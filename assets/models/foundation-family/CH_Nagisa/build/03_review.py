"""Reproducible face/forms comparison. Heavy commands are always sequential.

Use --compose-only to compose existing actual renders without starting Blender.
No numerical/visual acceptance is inferred from composing these images.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import subprocess
import os
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"review/03_face_hair"
BLENDER=os.environ.get("BLENDER_BIN","/Applications/Blender.app/Contents/MacOS/Blender")


def compose():
    original=Image.open(ROOT/"ref/turnaround-v1.png").convert("RGB")
    registrations={"front":(235,0,408,185),"side":(650,0,835,185)}
    for view,crop in registrations.items():
        ref=original.crop(crop)
        actual=Image.open(OUT/f"material_{view}.png").convert("RGBA")
        ref=ref.resize(actual.size,Image.Resampling.LANCZOS)
        background=Image.new("RGBA",actual.size,(248,242,230,255))
        background.alpha_composite(actual)
        rendered=background.convert("RGB")
        overlay=Image.blend(ref,rendered,.5)
        width,height=actual.size
        sheet=Image.new("RGB",(width*3,height+28),(245,245,240))
        draw=ImageDraw.Draw(sheet)
        for x,label,panel in [(0,"REFERENCE",ref),(width,"ACTUAL MATERIAL",rendered),(width*2,"50% REGISTERED OVERLAY",overlay)]:
            draw.text((x+8,8),label,(25,25,25));sheet.paste(panel,(x,28))
        sheet.save(OUT/f"compare_face_{view}.png")
    # Exact256px crown→chin cutout from the actual fixed front render, not a
    # different camera or a claimed256px render where only its canvas is256.
    actual=Image.open(OUT/"material_front.png").convert("RGBA")
    crop=registrations["front"]
    crown,chin=14*3,164*3
    head=actual.crop((0,crown,actual.width,chin))
    head=head.resize((round(head.width*256/head.height),256),Image.Resampling.LANCZOS)
    head.save(OUT/"actual_head_256px.png")
    # Preserve native subject size from physical8m/19m camera renders. These
    # are the coloured gameplay review, not enlarged dark clay thumbnails.
    game=Image.new("RGB",(440,260),(238,235,224));draw=ImageDraw.Draw(game)
    camera_samples=[]
    for x,label in [(40,"close_8m"),(260,"overview_19m")]:
        path=OUT/f"material_game_{label}.png"
        if not path.exists():
            continue
        frame=Image.open(path).convert("RGBA")
        box=frame.getchannel("A").getbbox()
        if not box:
            raise ValueError("Missing coloured whole-body subject")
        subject=frame.crop(box)
        game.paste(subject,(x,220-subject.height),subject)
        draw.text((x,230),f'{label}: {subject.height}px',(35,35,35))
        camera_samples.append({"file":path.name,"alpha_bbox":list(box),"native_subject_height_px":subject.height,"rescaled":False})
    game.save(OUT/"coloured_gameplay_native_strip.png")
    (OUT/"comparison-method.json").write_text(json.dumps({
        "method":"fixed world windows from original source sheet; no bbox alignment or view-specific scaling",
        "source":"ref/turnaround-v1.png","render":"material_front.png / material_side.png",
        "head_cutout":{"height_px":256,"source_render_window_y":[crown,chin],"method":"crop and resample of actual material render"},
        "coloured_gameplay_native_samples":camera_samples,
        "acceptance":"pending visual review; composition does not establish model quality"
    },indent=2)+"\n")


def main():
    parser=argparse.ArgumentParser();parser.add_argument("--compose-only",action="store_true")
    args=parser.parse_args()
    if not args.compose_only:
        subprocess.run([BLENDER,"--background","--factory-startup","--python",str(ROOT/"build/03_face_review.py")],check=True,timeout=120)
        spec=importlib.util.spec_from_file_location("nagisa_fullbody",ROOT/"build/02_review.py")
        review=importlib.util.module_from_spec(spec);spec.loader.exec_module(review)
        review.OUT=OUT/"fullbody";review.main()
    compose()


if __name__=="__main__":
    main()
