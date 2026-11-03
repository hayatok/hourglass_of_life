"""Measure actual posed surfaces, seam motion, and limb-family assignments.

Hashes are identification metadata only and are not acceptance checks here.
"""
from pathlib import Path
from collections import defaultdict
import bpy,json,sys,math
from mathutils import Matrix
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2]
SPECS=json.loads((ROOT/'build/specs.json').read_text())
ACTIVE=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(SPECS)
for ident in ACTIVE:
 s=SPECS[ident];build=REPO/f'builds/jrpg-resident-renewal/{ident}'
 bpy.ops.wm.open_mainfile(filepath=str(build/f'CH_{s["name"]}_Rig.blend'))
 body=bpy.data.objects[f'CH_{s["name"]}_Body_LOD0'];arm=bpy.data.objects[f'CH_{s["name"]}_Rig']
 names={g.index:g.name for g in body.vertex_groups};weights=[{names[g.group]:g.weight for g in v.groups} for v in body.data.vertices]
 groups=defaultdict(list)
 for v in body.data.vertices:groups[tuple(round(c,6) for c in v.co)].append(v.index)
 seam_groups=[ids for ids in groups.values() if len(ids)>1]
 arm_parts=('upper_arm.','forearm.','hand.','finger')
 mixed=[]
 for v,w in zip(body.data.vertices,weights):
  arm_value=sum(value for name,value in w.items() if any(part in name for part in arm_parts))
  lower_value=sum(value for name,value in w.items() if any(part in name for part in ('thigh.','shin.','apron_')))
  if arm_value>.01 and lower_value>.01:mixed.append({'index':v.index,'position':list(v.co),'weights':w})
 report={'resident':ident,'purpose':'Actual vertex deformation and skin-family review; provenance hashes are not quality tests',
         'arm_and_lower_body_mixed_vertices':mixed,'pose_samples':[],'maximum_seam_separation_m':0.}
 rest=[v.co.copy() for v in body.data.vertices]
 edges=[(a,b,(rest[a]-rest[b]).length) for edge in body.data.edges for a,b in [edge.vertices]]
 for name in ['idle','walk','talk','work','wave','sit_talk','eat','rest','sleep']:
  action=bpy.data.actions[name]
  for t in [0.,.25,.5,.75,1.]:
   arm.animation_data.action=None
   for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
   arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0]
   frame=action.frame_range[0]+t*(action.frame_range[1]-action.frame_range[0]);bpy.context.scene.frame_set(math.floor(frame),subframe=frame%1);bpy.context.view_layer.update()
   ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh();points=[v.co.copy() for v in mesh.vertices];ev.to_mesh_clear()
   seam=max(((points[ids[0]]-points[i]).length for ids in seam_groups for i in ids[1:]),default=0)
   report['maximum_seam_separation_m']=max(report['maximum_seam_separation_m'],seam)
   stretches=[]
   for a,b,length in edges:
    if length<=.001:continue
    posed=(points[a]-points[b]).length;ratio=posed/length
    if ratio>2.5 and posed>.03:stretches.append({'ratio':ratio,'rest_length_m':length,'posed_length_m':posed,'indices':[a,b],'rest_positions':[list(rest[a]),list(rest[b])],'weights':[weights[a],weights[b]]})
   stretches.sort(key=lambda row:-row['ratio'])
   report['pose_samples'].append({'clip':name,'fraction':t,'frame':frame,'seam_max_m':seam,'edges_above_2_5x_and_30mm':len(stretches),'largest_stretches':stretches[:6]})
 (ROOT/ident/'review/deformation-audit.json').write_text(json.dumps(report,indent=2)+'\n')
 worst=max(report['pose_samples'],key=lambda p:p['largest_stretches'][0]['ratio'] if p['largest_stretches'] else 0)
 print('DEFORMATION',ident,'mixed_arm_lower',len(mixed),'seam_max',report['maximum_seam_separation_m'],'worst_clip',worst['clip'],'worst',worst['largest_stretches'][:1])
