#!/usr/bin/env python3
"""Import byte-identical assets in an isolated Godot project and render a static comparison.

Usage: python3 assets/models/haru-cute-pilot/build/check_godot.py [--headless]
The production assets/models/.gdignore, actor scenes, source GLB and engine settings stay intact.
The temporary project is retained and its path is recorded for reproducibility.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--headless", action="store_true", help="Check imports without PNG rendering")
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[4]
    pilot = repo / "assets/models/haru-cute-pilot"
    out = pilot / "review/godot"
    out.mkdir(parents=True, exist_ok=True)
    project = Path(tempfile.mkdtemp(prefix="hourglass-haru-godot-"))
    files = [
        "assets/models/haru-cute-pilot/raw/CH_Haru_JRPG_Pilot_Raw.glb",
        "assets/models/haru-cute-pilot/build/check_godot.gd",
        "assets/artwork/cute-cast-pilot/haru-concept-v2-jrpg.png",
        "assets/models/haru-cute-pilot/build/fixtures/haru-placeholder.tscn",
        "assets/models/haru-cute-pilot/build/fixtures/haru-placeholder-appearance.json",
        "game/scripts/jrpg_resident_model.gd",
        "game/assets/models/aoi/CH_Aoi.glb",
        "game/assets/models/resident_toon.gdshader",
        "game/assets/models/haru/haru_texture_eyes.gdshader",
    ]
    manifest = []
    for name in files:
        source = repo / name
        destination = project / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        manifest.append({"file": name, "sha256": sha256(source), "staged_sha256": sha256(destination)})
    (project / "project.godot").write_text('''config_version=5
[application]
config/name="Haru static asset import check"
config/features=PackedStringArray("4.7", "GL Compatibility")
[display]
window/size/viewport_width=1600
window/size/viewport_height=1000
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
anti_aliasing/quality/msaa_3d=2
''')
    (out / "source-fixture.json").write_text(json.dumps({
        "project": str(project), "source_repository": str(repo), "files": manifest,
        "reason_for_isolation": "Production assets/models/.gdignore excludes raw production files from engine import.",
        "comparison_baseline_commit": "afb4c32",
        "fixture": "No Sim autoload or resident actor. Previous Haru snapshot uses its rest mesh, toon shader, age 25 and baseline palette. Raw candidate keeps imported PBR materials. Both use scene-only normalization to 1.71m.",
    }, ensure_ascii=False, indent=2) + "\n")

    def run(command: list[str], name: str) -> None:
        result = subprocess.run(command, cwd=project, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (out / name).write_text(result.stdout)
        print(result.stdout)
        if result.returncode:
            raise SystemExit(result.returncode)
        if re.search(r"(?m)^(?:SCRIPT ERROR|ERROR):", result.stdout):
            raise RuntimeError(f"Godot reported an engine/script error; see {out / name}")

    run([args.godot, "--headless", "--editor", "--import", "--path", str(project)], "editor-import.log")
    metadata = project / (files[0] + ".import")
    if not metadata.exists():
        raise RuntimeError("Editor did not create the raw GLB import remap")
    shutil.copyfile(metadata, out / "raw-glb-import-metadata.txt")
    command = [args.godot, "--path", str(project), "--script", "res://assets/models/haru-cute-pilot/build/check_godot.gd"]
    if args.headless:
        command.insert(1, "--headless")
    run(command + ["--", f"--output={out}", f"--original-source={repo / files[0]}"], "headless-check.log" if args.headless else "gpu-check.log")
    result = json.loads((out / "import-check.json").read_text())
    if not result["passed"]:
        raise RuntimeError(result["failures"])
    for entry in manifest:
        entry["sha256_after"] = sha256(repo / entry["file"])
    fixture = json.loads((out / "source-fixture.json").read_text())
    fixture["files"] = manifest
    fixture["fingerprint_policy"] = "Provenance only; not assertions or pass/fail gates."
    (out / "source-fixture.json").write_text(json.dumps(fixture, ensure_ascii=False, indent=2) + "\n")
    if not args.headless and len(result["renders"]) != 6:
        raise RuntimeError("Expected four comparison views and two static shader comparisons")
    print(f"Verified static asset preview: {out}")


if __name__ == "__main__":
    main()
