"""Measured local form corrections; original raw, UVs and image bytes stay frozen."""
from pathlib import Path
import bpy,json,struct,hashlib
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];SPECS=json.loads((ROOT/'build/specs.json').read_text())
PARAMS={'saki':{'body_x':.97,'arm_inward_m':.0128,'forearm_up_m':0.,'skirt_hem_narrowing':.06},'tomo':{'body_x':1.,'arm_inward_m':0.,'forearm_up_m':0.,'skirt_hem_narrowing':0.},'yui':{'body_x':.97,'arm_inward_m':.015,'forearm_up_m':.011,'skirt_hem_narrowing':0.}}
def sm(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def uvhash(ob):return hashlib.sha256(b''.join(struct.pack('<2f',*uv.uv) for uv in ob.data.uv_layers.active.data)).hexdigest()
for ident,s in SPECS.items():
    path=REPO/f'builds/jrpg-resident-renewal/{ident}';bpy.ops.wm.open_mainfile(filepath=str(path/f'CH_{s["name"]}_RawReview.blend'));ob=next(o for o in bpy.data.collections['LOW'].objects if o.type=='MESH');world=ob.matrix_world.copy();inverse=world.inverted();h=s['height'];p=PARAMS[ident];uvbefore=uvhash(ob);uv_values_before=[tuple(value.uv) for value in ob.data.uv_layers.active.data];changes=[];hand_delta=[]
    for vertex in ob.data.vertices:
        old=world@vertex.co;q=old.copy();side=1 if old.x>=0 else -1
        body=old.copy();body.x*=p['body_x']
        if p['skirt_hem_narrowing']:
            region=sm(.175*h,.215*h,old.z)*(1-sm(.59*h,.64*h,old.z));flare=1-sm(.23*h,.58*h,old.z);body.x*=1-p['skirt_hem_narrowing']*region*flare
        threshold=(.085+.045*(1-sm(.62*h,.80*h,old.z)))*h
        arm_mask=sm(threshold-.015,threshold+.025,abs(old.x))*(1-sm(.80*h,.86*h,old.z))*sm(.39*h,.43*h,old.z)
        arm=old.copy();arm.x-=side*p['arm_inward_m'];arm.z+=p['forearm_up_m']*(1-sm(.62*h,.76*h,old.z))
        q=body.lerp(arm,arm_mask)
        if s['camera'] and old.y<-.065*h and abs(old.x)<.060*h and .53*h<old.z<.70*h:q=old.copy()
        vertex.co=inverse@q;changes.append((q-old).length)
        if abs(old.x)>.175*h and .40*h<old.z<.55*h:hand_delta.append(tuple(q-old))
    uv_values_after=[tuple(value.uv) for value in ob.data.uv_layers.active.data];assert uv_values_after==uv_values_before,'Form correction changed actual UV coordinates';ob.data.update();bpy.ops.wm.save_as_mainfile(filepath=str(path/f'CH_{s["name"]}_Forms.blend'))
    report={'parameters':p,'provenance_only':{'original_raw_sha256':s['raw_sha256'],'uv_sha256_before':uvbefore,'uv_sha256_after':uvhash(ob),'policy':'Identifiers only; no fingerprint comparison or quality gate.'},'raw_input_policy':'The raw GLB is never written by this script.','uv_comparison':'Direct coordinate arrays, not fingerprints.','uv_coordinates_unchanged':uv_values_after==uv_values_before,'max_vertex_displacement_m':max(changes),'hand_local_shape_policy':'Separated hands translate with the arm region; no hand local scaling. Forearm-height blend ends above the hand.','sample_hand_displacements':sorted(set(tuple(round(v,6) for v in d) for d in hand_delta)),'reference_calibration_unchanged':True};(ROOT/ident/'review/forms-adjustment.json').write_text(json.dumps(report,indent=2)+'\n');print('FORMS',ident,json.dumps(report))
