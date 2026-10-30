"""Opt-in isolated inference over every image in explicitly selected folders.

Uses real local HumanArt weights through the mobile API/worker; never imports
the desktop database or touches the user's phone library. Results are counts,
timings and errors, not labelled accuracy. No downloads.
"""
import argparse
import json
import os
import time
from pathlib import Path

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', action='append', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    import cv2
    import numpy as np
    from fastapi.testclient import TestClient
    from mobile_api.app import create_app
    from mobile_api.engines import InsightEngines, CapabilityProbe
    from mobile_api.testing import make_test_context
    from character_detection import similarity
    from body_detector import MODELS_DIR, MODEL_SPECS
    spec = MODEL_SPECS['person']
    assert (MODELS_DIR / spec['file']).stat().st_size == spec['onnx_size']
    extensions = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif', '.avif', '.heic', '.heif'}
    files = sorted({p.resolve() for source in args.source for p in source.rglob('*') if p.is_file()})
    report = dict(total_files=len(files), images=0, decoded=0, with_characters=0,
                  character_detections=0, no_detection=0, unsupported=0, errors=[], folders={},
                  notes='Unlabelled corpus: detection counts do not establish precision or recall.')
    synthetic = {}
    engines = InsightEngines()
    context = make_test_context(args.output / 'isolated-server', engines=engines, probe=CapabilityProbe())
    device = context.auth.add_device('Isolated character QA')
    start = time.monotonic()
    with TestClient(create_app(context)) as client:
        for index, path in enumerate(files):
            if path.suffix.lower() not in extensions:
                report['unsupported'] += 1
                continue
            report['images'] += 1
            group = path.parent.name
            folder = report['folders'].setdefault(group, dict(images=0, decoded=0, with_characters=0, detections=0))
            folder['images'] += 1
            try:
                image = cv2.imdecode(np.fromfile(str(path), np.uint8), cv2.IMREAD_COLOR)
                if image is None:
                    raise ValueError('unsupported or unreadable image codec')
                scale = min(1, 2560 / max(image.shape[:2]))
                if scale < 1:
                    image = cv2.resize(image, (round(image.shape[1]*scale), round(image.shape[0]*scale)), interpolation=cv2.INTER_AREA)
                payload = cv2.imencode('.jpg', image, [cv2.IMWRITE_JPEG_QUALITY, 95])[1].tobytes()
                response = client.post('/v1/analyze/image',
                    headers={'Authorization': 'Bearer ' + device['token']},
                    files={'image': ('qa.jpg', payload, 'image/jpeg')},
                    data={'options': json.dumps(dict(detect_characters=True, detect_bodies=False, return_crops=False))})
                if response.status_code != 200:
                    raise RuntimeError(f'HTTP {response.status_code}: {response.text[:250]}')
                data = response.json()
                assert data['faces'] == [] and data['bodies'] == []
                count = len(data['characters'])
                report['decoded'] += 1
                report['with_characters'] += int(count > 0)
                report['character_detections'] += count
                report['no_detection'] += int(count == 0)
                folder['decoded'] += 1
                folder['with_characters'] += int(count > 0)
                folder['detections'] += count
                if path.parent.name == 'samples':
                    synthetic[path.stem] = data
            except Exception as error:
                report['errors'].append(dict(folder=group, name=path.name, error=str(error)))
            if (index + 1) % 20 == 0 or index + 1 == len(files):
                print(f"{index+1}/{len(files)} files: {report['with_characters']} with characters, "
                      f"{report['character_detections']} detections, {len(report['errors'])} errors", flush=True)
                (args.output / 'progress.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        assert client.get('/v1/health').status_code == 200
    report['seconds'] = round(time.monotonic() - start, 2)
    report['synthetic_pairs'] = {}
    for a, b in [('anime-red-standing', 'anime-red-walking'), ('anime-red-standing', 'cartoon-green-standing')]:
        left, right = synthetic.get(a, {}).get('characters', []), synthetic.get(b, {}).get('characters', [])
        report['synthetic_pairs'][a + ' vs ' + b] = similarity(left[0]['descriptor'], right[0]['descriptor']) if left and right else None
    (args.output / 'synthetic-responses.json').write_text(json.dumps(synthetic), encoding='utf-8')
    (args.output / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)
    if report['errors']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
