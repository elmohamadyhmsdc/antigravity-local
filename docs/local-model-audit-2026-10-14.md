# Local model audit — 2026-10-14

> Historical audit. Base weights were installed on October 18 and remaining
> SDXL FP16 weights on October 19. The missing-model list below is superseded.
> Current context: [Antigravity handoff](ANTIGRAVITY_HANDOFF.md) and
> [October 19 installation](local-model-installation-2026-10-19.md).

The user requested a search of **all of `D:\AndroidScan`** and prohibited Internet downloads on the current mobile connection. This audit used local filenames, file sizes, bounded safetensors headers, archive directory inspection and restricted tensor loading. It did not modify, move or delete model files. No weight downloads or package installation were performed.

The search enumerated 256,812 files, including hidden files and followed directory links. It covered `Comfy Desktop`, `DeepFaceLab`, `gallary`, `gallaryData` and `generative-models`. Recognized weight extensions were searched even inside environments; files without recognized extensions and partial downloads were also inspected outside package/install directories.

| Local files | Finding | Use in the current app |
|---|---|---|
| `D:/AndroidScan/gallary/the app/models/sd15_realistic_base.safetensors` | Complete safetensors layout, 3.97 GiB; SD1.5 UNet has 4 input channels | Already used successfully for real LoRA training and generation. It is not the 9-channel inpainting UNet required by the current Restyle engine. |
| `D:/AndroidScan/gallary/the app/models/loras/*.safetensors` | Existing trained character LoRAs | A real portrait generation round trip passed with `pass.safetensors`. |
| `D:/AndroidScan/gallary/the app/models/undress/h94--IP-Adapter/models/ip-adapter-plus_sd15.bin` | 150.7 MiB; restricted `torch.load(weights_only=True)` passed | Reusable SD1.5 reference adapter. |
| `D:/AndroidScan/gallary/the app/models/undress/h94--IP-Adapter/models/image_encoder/model.safetensors` | Complete safetensors layout, 2.35 GiB; encoder configuration is present | Reusable reference-image encoder. The adjacent `pytorch_model.bin` is another weight format, not a second feature. |
| `D:/AndroidScan/gallary/the app/models/undress/lllyasviel--ControlNet/annotator/ckpts/body_pose_model.pth` | 199.6 MiB; restricted tensor load passed | Reusable OpenPose body detector. |
| Same folder: `hand_pose_model.pth` | 140.5 MiB; restricted tensor load passed | Reusable OpenPose hand detector. The current loader also expects `facenet.pth`, which was not found in this tree. |
| `D:/AndroidScan/gallary/the app/models/` Reface ONNX files | InsightFace swapper, HyperSwap, GPEN, CodeFormer, parser and XSeg files present | V3 Reface API round trip passed. The WD14 tagger is now excluded from the list of DFM face models. |
| `D:/AndroidScan/generative-models/checkpoints/sv4d2.safetensors` and `sv4d2_8views.safetensors` | Each has a complete safetensors layout, 11.16 GiB | The local README identifies these as video-to-4D/novel-view models. Their architecture differs from SD1.5/SDXL clothing inpainting, so they are not drop-in Restyle weights. |

## What is still missing for this Restyle implementation

- The actual inpainting weights under `Uminosachi/realisticVisionV51_v51VAE-inpainting`; its bundled directory contains configuration files but no complete component weights.
- `lllyasviel/control_v11p_sd15_openpose` ControlNet weights. OpenPose body/hand *detectors* do not replace this diffusion ControlNet.
- The remaining OpenPose annotator face weights (`facenet.pth`). Body and hand weights above can be reused in a future complete setup.
- `diffusers/stable-diffusion-xl-1.0-inpainting-0.1` for the optional refinement stage.

The clothes parser is available from the existing local Hugging Face cache outside this tree. The capabilities probe checks real component weights rather than accepting a configuration folder as a working engine.

## Partial downloads and archives

Found **69 `.incomplete` files totaling 36.12 GiB**: 41 truncated ZIP/PyTorch containers, one truncated SV4D safetensors file and 27 unrecognized/empty fragments. No complete recoverable weight container was identified. They were left untouched.

`facesets.rar`, `fill50k.zip`, `models.zip` and `Model_SAEHD.zip` did not contain the required diffusion weight files. Faceset `.pak` files are face training data, not Restyle model weights. The `Comfy Desktop` folder in this tree contains the installed desktop program; no separate usable diffusion checkpoint was found there.

This is a local inventory, not a request to download or delete anything. The present build can use Reface and Character LoRA; Restyle remains unavailable until its required local weights are supplied, or a separately designed alternative pipeline is implemented.
