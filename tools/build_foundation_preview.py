#!/usr/bin/env python3
"""Package a committed foundation scene in an isolated worktree and save domain.

The preview is a checkpoint, not acceptance of roadmap stage 1. No tag, Release,
old save, working checkout or existing application is modified by this script.
"""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import json
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TITLE = "命の砂時計・生活基盤プレビュー"


def command(args, log, cwd=ROOT):
    result = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    log.write_text(result.stdout, encoding="utf-8")
    if result.returncode or re.search(r"SCRIPT ERROR:|(^|\n)ERROR:|Parse Error:|Unicode parsing error", result.stdout):
        raise RuntimeError(f"{log.name}: process failed; see the retained log")


def replace(text, key, value):
    pattern = rf"(?m)^{re.escape(key)}=.*$"
    if len(re.findall(pattern, text)) != 1:
        raise RuntimeError(f"Expected exactly one build setting: {key}")
    return re.sub(pattern, f'{key}="{value}"', text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--output", type=Path, default=ROOT / "builds/foundation-preview-20261105")
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    revision = subprocess.check_output(["git", "rev-parse", "--verify", args.ref + "^{commit}"], cwd=ROOT, text=True).strip()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = output / "source"
    if source.exists():
        raise RuntimeError("Source checkout already exists; choose a new output directory")
    command(["git", "worktree", "add", "--detach", str(source), revision], output / "checkout.log")
    project = source / "project.godot"
    config = project.read_text()
    config = replace(config, "config/name", TITLE)
    config = replace(config, "run/main_scene", "res://game/foundation/foundation_world.tscn")
    project.write_text(config)
    presets = source / "export_presets.cfg"
    settings = presets.read_text()
    settings = replace(settings, "application/bundle_identifier", "com.hayatok.hourglassoflife.foundationpreview")
    # FileAccess-loaded JSON contracts and the new nested house/life data must
    # be included too. Source art, evidence raw inputs and test tooling stay out.
    settings = re.sub(r'(?m)^include_filter=.*$', 'include_filter="*.json"', settings)
    settings = re.sub(r'(?m)^exclude_filter=.*$', 'exclude_filter="tools/*,tests/*,docs/*,assets/*,data/evidence/*"', settings)
    presets.write_text(settings)
    patch = subprocess.check_output(["git", "diff", "--", "project.godot", "export_presets.cfg"], cwd=source, text=True)
    (output / "preview-configuration.patch").write_text(patch)
    print("Importing the isolated committed source", flush=True)
    command([args.godot, "--headless", "--editor", "--path", str(source), "--import", "--quit"], output / "import.log")
    archive = output / "hourglass-of-life-foundation-preview-20261105-macOS.zip"
    print("Exporting the Mac preview", flush=True)
    command([args.godot, "--headless", "--path", str(source), "--export-release", "macOS", str(archive)], output / "export.log")
    command(["/usr/bin/ditto", "-x", "-k", str(archive), str(output)], output / "extract.log")
    applications = list(output.glob("*.app"))
    if len(applications) != 1:
        raise RuntimeError("The exported archive did not contain exactly one application")
    app = applications[0]
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    print("Booting the actual exported application headlessly", flush=True)
    command([str(executable), "--headless", "--quit-after", "60"], output / "packaged-boot.log", cwd=output)
    record = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "source_commit_identification_only": revision,
        "source_configuration": "preview-configuration.patch",
        "application": str(app), "archive": str(archive),
        "bundle_identifier": info["CFBundleIdentifier"],
        "save_directory_name": TITLE,
        "scope": "Playable development checkpoint of the new house/life scene; roadmap stage 1 remains in progress.",
        "packaged_headless_boot": "passed", "native_ui_review": "pending",
        "remaining": ["new family models", "accepted natural locomotion", "seat and bed interaction", "whole-body tool and carrying motion", "causal family backgrounds"],
    }
    (output / "build.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    (output / "README.txt").write_text(f"""{TITLE}

複数室の家、台所・衛生設備・家族の寝床、3人の生活工程を確認する開発プレビューです。
着座・寝具・道具の全身動作と新しい人物造形は制作中です。
ロードマップ段階1の完成版ではありません。

家を見渡す：右上のボタン。人物を見る：下の人物ボタン。
カメラを回す：空いている画面をドラッグ。拡縮：ピンチまたは右下の＋/−。
一時停止・再開、保存・保存から再開は左上のボタン。

従来版のセーブとは別の「{TITLE}」保存フォルダを使用します。
既存アプリを置き換える必要はありません。
""", encoding="utf-8")
    print(json.dumps({"application": str(app), "archive": str(archive), "native_ui_review": "pending"}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
