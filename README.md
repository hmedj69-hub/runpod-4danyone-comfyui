[README.md](https://github.com/user-attachments/files/32326868/README.md)
# ComfyUI + SplatKit (4DAnyone) - template RunPod

Ready-to-use Docker image turning amonocular video into a 4D Gaussian
Splatting sequence, on RunPod.

Built and validated on **RTX 5090 (32 GB)**.

```
ghcr.io/hmedj69-hub/runpod-4danyone-comfyui:latest
```

## Quick start

### 1. Create the RunPod template

| Field | Value |
|---|---|
| Container image | `ghcr.io/hmedj69-hub/runpod-4danyone-comfyui:latest` |
| Container disk | 30 GB |
| Volume disk | 60 GB, mounted at `/workspace` |
| HTTP ports | `8188` (label: ComfyUI), `8888` (label: Jupyter) |
| TCP ports | `22` (label: SSH) |

RunPod requires a **label** for every port, otherwise creation fails.

### 2. Deploy

Pick a GPU with at least **32 GB of VRAM** (see below), start the pod, then
**Connect → ComfyUI (8188)**.

### 3. Load the workflow

Open the **Workflows** sidebar and click the workflow.

> ⚠️ ComfyUI does **not** auto-open a workflow on startup. It shows up in the
> list; the user clicks it. One click, not zero.

## GPU: measured, not assumed

| Card | 16 views / 121 frames |
|---|---|
| RTX 4090 (24 GB) | ❌ **fails** - `OutOfMemoryError`, even with `low_vram=true` and SageAttention (3 attempts) |
| RTX 5090 (32 GB) | ✅ works |

Upstream reports a ~25 GB peak and still lists *"Low-memory inference
(<32 GB)"* as an unchecked TODO. **24 GB is not headroom, it's a wall.**

Other plausible but **untested** cards: RTX 6000 Ada (48 GB), L40S (48 GB),
A40 / A6000 (48 GB, Ampere - cheaper but slower).

> ⏱️ **Missing number**: generation time **without the Turbo LoRA** has not
> been measured. Turbo cuts denoising to 4 steps; without it, expect
> significantly longer. See Licensing for why this matters.

## First boot

1. SSH and JupyterLab (relaunched - our `ENTRYPOINT` replaces RunPod's)
2. Symlinks `models`, `output`, `input`, `user` to `/workspace` (persistent)
3. **Model download** (~20 GB, 10–20 min) - once only, guarded by a marker
4. Real CUDA smoke test, then backend manifest
5. ComfyUI on port 8188

The smoke test is not decorative: if CUDA fails, the manifest records
`cuda_smoke_test: false` and the 4DAnyone nodes **refuse to start**. That is
deliberate - a clear refusal beats a crash at 8% after ten minutes.

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `COMFY_PORT` | `8188` | ComfyUI listening port |
| `JUPYTER_PASSWORD` | empty | **Jupyter token - empty means no authentication** |
| `SKIP_MODEL_DOWNLOAD` | `0` | `1` if models are already present |
| `COMFY_EXTRA_ARGS` | empty | extra ComfyUI arguments |

> ⚠️ Without `JUPYTER_PASSWORD`, Jupyter runs **unauthenticated**: anyone with
> the proxy URL reaches your files. RunPod does the same by default, but it is
> worth knowing.

## What's inside

- ComfyUI + ComfyUI-Manager
- ComfyUI-SplatKit and ComfyUI-Mickmumpitz-Nodes
- 4D backend: isolated Python 3.11 venv, torch 2.8.0 / CUDA 12.8 /
  gsplat 1.4.0, SageAttention
- **Export PLY Sequence** node (provided here)

### The Linux backend

SplatKit ships only a Windows `installer.bat`, and its release notes say Linux
is unsupported. **That is true of the installer, not the code**:
`venv_python()` already returns `bin/python` off Windows, and the contract
computes `sys.platform` at runtime.

This repo reproduces on Linux what the Windows installer builds.
**Not a single line of SplatKit's code is modified.**

gsplat 1.4.0 is validated on Blackwell (RTX 5090).

### No SMPL-X

The 4DAnyone vendored inside SplatKit uses **SAM 3D Body** instead of
GVHMR/SMPL-X - there is no `import smplx` anywhere. The Max-Planck academic
licence, which forbids redistribution, **does not apply**.

## Licensing

Weights are **downloaded from HuggingFace at startup**, not baked into the
image. This repository redistributes no model.

| Component | Licence | Commercial use |
|---|---|---|
| 4DAnyone checkpoint | Apache-2.0 | ✅ |
| Wan2.2 VAE, prompt_context | Apache-2.0 | ✅ |
| `smplx_to_goliath70` regressor | Apache-2.0 (+ Sapiens2 schema, Meta) | ✅ |
| VGG-19 perceptual | CC BY 4.0 | ✅ **attribution required** |
| SAM 3D Body | SAM License (Meta) | ✅ usage restrictions |
| BiRefNet | see upstream repo | — |
| ComfyUI-SplatKit | MIT | ✅ |
| ComfyUI | GPL-3.0 | ✅ for use |
| **Turbo LoRA** | **CC BY-NC-SA 4.0** | ❌ **non-commercial** |

### ⚠️ The Turbo LoRA is not commercially usable

`Wan22_TI2V_5B_Turbo_lora_rank_64_fp16.safetensors` is **CC BY-NC-SA 4.0**,
inherited from the upstream Turbo model. Ant Research states: *"Kijai declares
no separate adapter license, and this repository grants no additional rights"*.

**NC** = non-commercial. **SA** = share-alike.

For commercial work - music videos, client jobs, monetised content - set the
**4DAnyone Model Loader** node to:

```
turbo       = false
turbo_lora  = none
```

Generation will be slower; everything else stays free to use. Attribution
never buys off a usage restriction.

### Attribution

- **VGG-19**: Oxford Visual Geometry Group, MatConvNet distribution (CC BY 4.0)
- **SAM 3D Body**: Meta - the SAM License carries usage restrictions (trade
  controls, weapons-related prohibitions) and its text must travel with any
  redistribution

These belong to **software distribution**, not to your renders: your video
credits owe nothing - VGG-19 is a computation tool and does not appear in the
output.

### ⚠️ Likeness rights

No software licence covers this, and it is the most serious risk in this
pipeline.

You are not producing a video of someone: you are producing a **manipulable 3D
model of their person**, from angles never filmed. A standard filming release
does not anticipate that.

Obtain explicit written consent from everyone filmed, stating the process, the
purpose, the exploitation period and what happens to the model afterwards.

> This document is not legal advice. The licences cited are verifiable at the
> links above; for anything carrying real liability, consult a professional.

## Credits

- [4DAnyone](https://github.com/ant-research/4DAnyone) - Ant Research,
  Zhejiang University, Robbyant, HKUST
- [ComfyUI-SplatKit](https://github.com/mickmumpitz/ComfyUI-SplatKit) - mickmumpitz
- [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
- [gsplat](https://github.com/nerfstudio-project/gsplat) - Nerfstudio
- [SAM 3D Body](https://github.com/facebookresearch/sam-3d-body) - Meta
