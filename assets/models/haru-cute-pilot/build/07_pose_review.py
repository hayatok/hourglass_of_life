"""Rendered deformation evidence at the poses used by town interactions."""
from pathlib import Path
import bpy,math,json
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2]
bpy.ops.wm.open_mainfile(filepath=str(REPO/'builds/haru-cute-pilot/CH_Haru_Rig.blend'))
arm=bpy.data.objects['CH_Haru_Rig'];body=bpy.data.objects['CH_Haru_Body_LOD0']
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=12;scene.cycles.use_denoising=True;scene.cycles.device='CPU'
scene.render.resolution_x=480;scene.render.resolution_y=600;scene.render.resolution_percentage=100
scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.view_settings.view_transform='Standard'
for ob in scene.objects:
    if ob.type in ['MESH','CURVE','FONT']:ob.hide_render=ob!=body
for ob in list(scene.objects):
    if ob.type=='LIGHT':bpy.data.objects.remove(ob,do_unlink=True)
world=scene.world or bpy.data.worlds.new('PoseWorld');scene.world=world;world.use_nodes=True;bg=world.node_tree.nodes.get('Background');bg.inputs['Color'].default_value=(.65,.65,.65,1);bg.inputs['Strength'].default_value=.35
for name,pos,energy,size in [('Key',(-2,-3,4),250,4),('Fill',(3,-2,2.5),120,3),('Rim',(0,3,3),200,3)]:
    light=bpy.data.lights.new('Pose'+name,'AREA');light.energy=energy;light.size=size;ob=bpy.data.objects.new(light.name,light);scene.collection.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector((0,0,1))-ob.location).to_track_quat('-Z','Y').to_euler()
cam=bpy.data.objects.new('PoseCamera',bpy.data.cameras.new('PoseCamera'));scene.collection.objects.link(cam);scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=1.95
output=ROOT/'review/poses';output.mkdir(exist_ok=True)
poses=[('full_stride','walk',6),('talk_forward','talk',18),('work_reach','work',15),('seated','sit_talk',18),('sleep','sleep',30),('arms_overhead','_pose_overhead',0),('torso_twist','_pose_twist',0),('deep_bend','idle',0)]
report={'renderer':'Cycles 12 samples, Standard, neutral light, source atlas unchanged','poses':[]}
for label,clip,frame in poses:
    action=bpy.data.actions[clip];arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0];scene.frame_set(frame)
    if label=='deep_bend':
        arm.animation_data.action=None
        for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
        for side in ['L','R']:
            arm.pose.bones['DEF-thigh.'+side].rotation_euler.x=1.85
            arm.pose.bones['DEF-shin.'+side].rotation_euler.x=-2.1
            arm.pose.bones['DEF-upper_arm.'+side].rotation_euler.x=1.1
            arm.pose.bones['DEF-forearm.'+side].rotation_euler.x=2.15
        arm.pose.bones['DEF-chest'].rotation_euler.x=.2
    if label=='arms_overhead':
        arm.animation_data.action=None
        for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
        for side,s in [('L',1),('R',-1)]:
            arm.pose.bones['DEF-upper_arm.'+side].rotation_euler.z=s*2.55
            arm.pose.bones['DEF-forearm.'+side].rotation_euler.x=.10
    bpy.context.view_layer.update()
    ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh();points=[v.co.copy() for v in mesh.vertices];ev.to_mesh_clear()
    lo=Vector([min(p[i] for p in points) for i in range(3)]);hi=Vector([max(p[i] for p in points) for i in range(3)]);center=(lo+hi)*.5
    cam.data.ortho_scale=2.5 if label=='sleep' else (2.3 if label=='arms_overhead' else 1.95)
    for angle,name in [(0,'front'),(65,'threequarter')]:
        az=math.radians(angle);cam.location=center+Vector((4*math.sin(az),-4*math.cos(az),.7 if label=='sleep' else .1));cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(output/f'{label}-{name}.png');bpy.ops.render.render(write_still=True)
    report['poses'].append({'label':label,'clip':clip if label not in ['arms_overhead','deep_bend'] else 'manual extreme pose, not a game clip','frame':frame,'bounds':{'min':list(lo),'max':list(hi)},'hand_heights_m':{s:arm.pose.bones['DEF-hand.'+s].matrix.translation.z for s in ['L','R']},'head_bone_height_m':arm.pose.bones['DEF-head'].matrix.translation.z,'upper_arm_local_z_deg':{s:math.degrees(arm.pose.bones['DEF-upper_arm.'+s].rotation_euler.z) for s in ['L','R']},'images':[f'{label}-front.png',f'{label}-threequarter.png']})
arm.animation_data.action=None
for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
target=Vector((0,0,.855));cam.location=target+Vector((2.5,-4.330127,5));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.1
scene.render.resolution_x=scene.render.resolution_y=160;scene.render.filepath=str(output/'town-angle-rest.png');bpy.ops.render.render(write_still=True)
report['town_angle_thumbnail']={'file':'town-angle-rest.png','azimuth_degrees':30,'elevation_degrees':45,'image_size':160,'kind':'Blender approximation of town-camera angle; not actual runtime evidence'}
(output/'poses.json').write_text(json.dumps(report,indent=2)+'\n')
