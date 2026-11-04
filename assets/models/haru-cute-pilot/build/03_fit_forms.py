"""Fit the derived model's silhouette without changing the raw file, UVs or reference.

The arm correction is a rigid shoulder rotation outside the blended shoulder zone;
it preserves the shape of the hands instead of scaling them to fit an image.
"""
from pathlib import Path
import bpy, math, json, hashlib, struct
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[1]; REPO=ROOT.parents[2]
SOURCE=REPO/'builds/haru-cute-pilot/CH_Haru_JRPG_Pilot_Review.blend'
DEST=REPO/'builds/haru-cute-pilot/CH_Haru_JRPG_Pilot_Derived.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
ob=next(o for o in bpy.data.collections['LOW'].objects if o.type=='MESH')
world=ob.matrix_world.copy(); inverse=world.inverted()
uv_before=hashlib.sha256(b''.join(struct.pack('<2f',*uv.uv) for uv in ob.data.uv_layers.active.data)).hexdigest()
def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
max_change=0
for v in ob.data.vertices:
    p=world@v.co; q=p.copy(); side=1 if p.x>=0 else -1
    # Torso/leg/head correction is modest; separated arms rotate at their shoulder.
    threshold=.178+.025*(1-smooth(1.05,1.32,p.z))
    arm=smooth(threshold-.015,threshold+.022,abs(p.x))*(1-smooth(1.35,1.44,p.z))*smooth(.69,.78,p.z)
    body=p.copy();body.x*=.96
    pivot=Vector((side*.165,0,1.35))
    rotated=pivot+Matrix.Rotation(side*.037,3,'Y')@(p-pivot)
    rotated.x-=side*.0066
    q=body.lerp(rotated,arm)
    v.co=inverse@q;max_change=max(max_change,(q-p).length)
uv_after=hashlib.sha256(b''.join(struct.pack('<2f',*uv.uv) for uv in ob.data.uv_layers.active.data)).hexdigest()
assert uv_before==uv_after
ob.data.update()
ob['derivation']='Torso/legs/head X .96; arms rigid shoulder rotation 0.037rad toward neutral with blended shoulder; no hand local scaling'
bpy.ops.wm.save_as_mainfile(filepath=str(DEST))
report={'source':str(SOURCE.relative_to(REPO)),'derived':str(DEST.relative_to(REPO)),'raw_source_unchanged':True,'uv_sha256_before':uv_before,'uv_sha256_after':uv_after,'vertex_count':len(ob.data.vertices),'triangles':len(ob.data.polygons),'maximum_vertex_displacement_m':max_change,'body_x_factor':.96,'arm_rotation_radians':.037,'hand_local_scaling':False,'review_height_m':1.77}
(ROOT/'review/derived-forms.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
