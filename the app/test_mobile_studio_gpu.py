"""Opt-in, local-model-only Reface round trip against the real GPU engines.

Usage: venv\Scripts\python test_mobile_studio_gpu.py --source photo.jpg --target other.jpg
Uses a temporary API workspace and does not import the desktop user database.
"""

import argparse
import hashlib
import os
import tempfile
import time
import zipfile
from pathlib import Path

os.environ['HF_HUB_OFFLINE']='1'
os.environ['TRANSFORMERS_OFFLINE']='1'

import cv2
from fastapi.testclient import TestClient
from mobile_api import APP_DIR
from mobile_api.app import create_app
from mobile_api.engines import CapabilityProbe, InsightEngines
from mobile_api.gpu_guard import GpuGuard
from mobile_api.testing import make_test_context


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True,type=Path)
    parser.add_argument('--target',required=True,type=Path)
    parser.add_argument('--restyle',action='store_true',help='Also run one clothing restyle of the target.')
    parser.add_argument('--train-dataset',type=Path,help='Use five captioned photos for one tiny training epoch.')
    parser.add_argument('--build-dataset',type=Path,help='Build and caption a real dataset from five local person photos.')
    parser.add_argument('--generate',action='store_true',help='Generate one portrait with the tiny trained LoRA.')
    parser.add_argument('--generate-lora',type=Path,help='Generate with an existing local safetensors file instead of training.')
    args=parser.parse_args()
    def photo(path):
        image=cv2.imread(str(path))
        if image is None:raise ValueError('Choose a readable photo.')
        if max(image.shape[:2])>2560:
            scale=2560/max(image.shape[:2]);image=cv2.resize(image,None,fx=scale,fy=scale)
        return cv2.imencode('.jpg',image)[1].tobytes()
    with tempfile.TemporaryDirectory(prefix='ag_mobile_gpu_') as tmp:
        ctx=make_test_context(Path(tmp),engines=InsightEngines(),probe=CapabilityProbe(),
                              max_upload_bytes=128*1024*1024,blob_cache_bytes=256*1024*1024)
        ctx.gpu=GpuGuard(APP_DIR/'jobs',ctx.workspace.jobs_dir)
        with TestClient(create_app(ctx)) as client:
            device=ctx.auth.add_device('GPU acceptance fixture')
            headers={'Authorization':'Bearer '+device['token']}
            print('Analyzing source on the GPU...',flush=True)
            response=client.post('/v1/analyze/image',headers=headers,files={'image':('source.jpg',photo(args.source),'image/jpeg')},
                                 data={'options':'{"detect_bodies":false,"min_quality":0.4}'})
            assert response.status_code==200,response.text
            faces=[f for f in response.json()['faces'] if f['passes_gate']]
            assert faces,'No usable source face in this photo.'
            face=max(faces,key=lambda f:f['quality']['quality_score'])
            target=photo(args.target);sha=hashlib.sha256(target).hexdigest()
            assert client.put('/v1/blobs/'+sha,headers=headers,content=target).status_code in (201,204)
            response=client.post('/v1/jobs',headers=headers,json={'type':'reface_image_v3','client_job_id':'gpu-fixture',
                'inputs':{'target':sha},'params':{'source_faces':[{'embedding':face['embedding'],'quality':face['quality']['quality_score'],'pose':face['quality']['pose']}]}})
            assert response.status_code==201,response.text
            job=response.json()['job_id'];deadline=time.monotonic()+240
            print('Rendering a real V3 image job...',flush=True)
            while time.monotonic()<deadline:
                status=client.get('/v1/jobs/'+job,headers=headers).json()
                if status['status'] in ('completed','failed'):break
                time.sleep(.5)
            assert status['status']=='completed',status
            manifest=client.get(f'/v1/jobs/{job}/result',headers=headers).json()
            output=client.get(f'/v1/jobs/{job}/result/result.png',headers=headers).content
            entry=manifest['files'][0]
            assert len(output)==entry['size'] and hashlib.sha256(output).hexdigest()==entry['sha256']
            assert client.delete('/v1/jobs/'+job,headers=headers).status_code==204
            print('PASS: GPU analysis -> embedding-only V3 job -> verified PNG -> ACK/purge.',flush=True)

            def upload(data):
                digest=hashlib.sha256(data).hexdigest()
                assert client.put('/v1/blobs/'+digest,headers=headers,content=data).status_code in (201,204)
                return digest
            def run(kind,params,inputs,filename):
                print(f'Starting real {kind}...',flush=True)
                response=client.post('/v1/jobs',headers=headers,json={'type':kind,'params':params,'inputs':inputs,'client_job_id':kind})
                assert response.status_code==201,response.text
                id=response.json()['job_id'];deadline=time.monotonic()+900;last=0
                while time.monotonic()<deadline:
                    status=client.get('/v1/jobs/'+id,headers=headers).json()
                    if status['status'] in ('completed','failed'):break
                    if time.monotonic()-last>15:
                        print(f"{kind}: {status['message']} ({status['progress']:.0%})",flush=True);last=time.monotonic()
                    time.sleep(.5)
                if status['status'] != 'completed':
                    for log in (ctx.workspace.jobs_dir/id).rglob('engine.log'):
                        print(log.read_text(encoding='utf-8',errors='replace')[-16000:],flush=True)
                assert status['status']=='completed',status
                manifest=client.get(f'/v1/jobs/{id}/result',headers=headers).json()
                data=client.get(f'/v1/jobs/{id}/result/{filename}',headers=headers).content
                entry=manifest['files'][0]
                assert len(data)==entry['size'] and hashlib.sha256(data).hexdigest()==entry['sha256']
                assert client.delete('/v1/jobs/'+id,headers=headers).status_code==204
                print(f'PASS: real {kind} -> verified artifact -> ACK/purge.',flush=True)
                return data
            if args.restyle:
                target=photo(args.target)
                run('undress_image',{'prompt':'Photorealistic fashion portrait, fully clothed in a blue tailored jacket and trousers, preserve the face, background and lighting',
                    'negative_prompt':'nudity, underwear, bad anatomy, watermark','steps':5,'refine':False,'seed':7},
                    {'image':upload(target)},'result.png')
            if args.build_dataset:
                import io
                images=sorted(args.build_dataset.rglob('*_face.jpg'))[:5]
                assert len(images)==5,'Need five person photos.'
                dataset=run('build_lora_dataset',{'trigger_word':'sksfixture','repeats':1,'anchor_embedding':face['embedding']},
                            {'images':[upload(photo(image)) for image in images]},'dataset.zip')
                with zipfile.ZipFile(io.BytesIO(dataset)) as archive:
                    assert len([name for name in archive.namelist() if name.endswith('.jpg')])>=5
            model = args.generate_lora.read_bytes() if args.generate_lora else None
            if args.train_dataset:
                import io
                images=[p for p in sorted(args.train_dataset.rglob('*_face.jpg')) if p.with_suffix('.txt').exists()][:5]
                assert len(images)==5,'Need five captioned fixture photos.'
                stream=io.BytesIO()
                with zipfile.ZipFile(stream,'w',compression=zipfile.ZIP_STORED) as archive:
                    for index,image in enumerate(images):
                        archive.writestr(f'1_sksfixture person/{index}.jpg',photo(image))
                        archive.writestr(f'1_sksfixture person/{index}.txt','sksfixture person, natural portrait, fully clothed')
                model=run('train_lora',{'trigger_word':'sksfixture','output_name':'fixture','base_checkpoint':'sd15_realistic_base',
                    'epochs':1,'network_dim':4,'network_alpha':2,'learning_rate':.0001,'batch_size':1,'max_resolution':512},
                    {'dataset':upload(stream.getvalue())},'lora.safetensors')
            if model is not None and (args.generate or args.generate_lora):
                import io
                portraits=run('generate_lora_images',{'trigger_word':'sksfixture','base_checkpoint':'sd15_realistic_base','num_images':1,
                    'steps':5,'seed':7,'multi_angle':False,'prompt':'sksfixture person, natural studio portrait, fully clothed'},
                    {'lora':upload(model)},'portraits.zip')
                with zipfile.ZipFile(io.BytesIO(portraits)) as archive:assert len(archive.namelist())==1


if __name__=='__main__':main()
