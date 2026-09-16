"""Export PLY Sequence - node ComfyUI pour recuperer la sequence .ply
produite par SplatKit "Train Sequence", sous forme d archive telechargeable.

Train Sequence ecrit deja un .ply par frame dans <sortie>/ply/. Ce node fait
le zip depuis ComfyUI et pose l archive dans output/.

Se branche sur la sortie "sequence" de Train Sequence ou de Load Sequence.
"""

import os, shutil, zipfile
from pathlib import Path

try:
    import folder_paths
except ImportError:
    folder_paths = None

CATEGORY = "SplatKit/Splatting"
TYPE_SEQUENCE = "SPLATKIT_SEQUENCE"


def _out():
    return Path(folder_paths.get_output_directory()) if folder_paths else Path("output")


def _human(n):
    v = float(n)
    for u in ("o", "Ko", "Mo", "Go"):
        if v < 1024 or u == "Go":
            return "%.1f %s" % (v, u)
        v /= 1024


class SplatKitExportPlySequence:
    CATEGORY = CATEGORY
    FUNCTION = "export"
    RETURN_TYPES = ("STRING", "INT", "STRING")
    RETURN_NAMES = ("archive_path", "frame_count", "report")
    OUTPUT_NODE = True
    DESCRIPTION = "Archive les .ply d une sequence dans output/, pret a telecharger."

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "sequence": (TYPE_SEQUENCE,),
                "filename_prefix": ("STRING", {"default": "splatkit_ply"}),
                "mode": (["zip_store", "zip", "dossier"], {"default": "zip_store"}),
            },
            "optional": {
                "frame_step": ("INT", {"default": 1, "min": 1, "max": 100}),
                "include_meta": ("BOOLEAN", {"default": True}),
                "overwrite": ("BOOLEAN", {"default": False}),
            },
        }

    @classmethod
    def IS_CHANGED(cls, sequence, filename_prefix, mode, **kw):
        try:
            stamp = tuple((p, os.path.getsize(p)) for p in sequence.get("ply", [])
                          if os.path.isfile(p))
            return (stamp, filename_prefix, mode, tuple(sorted(kw.items())))
        except Exception:
            return float("nan")

    def export(self, sequence, filename_prefix, mode,
               frame_step=1, include_meta=True, overwrite=False):
        plys = [Path(p) for p in sequence.get("ply", []) if os.path.isfile(p)]
        if not plys:
            raise RuntimeError(
                "Aucun .ply dans cette sequence. Train Sequence a peut-etre "
                "tourne avec --no-ply, ou l entrainement n est pas termine."
            )

        plys = sorted(plys)[::max(1, int(frame_step))]
        root = Path(sequence["dir"])
        total = sum(p.stat().st_size for p in plys)

        od = _out()
        od.mkdir(parents=True, exist_ok=True)
        safe = "".join(c for c in filename_prefix if c.isalnum() or c in "-_") or "splatkit_ply"
        suf = "" if mode == "dossier" else ".zip"
        tgt = od / (safe + suf)
        if not overwrite:
            i = 1
            while tgt.exists():
                tgt = od / ("%s_%03d%s" % (safe, i, suf))
                i += 1
        elif tgt.exists():
            shutil.rmtree(tgt) if tgt.is_dir() else tgt.unlink()

        if mode == "dossier":
            tgt.mkdir(parents=True, exist_ok=True)
            for p in plys:
                shutil.copy2(p, tgt / p.name)
            if include_meta and (root / "meta.json").is_file():
                shutil.copy2(root / "meta.json", tgt / "meta.json")
            written = sum(f.stat().st_size for f in tgt.rglob("*") if f.is_file())
        else:
            comp = zipfile.ZIP_STORED if mode == "zip_store" else zipfile.ZIP_DEFLATED
            with zipfile.ZipFile(tgt, "w", compression=comp, allowZip64=True) as zf:
                for p in plys:
                    zf.write(p, arcname="ply/" + p.name)
                if include_meta and (root / "meta.json").is_file():
                    zf.write(root / "meta.json", arcname="meta.json")
            written = tgt.stat().st_size

        rep = "\n".join([
            "Frames        : %d" % len(plys),
            "Source        : %s" % root,
            "Archive       : %s" % tgt,
            "Taille .ply   : %s" % _human(total),
            "Taille ecrite : %s" % _human(written),
            "Mode          : %s" % mode,
        ])
        print("[PlyExport]")
        print(rep)
        return {"ui": {"text": [rep]}, "result": (str(tgt), len(plys), rep)}


NODE_CLASS_MAPPINGS = {"SplatKit_ExportPlySequence": SplatKitExportPlySequence}
NODE_DISPLAY_NAME_MAPPINGS = {"SplatKit_ExportPlySequence": "Export PLY Sequence"}
