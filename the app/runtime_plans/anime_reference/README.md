# Proposed isolated anime reference runtime — approval required

The installed generic SD1.5/IP-Adapter reference path failed real image identity/quality checks for both fixture kinds; a bounded source-pixel initialization also failed. Exact locality and target selection passed, so these failures cannot be called successful faithful replacement.

Candidate: [official MimicBrush implementation](https://github.com/ali-vilab/MimicBrush), a model trained for masked reference imitation with two U-Nets. It is a candidate to evaluate, not a promised quality fix. Official runtime pins are materially different from the installed venv_ai (diffusers0.39 / transformers5.14 / torch2.5.1cu121). Do not downgrade or install into any existing environment.

Concrete proposed boundary:

- New directory only: the app/venv_reference. Use the already installed Python3.10 interpreter to create a fresh venv. Refuse an existing destination; no deletion, moving or reuse of an existing environment.
- Install PyTorch2.0.1 and torchvision0.15.2 from the official cu118 wheel index into that new venv; these wheels carry their own runtime libraries. Do not install/change the machine CUDA toolkit, drivers or PATH.
- Install requirements-inference.txt into the new venv only. pip23.3.2 inside that venv is needed for the official older OmegaConf metadata. The list deliberately omits Gradio/UI/benchmark packages from the upstream demo.
- Audit and vendor the Apache-2.0 inference source with pinned revision and license before executing it. Add missing inference dependencies only inside this environment and record them. Do not use uploaded executable serialization; official downloaded weights must have recorded hashes and load weights-only where possible.
- Model files under models/reference/mimicbrush with partial-file/length/hash verification. Prior user permission covers model/asset downloads; no downloads/installations have been performed for this candidate yet.
- Integrate through the existing isolated worker/owned job/ACK lifecycle. No additional product server, port, APK or deployment. Run CPU import/contract tests before serial GPU acceptance on the saved fictional neutral fixtures.
- Preserve exact decoded pixels outside selected masks; evaluate source identity relative to original target and inspect images/video. If the candidate fails, retain a failed/experimental support state. Do not advertise full parity from installed files or successful HTTP requests.

Official sources: [requirements](https://raw.githubusercontent.com/ali-vilab/MimicBrush/main/requirements.txt), [inference](https://github.com/ali-vilab/MimicBrush/blob/main/run_inference_benchmark.py), [paper](https://arxiv.org/abs/2406.07547).

This is a reviewable installation/evaluation plan. The current chat permission authorizes GPU tests with existing models and environments; creating/installing a new runtime requires explicit user permission under CLAUDE.md.
