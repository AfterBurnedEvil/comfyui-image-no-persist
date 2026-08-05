# Disposable RunPod ComfyUI

A model-free, disposable ComfyUI image based on the official
`runpod/comfyui:cuda13.0` image. It keeps RunPod's CUDA 13 / PyTorch CUDA 13
environment while bypassing the base image's persistent `/workspace` setup.

ComfyUI is cloned from the official repository and installed while the image is
built. Container startup performs no ComfyUI clone, pull, update, or workspace
copy. ComfyUI runs directly from `/opt/ComfyUI`.

## Included services

| Service | Port | Notes |
| --- | ---: | --- |
| ComfyUI | `8188/http` | Starts automatically and listens on `0.0.0.0` |
| File Browser | `8080/http` | Browses the disposable `/opt/ComfyUI` tree |
| SSH | `22/tcp` | Uses RunPod's `PUBLIC_KEY` environment variable |

The supported built-in ComfyUI Manager is enabled. It can install missing
custom nodes, their Python requirements, and supported models during the Pod's
lifetime. Git, Git LFS, wget, curl, aria2, ffmpeg, C/C++ build tools, CMake,
Ninja, and Python development headers are available for runtime node installs.

No checkpoints, diffusion models, LoRAs, VAEs, text encoders, ControlNets,
upscalers, GGUF files, or other generation weights are added by this repository.
Anything downloaded through Manager is stored only in the disposable container.

## RunPod template settings

Use these settings, replacing `<owner>/<repo>` with the lowercase GitHub
repository path:

| Setting | Value |
| --- | --- |
| Container image | `ghcr.io/<owner>/<repo>:latest` |
| Container disk | `200 GB` |
| Persistent storage | `0 GB` |
| Network volume | **NONE** |
| Exposed ports | `8188/http`, `8080/http`, `22/tcp` |
| RunPod Start Command | Leave empty |

If the GHCR package is private, configure RunPod registry credentials. A public
package needs no registry credentials.

## Restart ComfyUI

After Manager installs or updates custom nodes, restart only ComfyUI from an SSH
or web-terminal session:

```bash
restart-comfy
```

The container supervisor stops the current ComfyUI process and immediately
starts it again with the same Python environment and arguments. Logs continue to
appear in the RunPod container logs.

Optional extra ComfyUI flags can be supplied through `COMFYUI_EXTRA_ARGS`, for
example `--preview-method auto`. Do not set a RunPod Start Command.

## Publishing

GitHub Actions is the intended and only build environment. A push to `main`
publishes:

- `ghcr.io/<owner>/<repo>:latest`
- `ghcr.io/<owner>/<repo>:sha-<full-commit-sha>`

Pushing a tag such as `v1.2.3` also publishes `1.2.3` and `1.2`. The workflow
builds `linux/amd64` with Docker Buildx, authenticates to GHCR using
`GITHUB_TOKEN`, and uses the GitHub Actions build cache.

The first real image build should happen only after these files are committed
and pushed to GitHub.
