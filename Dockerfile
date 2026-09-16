# =============================================================================
#  ComfyUI + SplatKit (4DAnyone) - image RunPod
#
#  Tout est installe sous /opt, JAMAIS sous /workspace : RunPod monte le
#  volume par-dessus /workspace au demarrage et effacerait ce qui y serait
#  bake. Seuls les modeles, entrees et sorties vivent sur /workspace, via
#  des liens symboliques poses par l entrypoint.
#
#  Versions imposees par le contrat de ComfyUI-SplatKit 1.2.2
#  (core/splatting/runtime.py) : Python 3.11 / torch 2.8.0 /
#  torchvision 0.23.0 / CUDA 12.8 / gsplat 1.4.0.
# =============================================================================
FROM runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404

SHELL ["/bin/bash", "-lc"]

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    COMFY_ROOT=/opt/ComfyUI \
    PACK=/opt/ComfyUI/custom_nodes/ComfyUI-SplatKit \
    WORKSPACE=/workspace

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates ffmpeg libgl1 libglib2.0-0 unzip \
    && rm -rf /var/lib/apt/lists/*

# --- 1. ComfyUI + node packs -------------------------------------------------
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git ${COMFY_ROOT} \
 && cd ${COMFY_ROOT}/custom_nodes \
 && git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git \
 && git clone --depth 1 https://github.com/mickmumpitz/ComfyUI-SplatKit.git \
 && git clone --depth 1 https://github.com/mickmumpitz/ComfyUI-Mickmumpitz-Nodes.git

# --- 2. venv hote (celui qui fait tourner ComfyUI) ---------------------------
RUN python -m venv --system-site-packages /opt/venv \
 && source /opt/venv/bin/activate \
 && pip install --upgrade pip \
 && pip install -r ${COMFY_ROOT}/requirements.txt \
 && pip install -r ${PACK}/requirements.txt \
 && pip install hf_transfer "huggingface_hub[cli]"

# --- 3. backend 4D (venv isole, contrat SplatKit) ----------------------------
# Le smoke test CUDA n est PAS fait ici : aucun GPU pendant un build.
# L entrypoint le lance au demarrage et ecrit le manifeste.
ENV UV_INSTALL_DIR=/opt/uv \
    UV_PYTHON_INSTALL_DIR=/opt/uv-python \
    BACKEND=/opt/ComfyUI/custom_nodes/ComfyUI-SplatKit/bin/splat_backend
ENV PATH=${UV_INSTALL_DIR}:${PATH}

RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
 && uv python install 3.11 \
 && uv venv --python 3.11 ${BACKEND}/venv \
 && uv pip install --python ${BACKEND}/venv/bin/python \
      --index-url https://download.pytorch.org/whl/cu128 \
      torch==2.8.0 torchvision==0.23.0 \
 && uv pip install --python ${BACKEND}/venv/bin/python ninja \
 && ( uv pip install --python ${BACKEND}/venv/bin/python gsplat==1.4.0 \
        --index-url https://docs.gsplat.studio/whl/pt28cu128 \
      || uv pip install --python ${BACKEND}/venv/bin/python gsplat==1.4.0 ) \
 && grep -vE "^(torch|torchvision|gsplat)==" ${PACK}/tools/splatting/requirements.txt \
      | grep -vE "^[[:space:]]*(#|$)" > /tmp/req_trainer.txt \
 && uv pip install --python ${BACKEND}/venv/bin/python -r /tmp/req_trainer.txt \
 && grep -vE "^(torch|torchvision)[><=]" ${PACK}/vendored/4danyone/requirements.txt \
      | grep -vE "^[[:space:]]*(#|$)" > /tmp/req_generator.txt \
 && uv pip install --python ${BACKEND}/venv/bin/python -r /tmp/req_generator.txt \
 && uv pip install --python ${BACKEND}/venv/bin/python sageattention \
 && cp -a ${PACK}/vendored/4danyone ${BACKEND}/4DAnyone

# --- 4. node d export PLY ----------------------------------------------------
COPY custom_nodes/ComfyUI-SplatKit-PlyExport/__init__.py \
     ${COMFY_ROOT}/custom_nodes/ComfyUI-SplatKit-PlyExport/__init__.py

# --- 5. workflow charge par defaut ------------------------------------------
COPY workflows/ ${COMFY_ROOT}/user/default/workflows/

# --- 6. entrypoint -----------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8188
ENTRYPOINT ["/entrypoint.sh"]
