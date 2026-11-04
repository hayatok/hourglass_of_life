"""Per-character rendered body/garment acceptance before engine integration."""
from pathlib import Path
import bpy,math,json,sys
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];SPECS=json.loads((ROOT/'build/specs.json').read_text());ident=sys.argv[sys.argv.index('--')+1];spec=SPECS[ident]
sys.path.insert(0,str(ROOT/'build'));import garment_helpers
bpy.ops.wm.open_mainfile(filepath=str(REPO/f'builds/jrpg-resident-renewal/{ident}/CH_{spec["name"]}_Rig.blend'))
arm=bpy.data.objects[f'CH_{spec["name"]}_Rig'];body=bpy.data.objects[f'CH_{spec["name"]}_Body_LOD0'];h=spec['height'];quick='quick' in sys.argv;out=ROOT/ident/('review/pose-debug' if quick else 'review/poses');out.mkdir(exist_ok=True)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True;scene.view_settings.view_transform='Standard';scene.render.resolution_x=480;scene.render.resolution_y=600;scene.render.resolution_percentage=100;scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.render.threads_mode='FIXED';scene.render.threads=2
for ob in scene.objects:
 if ob.type in ['MESH','CURVE','FONT']:ob.hide_render=ob!=body
for ob in list(scene.objects):
 if ob.type=='LIGHT':bpy.data.objects.remove(ob,do_unlink=True)
world=scene.world or bpy.data.worlds.new('BodyReviewWorld');scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Color'].default_value=(.65,.65,.65,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=.35
for name,pos,energy,size in [('Key',(-2,-3,4),250,4),('Fill',(3,-2,2.5),120,3),('Rim',(0,3,3),200,3)]:
 light=bpy.data.lights.new('Review'+name,'AREA');light.energy=energy;light.size=size;ob=bpy.data.objects.new(light.name,light);scene.collection.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector((0,0,1))-ob.location).to_track_quat('-Z','Y').to_euler()
cam=bpy.data.objects.new('BodyReviewCamera',bpy.data.cameras.new('BodyReviewCamera'));scene.collection.objects.link(cam);scene.camera=cam;cam.data.type='ORTHO'
camera_ids=[v.index for v in body.data.vertices if spec['camera'] and v.co.y<-.125 and abs(v.co.x)<.115 and .90<v.co.z<1.12];camera_pairs=[(camera_ids[i],camera_ids[-i-1]) for i in range(min(60,len(camera_ids)//2))];camera_rest=[(body.data.vertices[a].co-body.data.vertices[b].co).length for a,b in camera_pairs]
poses=[('full_stride','walk',round(bpy.data.actions['walk'].frame_range[1]/4)),('talk_forward','talk',18),('work_reach','work',15),('seated','sit_talk',18),('sleep','sleep',30),('arms_overhead','_pose_overhead',0),('torso_twist','_pose_twist',0),('deep_bend','idle',0),('head_turn','idle',18)]
if quick:poses=[p for p in poses if p[0] in ['full_stride','work_reach']]
report={'resident':ident,'renderer':'Cycles12, denoised, Standard, original material/atlas','purpose':'Body and clothing deformation evidence; not facial or gameplay acceptance','poses':[]}
for label,clip,frame in poses:
 arm.animation_data.action=None
 for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
 action=bpy.data.actions[clip];arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0];scene.frame_set(frame)
 if label in ['deep_bend','arms_overhead']:
  arm.animation_data.action=None
  for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
  for side,sign in [('L',1),('R',-1)]:
   if label=='deep_bend':
    arm.pose.bones['DEF-thigh.'+side].rotation_euler.x=1.85;arm.pose.bones['DEF-shin.'+side].rotation_euler.x=-2.10;arm.pose.bones['DEF-upper_arm.'+side].rotation_euler.x=1.10;arm.pose.bones['DEF-forearm.'+side].rotation_euler.x=2.15
   else:arm.pose.bones['DEF-upper_arm.'+side].rotation_euler.z=sign*2.55;arm.pose.bones['DEF-forearm.'+side].rotation_euler.x=.10
 if label=='head_turn':
  arm.animation_data.action=None;arm.pose.bones['DEF-head'].rotation_euler.y=.60
 bpy.context.view_layer.update()
 if spec['skirt'] and label in ['deep_bend','arms_overhead','head_turn']:
  bind=json.loads((ROOT/ident/'production-inputs/bind-report.json').read_text());garment_helpers.update(arm,bind['landmarks_inferred_from_forms']['skirt_min']+.015,label);bpy.context.view_layer.update()
 ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh();points=[v.co.copy() for v in mesh.vertices];ev.to_mesh_clear();lo=Vector([min(v[i] for v in points) for i in range(3)]);hi=Vector([max(v[i] for v in points) for i in range(3)]);center=(lo+hi)*.5
 cam.data.ortho_scale=2.5 if label=='sleep' else (2.3 if label=='arms_overhead' else 1.95)
 for angle,name in [(0,'front'),(65,'threequarter')]:
  az=math.radians(angle);cam.location=center+Vector((4*math.sin(az),-4*math.cos(az),.7 if label=='sleep' else .1));cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(out/f'{label}-{name}.png');bpy.ops.render.render(write_still=True)
 camera_error=max([abs((points[a]-points[b]).length-distance) for (a,b),distance in zip(camera_pairs,camera_rest)],default=0)
 if camera_ids and label in ['work_reach','seated']:
  target=sum([points[i] for i in camera_ids],Vector())/len(camera_ids);cam.location=target+Vector((.3,-3,.15));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.55;scene.render.filepath=str(out/f'camera-{label}.png');bpy.ops.render.render(write_still=True)
 if label=='head_turn' and ident=='yui':
  target=Vector((0,.02,1.38));cam.location=target+Vector((2,3,.3));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.65;scene.render.filepath=str(out/'ponytail-head-turn-back.png');bpy.ops.render.render(write_still=True)
 report['poses'].append({'label':label,'clip':clip if label not in ['arms_overhead','deep_bend','head_turn'] else 'manual limit/review pose','frame':frame,'bounds':{'min':list(lo),'max':list(hi)},'camera_rigid_pair_max_error_m':camera_error,'camera_sampled_pairs':len(camera_pairs),'head_yaw_local_radians':arm.pose.bones['DEF-head'].rotation_euler.y})
(out/'poses.json').write_text(json.dumps(report,indent=2)+'\n');print('POSE_REVIEW',ident,'finished')
