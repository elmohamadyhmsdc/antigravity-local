"""
Antigravity Local - headless DeepFaceLab runner

Runs INSIDE DeepFaceLab's own Python 3.6 (DeepFaceLab_NVIDIA_RTX3000_series/
_internal/python-3.6.8), launched by dfl_bridge.py. Keep it 3.6-compatible:
no dataclasses, no walrus, no f-string '=' specifiers.

DeepFaceLab asks its training options interactively. Here every question is
answered from a JSON file (matched by the start of the prompt) and anything
not listed takes DeepFaceLab's own default, so a run is reproducible and
needs no console. Training stops cleanly - model saved - when the stop file
appears: a watcher thread raises KeyboardInterrupt in the main thread, which
is exactly what DeepFaceLab's no-preview loop treats as "save and exit".

    python dfl_runner.py train  --dfl-root R --src S --dst D --model-dir M --name N
                                [--answers A.json] [--stop-file F] [--override]
    python dfl_runner.py export --dfl-root R --model-dir M --name N [--quantized]
    python dfl_runner.py extract --dfl-root R --src IMAGES --dst ALIGNED
    python dfl_runner.py xseg --dfl-root R --src ALIGNED --xseg-model DIR

Extraction and XSeg go through here too: both can ask which GPU to use, and
with no console attached that question would end the process.

Progress lines for the bridge:  @@dfl {"event": ..., ...}
"""

import argparse
import json
import os
import sys
import threading
import time

try:
    import _thread
except ImportError:  # pragma: no cover
    import thread as _thread


def emit(event, **data):
    data["event"] = event
    sys.stdout.write("@@dfl " + json.dumps(data) + "\n")
    sys.stdout.flush()


def patch_questions(answers, override):
    """Answer DeepFaceLab's interactive questions from `answers`."""
    from core.interact import interact as io

    def lookup(prompt, default):
        p = (prompt or "").strip()
        for key, value in answers.items():
            if key and p.startswith(key):
                emit("option", prompt=p, value=value)
                return value
        return default

    def input_int(s, default_value, *a, **k):
        return int(lookup(s, default_value))

    def input_number(s, default_value, *a, **k):
        return float(lookup(s, default_value))

    def input_bool(s, default_value, *a, **k):
        return bool(lookup(s, default_value))

    def input_str(s, default_value=None, *a, **k):
        v = lookup(s, default_value)
        return v if v is None else str(v)

    def input_in_time(s, max_time_sec):
        # Only asked as "Press enter in 2 seconds to override model settings."
        return bool(override)

    io.input_int = input_int
    io.input_number = input_number
    io.input_bool = input_bool
    io.input_str = input_str
    io.input_in_time = input_in_time


def watch_stop_file(path):
    def run():
        while True:
            if path and os.path.exists(path):
                emit("stopping")
                _thread.interrupt_main()
                return
            time.sleep(2.0)
    t = threading.Thread(target=run, daemon=True)
    t.start()


def cmd_train(args):
    answers = {}
    if args.answers:
        with open(args.answers, "r", encoding="utf-8") as f:
            answers = json.load(f)
    patch_questions(answers, args.override)
    watch_stop_file(args.stop_file)
    emit("start", name=args.name, model=args.model)

    from pathlib import Path
    from mainscripts import Trainer
    Trainer.main(model_class_name=args.model,
                 saved_models_path=Path(args.model_dir),
                 training_data_src_path=Path(args.src),
                 training_data_dst_path=Path(args.dst),
                 pretraining_data_path=None,
                 pretrained_model_path=None,
                 no_preview=True,
                 force_model_name=args.name,
                 force_gpu_idxs=[0],
                 cpu_only=False,
                 silent_start=True,
                 execute_programs=[],
                 debug=False)
    emit("stopped")


def cmd_export(args):
    patch_questions({"Export quantized?": bool(args.quantized)}, False)
    from pathlib import Path
    import models
    model = models.import_model(args.model)(is_exporting=True, saved_models_path=Path(args.model_dir),
                                            force_model_name=args.name, cpu_only=True)
    model.export_dfm()
    emit("exported", name=args.name)


def cmd_extract(args):
    patch_questions({}, False)
    from pathlib import Path
    from mainscripts import Extractor
    Extractor.main(detector="s3fd", input_path=Path(args.src), output_path=Path(args.dst),
                   output_debug=False, manual_fix=False, manual_output_debug_fix=False,
                   manual_window_size=1368, face_type="whole_face", max_faces_from_image=0,
                   image_size=512, jpeg_quality=90, cpu_only=False, force_gpu_idxs=[0])
    emit("extracted")


def cmd_xseg(args):
    patch_questions({}, False)
    from pathlib import Path
    from mainscripts import XSegUtil
    XSegUtil.apply_xseg(Path(args.src), Path(args.xseg_model))
    emit("masked")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["train", "export", "extract", "xseg"])
    ap.add_argument("--dfl-root", required=True)
    ap.add_argument("--model-dir")
    ap.add_argument("--name")
    ap.add_argument("--xseg-model")
    ap.add_argument("--model", default="SAEHD")
    ap.add_argument("--src")
    ap.add_argument("--dst")
    ap.add_argument("--answers")
    ap.add_argument("--stop-file")
    ap.add_argument("--override", action="store_true")
    ap.add_argument("--quantized", action="store_true")
    args = ap.parse_args()

    sys.path.insert(0, args.dfl_root)
    os.chdir(args.dfl_root)
    # What DeepFaceLab's own main.py does first: its worker pools are spawned,
    # and nn.initialize_main_env() enumerates the GPUs for every later call.
    import multiprocessing
    multiprocessing.set_start_method("spawn")
    from core.leras import nn
    nn.initialize_main_env()

    {"train": cmd_train, "export": cmd_export, "extract": cmd_extract, "xseg": cmd_xseg}[args.command](args)


if __name__ == "__main__":
    main()
