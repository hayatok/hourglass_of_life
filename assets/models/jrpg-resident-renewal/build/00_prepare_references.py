"""Freeze front mattes/calibration from the selected images, independently of meshes."""
from pathlib import Path
import json,hashlib,shutil
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];SPECS=json.loads((ROOT/'build/specs.json').read_text())
for ident,spec in SPECS.items():
    asset=ROOT/ident;ref=asset/'ref';ref.mkdir(exist_ok=True);(asset/'review').mkdir(exist_ok=True)
    source=REPO/f'assets/artwork/jrpg-resident-renewal/{ident}-concept-v1.png';source_sha256=hashlib.sha256(source.read_bytes()).hexdigest();shutil.copyfile(source,ref/'front.png')
    im=Image.open(source).convert('RGBA');w,h=im.size;pix=im.load();mask=Image.new('L',im.size);mp=mask.load()
    for y in range(h):
        edge=[pix[x,y][:3] for x in list(range(0,20))+list(range(w-20,w))];background=tuple(sorted(c[i] for c in edge)[len(edge)//2] for i in range(3))
        for x in range(w):
            if max(abs(pix[x,y][i]-background[i]) for i in range(3))>30:mp[x,y]=255
    # Fill enclosed silhouette holes; do not change mask to fit a model.
    from collections import deque
    outside=bytearray(w*h);queue=deque()
    for x in range(w):
        for y in [0,h-1]:
            if not mp[x,y] and not outside[y*w+x]:outside[y*w+x]=1;queue.append((x,y))
    for y in range(h):
        for x in [0,w-1]:
            if not mp[x,y] and not outside[y*w+x]:outside[y*w+x]=1;queue.append((x,y))
    while queue:
        x,y=queue.popleft()
        for nx,ny in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
            if 0<=nx<w and 0<=ny<h and not mp[nx,ny] and not outside[ny*w+nx]:outside[ny*w+nx]=1;queue.append((nx,ny))
    for y in range(h):
        for x in range(w):
            if not outside[y*w+x]:mp[x,y]=255
    bbox=mask.getbbox();top=bbox[1];ground=bbox[3]-1;subject_height=ground-top+1
    samples=[]
    # Trunk samples avoid off-axis ponytails/fringe being mistaken for face centre.
    for fraction in [.195,.35,.47]:
        row=round(top+subject_height*fraction);spans=[];start=None
        for x in range(w+1):
            on=x<w and mp[x,row]>0
            if on and start is None:start=x
            elif not on and start is not None:spans.append((start,x-1));start=None
        wide=[span for span in spans if span[1]-span[0]+1>.03*subject_height]
        centered=[span for span in wide if span[0]<=w/2<=span[1]]
        central=min(centered or wide or spans,key=lambda span:abs((sum(span)/2)-w/2));samples.append({'fraction':fraction,'row':row,'interval':central,'center':sum(central)/2})
    axis=sorted(s['center'] for s in samples)[1];image=im.copy();image.putalpha(mask);image.save(ref/'front-matte.png')
    widths=[]
    for fraction in [.05,.15,.25,.35,.45,.55,.65,.75,.85,.95]:
        row=round(top+fraction*subject_height);xs=[x for x in range(w) if mp[x,row]];widths.append((max(xs)-min(xs)+1)/subject_height if xs else 0)
    cal={'reference_sha256':source_sha256,'provenance_only':{'declared_reference_sha256':spec['reference_sha256'],'observed_reference_sha256':source_sha256,'policy':'Identifiers only; not compared, counted or used as an acceptance gate.'},'image_size':[w,h],'bbox':bbox,'axis_column':axis,'axis_samples':samples,'top_row':top,'ground_row':ground,'subject_height_pixels':subject_height,'subject_fraction':subject_height/h,'ground_fraction':(h-ground-1)/h,'target_height_m_inferred':spec['height'],'meters_per_pixel':spec['height']/subject_height,'ten_band_width_over_height':widths,'matte_method':'Per-row edge background, max RGB distance >30, enclosed holes filled; fixed before mesh import. No model-based threshold adjustment.','scale_basis':'Inferred from former variant presentation, rounded to canonical metres with body_scale1.0.'};(ref/'calibration.json').write_text(json.dumps(cal,indent=2)+'\n');print(ident,json.dumps(cal))
    brief=f'''ASSET      CH_{spec['name']}_JRPG_Renewal
CATEGORY   character, adult biped; raw source review followed by local humanoid rig
VIEWS      Single front A-pose concept, estimated orthographic AZ0/EL0; bbox {bbox}, axis {axis}, ground row {ground}. Side/back are unavailable.
SCALE      Canonical {spec['height']:.2f}m inferred from previous variant presentation; metres, Blender Z up/-Y front, feet on ground. Original raw remains unchanged.
PROPORTIONS Ten silhouette width/height samples: {widths}. Approximate six-head adult proportions; side depth and joint centres are inferred.
PARTS      {spec['identity']} The generated mesh/material split is inspected before binding; facial controls are not assumed from painted eyes.
SILHOUETTE Preserve the selected resident identity, age and costume; open A-pose hands and separated feet. Haru's selected anime/cel JRPG style is the family reference.
MATERIALS  Original generated atlas retained with ordinary UV sampling; no old palette-cell recolors. Material/eye calibration remains per character.
ARTICULATION Original 35 named bones retained, source CH_{spec['rig_source']}; idle/walk/talk/work/sit_talk/sleep/wave/eat/rest. {'One DEF-skirt_middle helper added (36 total), dedicated skirt weights and deep sit/full-stride reviews.' if spec['skirt'] else '35 total, target-fitted limb weights and deep bend reviews.'} {'Camera rigid to chest; strap attachment review.' if spec['camera'] else ''}
INFERRED   Real height, back/depth, hidden anatomy, garment interiors, joint centres, side/back hair and shoes. These are not reference-confirmed.
TARGET     Godot 4.7.2 GLB; source under30k triangles, original 2K images. Required DEF35 plus skirt helper where needed, 4 influences max; welded-before-decimate compatible LODs and actor-owned atlas. Gameplay review128px plus actual runtime contacts.
''';(asset/'asset-brief.md').write_text(brief)
