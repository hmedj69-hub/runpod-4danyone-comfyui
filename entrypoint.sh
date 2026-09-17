#!/usr/bin/env bash
# =============================================================================
#  Entrypoint - premier demarrage et demarrages suivants.
#
#  Ordre volontaire :
#    1. SSH et Jupyter (remplaces par notre ENTRYPOINT, donc a relancer)
#    2. liens vers /workspace (volume persistant)
#    3. modeles -> AVANT ComfyUI, sinon les menus des nodes sont vides
#    4. smoke test CUDA + manifeste (necessite un GPU, donc pas au build)
#    5. ComfyUI
# =============================================================================
set -euo pipefail

COMFY_ROOT=${COMFY_ROOT:-/opt/ComfyUI}
PACK=${PACK:-$COMFY_ROOT/custom_nodes/ComfyUI-SplatKit}
BACKEND=$PACK/bin/splat_backend
WS=${WORKSPACE:-/workspace}
VPY=$BACKEND/venv/bin/python
PORT=${COMFY_PORT:-8188}

echo "=================================================================="
echo "  ComfyUI + SplatKit (4DAnyone)"
echo "=================================================================="

# --- Activation SSH RunPod --------------------------------------------------
if [ -n "${PUBLIC_KEY:-}" ]; then
    mkdir -p /root/.ssh
    echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
    chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys
    service ssh start || true
fi

# --- Jupyter (port 8888) ----------------------------------------------------
# L image de base RunPod lance JupyterLab via son propre script de demarrage,
# que notre ENTRYPOINT remplace. On le relance donc nous-memes, sinon le port
# 8888 reste indefiniment en "Initializing" cote RunPod - et l utilisateur n a
# aucun moyen simple de recuperer ses archives PLY.
if command -v jupyter >/dev/null 2>&1; then
    echo "[jupyter] Demarrage sur le port 8888 ..."
    nohup jupyter lab \
        --allow-root --no-browser --ip=0.0.0.0 --port=8888 \
        --ServerApp.token="${JUPYTER_PASSWORD:-}" \
        --ServerApp.allow_origin="*" \
        --ServerApp.preferred_dir="$WS" \
        --FileContentsManager.delete_to_trash=False \
        > /tmp/jupyter.log 2>&1 &
else
    echo "[jupyter] jupyter introuvable - port 8888 inactif."
fi

# --- 1. persistance ---------------------------------------------------------
mkdir -p "$WS/models" "$WS/output" "$WS/input" "$WS/user"
for d in models output input user; do
    if [ ! -L "$COMFY_ROOT/$d" ]; then
        if [ -d "$COMFY_ROOT/$d" ]; then
            cp -an "$COMFY_ROOT/$d/." "$WS/$d/" 2>/dev/null || true
            rm -rf "$COMFY_ROOT/$d"
        fi
        ln -s "$WS/$d" "$COMFY_ROOT/$d"
    fi
done

# --- 2. modeles -------------------------------------------------------------
MARK="$WS/models/.provisioned"
if [ ! -f "$MARK" ] && [ "${SKIP_MODEL_DOWNLOAD:-0}" != "1" ]; then
    echo "[modeles] Premier demarrage - telechargement (~20 Go)."
    echo "[modeles] Compter 10 a 20 min. ComfyUI demarrera ensuite."
    source /opt/venv/bin/activate
    export HF_HUB_ENABLE_HF_TRANSFER=1
    cd "$WS/models"
    mkdir -p splatkit/4danyone splatkit/birefnet detection

    hf download AntResearch/4DAnyone --include "4danyone/*"   --local-dir /tmp/m1
    mv /tmp/m1/4danyone/*   splatkit/4danyone/ && rm -rf /tmp/m1
    hf download AntResearch/4DAnyone --include "perceptual/*" --local-dir /tmp/m2
    mv /tmp/m2/perceptual/* splatkit/4danyone/ && rm -rf /tmp/m2
    hf download ZhengPeng7/BiRefNet --local-dir splatkit/birefnet
    hf download Comfy-Org/sam-3d-body --include "detection/*" --local-dir /tmp/m3
    mv /tmp/m3/detection/*  detection/ && rm -rf /tmp/m3

    touch "$MARK"
    echo "[modeles] Termine."
else
    echo "[modeles] Deja presents - skip."
fi

# --- 3. backend : smoke test puis manifeste ---------------------------------
# Refait a chaque demarrage : le GPU peut changer d un pod a l autre, et un
# manifeste declarant un backend fonctionnel la ou il ne l est pas produirait
# un plantage en pleine generation plutot qu un refus clair.
echo "[backend] Test CUDA ..."
SMOKE=0
if "$VPY" -c "
import torch, gsplat
assert torch.cuda.is_available()
x = torch.randn(256, 256, device='cuda'); torch.mm(x, x).sum().item()
from gsplat import rasterization
print('  OK', torch.__version__, '| CUDA', torch.version.cuda,
      '|', torch.cuda.get_device_name(0), '| gsplat', gsplat.__version__)
"; then SMOKE=1; else echo "  [!] Test CUDA en echec."; fi

PACK="$PACK" SMOKE="$SMOKE" /opt/venv/bin/python - <<'PY'
import importlib.util, json, os, pathlib
pack = pathlib.Path(os.environ["PACK"]).resolve()
spec = importlib.util.spec_from_file_location("rt", pack/"core"/"splatting"/"runtime.py")
rt = importlib.util.module_from_spec(spec); spec.loader.exec_module(rt)
manifest = {
    "contract": rt.expected(),
    "cuda_smoke_test": os.environ["SMOKE"] == "1",
    "generator_source_id": rt.source_id(rt.GENERATOR_SOURCE),
    "trainer_id": rt.trainer_id(),
    "installed_by": "docker-entrypoint",
}
rt.MANIFEST.parent.mkdir(parents=True, exist_ok=True)
rt.MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
print("[backend] manifeste ecrit -", manifest["contract"]["platform"],
      "| smoke:", manifest["cuda_smoke_test"])
PY

if [ "$SMOKE" != "1" ]; then
    echo "[backend] cuda_smoke_test=false : les nodes 4DAnyone refuseront de"
    echo "          demarrer. C est volontaire. Verifiez le GPU du pod."
fi

# --- 4. ComfyUI -------------------------------------------------------------
echo "[comfy] Demarrage sur le port $PORT ..."
cd "$COMFY_ROOT"
source /opt/venv/bin/activate
exec python main.py --listen 0.0.0.0 --port "$PORT" --enable-cors-header "*" ${COMFY_EXTRA_ARGS:-}
