"""Verify evaluated geometry and clip seams, not merely the presence of animation names."""
import bpy,json,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'CH_Nagisa_delivery.blend'))
arm=bpy.data.objects['CH_Nagisa_Rig'];meshes=[bpy.data.objects['CH_Nagisa_'+p+'_LOD0'] for p in ['Body','Face']]
report={'clips':{},'morphs':{},'failures':[]}
def evaluated(ob):
    e=ob.evaluated_get(bpy.context.evaluated_depsgraph_get());me=e.to_mesh();out=np.empty(len(me.vertices)*3,np.float32)
    me.vertices.foreach_get('co',out);e.to_mesh_clear();return out.reshape(-1,3)
for ob in bpy.data.collections['LOW'].objects:
    if not ob.data.shape_keys:continue
    basis=ob.data.shape_keys.key_blocks['Basis']
    base=np.array([tuple(p.co) for p in basis.data])
    for key in ob.data.shape_keys.key_blocks:
        if key==basis:continue
        delta=float(np.linalg.norm(np.array([tuple(p.co) for p in key.data])-base,axis=1).max())
        report['morphs'][ob.name+'/'+key.name]={'default':key.value,'max_delta_m':round(delta,5)}
        if key.value!=0 or delta>.035:report['failures'].append('invalid neutral morph '+ob.name+'/'+key.name)
for action in bpy.data.actions:
    if action.name.startswith('_'):continue
    arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0]
    start,end=map(int,action.frame_range);snapshots=[];minimum=100
    for frame in sorted(set(np.linspace(start,end,25).round().astype(int))):
        bpy.context.scene.frame_set(int(frame));bpy.context.view_layer.update()
        vertices=np.concatenate([evaluated(o) for o in meshes])
        minimum=min(minimum,float(vertices[:,2].min()))
        if frame in [start,end]:snapshots.append(vertices)
    seam=float(np.linalg.norm(snapshots[0]-snapshots[-1],axis=1).max())
    report['clips'][action.name]={'length_s':(end-start)/30,'loop':bool(action['loop']),
        'seam_max_m':round(seam,7),'floor_min_m':round(minimum,5)}
    if action['loop'] and seam>.0001:report['failures'].append('loop seam '+action.name)
    if action.name!='sleep' and minimum<-.006:report['failures'].append('floor penetration '+action.name)
dest=ROOT/'review/08_animation/geometry-checks.json';dest.parent.mkdir(parents=True,exist_ok=True)
dest.write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
if report['failures']:raise RuntimeError('Animation geometry checks failed')
