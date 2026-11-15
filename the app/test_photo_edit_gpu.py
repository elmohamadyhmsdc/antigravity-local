"""Opt-in real local-model smoke test on an artificial, person-free still life."""
import argparse
import json
import shutil
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import photo_edit


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--operation',choices=['remove','replace'],default='remove')
    parser.add_argument('--model', choices=photo_edit.SUPPORTED_MODELS, default=photo_edit.DEFAULT_MODEL)
    parser.add_argument('--steps', type=int, default=26)
    parser.add_argument('--reference', action='append', type=Path, default=[])
    args = parser.parse_args()
    root = Path(__file__).resolve().parent/'build/photo-edit-2026-11-09'/args.operation
    if args.model != photo_edit.DEFAULT_MODEL:
        root /= args.model
    if args.reference:
        if args.operation != 'replace' or args.model != photo_edit.DEFAULT_MODEL or len(args.reference) > photo_edit.MAX_REFERENCES:
            parser.error('Use up to three references with Realistic Vision Replace.')
        root /= 'guided'
    root.mkdir(parents=True,exist_ok=True)
    image = Image.new('RGB',(960,640),(195,214,240))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0,390,960,640),fill=(90,108,146))
    for x in range(0,960,120): draw.line((x,390,x,640),fill=(86,103,140),width=2)
    draw.ellipse((375,470,590,525),fill=(70,85,120))
    draw.rounded_rectangle((410,300,560,495),radius=24,fill=(177,37,35))
    draw.ellipse((410,285,560,330),fill=(215,65,50))
    image.save(root/'input.image',format='PNG')
    mask = Image.new('L',image.size,0)
    ImageDraw.Draw(mask).rectangle((365,265,605,535),fill=255)
    mask.save(root/'input.mask',format='PNG')
    assert photo_edit.ready(), 'Missing local model assets'
    started = time.monotonic()
    for index, source in enumerate(args.reference):
        shutil.copyfile(source, root/f'input.refs.{index:04d}')
    meta = photo_edit.edit_photo(dict(type='edit_image',params=dict(operation=args.operation,
        instruction='a small blue ceramic vase on a blue table' if args.operation == 'replace' else '',
        seed=123,steps=args.steps,model=args.model), request={'inputs': {'refs': args.reference}}),
        root,lambda p,m:print(f'{p:.0%} {m}',flush=True),lambda:False)
    result = np.asarray(Image.open(root/'result.png').convert('RGBA'))
    original = np.asarray(image.convert('RGBA'))
    selected = np.asarray(mask) >= 128
    assert result.shape == original.shape
    assert np.array_equal(result[~selected],original[~selected])
    changed = int(np.any(result[selected] != original[selected],axis=1).sum())
    assert changed > selected.sum()*.5
    meta.update(seconds=round(time.monotonic()-started,2),changed_selected_pixels=changed,
                total_selected_pixels=int(selected.sum()),result_bytes=(root/'result.png').stat().st_size)
    (root/'report.json').write_text(json.dumps(meta,indent=2),encoding='utf-8')
    print(json.dumps(meta,indent=2),flush=True)


if __name__ == '__main__':
    main()
