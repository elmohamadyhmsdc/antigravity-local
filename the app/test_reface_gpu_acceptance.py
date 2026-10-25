r"""Opt-in GPU correctness check using local source/target photos; no library writes.

venv\Scripts\python test_reface_gpu_acceptance.py --source source.png --target target.png
"""
from pathlib import Path
import argparse
import sys, json
def main():
    sys.path.insert(0, str(Path.cwd()))
    import cv2
    import numpy as np
    from reface_engine import Faceset, FaceData
    from reface_engine_v3 import RefaceEngineV3
    from reface_video_io import validate_video
    from job_manager import Job, JobStatus, finish_v3_video

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--target',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=Path('../mobile/build/reface-acceptance'))
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True,exist_ok=True)
    engine = RefaceEngineV3(output_dir=str(out/'render'))
    try:
        source_img, target_img = cv2.imread(str(args.source)), cv2.imread(str(args.target))
        assert source_img is not None and target_img is not None, 'Choose readable source and target photos'
        source_face = max(engine._detect(source_img, embeddings=True), key=lambda f: float((f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1])))
        source = Faceset('acceptance')
        source.add_face(FaceData('',source_face.embedding,(0,0,0),[],.9))
        frame = np.concatenate([cv2.resize(source_img,(640,360)),cv2.resize(target_img,(640,360))],axis=1)
        faces = engine._detect(frame, embeddings=True)
        assert len(faces)>=2, 'The two-person sample must contain two detected faces'
        index = max(range(len(faces)),key=lambda i:faces[i].bbox[0])
        refs = [f.normed_embedding.tolist() for f in faces]
        image = out/'two-person.png'
        cv2.imwrite(str(image),frame)
        result = engine.reface_image_v3(str(image),source,[index],refs)
        assert result.success and result.faces_swapped==1, result
        rendered = cv2.imread(result.output_path)
        assert np.array_equal(rendered[:,:600],frame[:,:600]), 'Unselected person/background changed in lossless photo'
        video = out/'short-input.mp4'
        writer,proc = engine._open_writer(video,30000/1001,1280,360)
        for _ in range(9): engine._write(writer,proc,frame)
        engine._close_writer(writer,proc)
        counts=[]
        part1 = engine.reface_video_v3(str(video),source,[index],target_face_embeddings=refs,finalize=False,
                                      progress_callback=lambda count,total:(counts.append(count) or count<3))
        assert part1.success and counts[-1]==3, part1
        part2 = engine.reface_video_v3(str(video),source,[index],target_face_embeddings=refs,finalize=False,resume_from_frame=3)
        assert part2.success, part2
        job = Job(id='gpu-acceptance',job_type='reface_video_v3',status=JobStatus.RUNNING,progress=0,message='',created_at='',
                  frames_done=3,part_files=[part1.output_path])
        joined = finish_v3_video(job,part2.output_path,6,str(video))
        info = validate_video(joined,9,30000/1001)
        report = dict(photo_faces_swapped=result.faces_swapped,unselected_photo_unchanged=True,
                      first_part_frames=part1.details['frames_done'],second_part_frames=part2.details['frames_done'],
                      video=info,settings=result.details['settings'],image=result.output_path,output=str(joined))
        (out/'gpu-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print('PASS: selected-face GPU photo preserves the bystander exactly; 3+6 frame pause/resume video joins to 9 frames at 29.97 fps',flush=True)
    finally:
        if engine.compositor._pool is not None: engine.compositor._pool.shutdown(wait=True)


if __name__ == "__main__":
    main()
