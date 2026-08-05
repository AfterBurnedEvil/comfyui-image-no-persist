FROM runpod/comfyui:cuda13.0

ARG DEBIAN_FRONTEND=noninteractive

# Keep the CUDA 13 / PyTorch environment supplied by RunPod. Add only the
# tools commonly needed when ComfyUI Manager installs custom nodes at runtime.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        aria2 \
        cmake \
        git-lfs \
        ninja-build \
        pkg-config \
    && git lfs install --system \
    && rm -rf /var/lib/apt/lists/*

# Fetch the latest official ComfyUI at image-build time. The RunPod base image
# pins its CUDA-enabled Torch packages in this constraints file; applying it
# prevents ComfyUI's unpinned Torch requirements from replacing that stack.
RUN git clone --depth 1 https://github.com/Comfy-Org/ComfyUI.git /opt/ComfyUI \
    && python3 -m pip install --no-cache-dir \
        --constraint /opt/comfyui-runtime-constraints.txt \
        --requirement /opt/ComfyUI/requirements.txt \
    && python3 -m pip install --no-cache-dir \
        --constraint /opt/comfyui-runtime-constraints.txt \
        --requirement /opt/ComfyUI/manager_requirements.txt \
    && if find /opt/ComfyUI/models -type f \
        \( -iname '*.ckpt' -o -iname '*.safetensors' -o -iname '*.gguf' \
           -o -iname '*.pt' -o -iname '*.pth' -o -iname '*.bin' \) \
        -print -quit | grep -q .; then \
        echo 'Unexpected model weight found in /opt/ComfyUI/models' >&2; \
        exit 1; \
    fi \
    && rm -rf /opt/comfyui-baked

COPY --chmod=755 start.sh /usr/local/bin/start-comfy-container
COPY --chmod=755 restart-comfy.sh /usr/local/bin/restart-comfy

WORKDIR /opt/ComfyUI

EXPOSE 22 8080 8188

# Deliberately replace the base image's /start.sh so nothing is copied to
# /workspace. ComfyUI runs directly from /opt/ComfyUI in the image layer.
ENTRYPOINT ["/usr/local/bin/start-comfy-container"]
