"""Non-destructive close-up and gameplay-camera review of the imported raw mesh."""
from pathlib import Path
import bpy,math,json,importlib.util
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2]
bpy.ops.wm.open_mainfile(filepath=str(REPO/'builds/haru-cute-pilot/CH_Haru_JRPG_Pilot_Review.blend'))
for ob in bpy.context.scene.objects:
    if ob.type in ['MESH','CURVE','FONT']:ob.hide_render=ob not in set(bpy.data.collections['LOW'].all_objects)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.view_settings.view_transform='Standard'
world=scene.world or bpy.data.worlds.new('ReviewWorld');scene.world=world
world.node_tree.nodes.clear();bg=world.node_tree.nodes.new('ShaderNodeBackground');bg.inputs['Color'].default_value=(.6,.6,.6,1);bg.inputs['Strength'].default_value=.3;out=world.node_tree.nodes.new('ShaderNodeOutputWorld');world.node_tree.links.new(bg.outputs[0],out.inputs[0])
for ob in list(scene.objects):
    if ob.type=='LIGHT':bpy.data.objects.remove(ob,do_unlink=True)
for name,location,energy,size in [('Key',(-2,-3,4),220,4),('Fill',(3,-2,2.5),100,3),('Rim',(0,3,3),180,3)]:
    light=bpy.data.lights.new('Review'+name,'AREA');light.energy=energy;light.shape='DISK';light.size=size;ob=bpy.data.objects.new(light.name,light);scene.collection.objects.link(ob);ob.location=location;ob.rotation_euler=(Vector((0,0,1))-ob.location).to_track_quat('-Z','Y').to_euler()
cam=bpy.data.objects.new('DetailCamera',bpy.data.cameras.new('DetailCamera'));scene.collection.objects.link(cam);scene.camera=cam;cam.data.type='ORTHO'
output=ROOT/'review/details';output.mkdir(parents=True,exist_ok=True)
views=[('face_front',(0,-3,1.59),(0,0,1.59),.50),('face_threequarter',(2,-3,1.64),(0,0,1.58),.52),('left_hand_front',(-.40,-2,.86),(-.40,0,.86),.40),('right_hand_front',(.40,-2,.86),(.40,0,.86),.40),('hands_back',(0,3,.86),(0,0,.86),1.1),('gameplay_threequarter',(2.5,-4.33,5.5),(0,0,.88),2.1)]
report={'color_management':'Standard, neutral area lights, source material unchanged, denoised Cycles 32 samples','views':[]}
for name,position,target,extent in views:
    cam.location=position;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=extent
    scene.render.resolution_x=scene.render.resolution_y=512 if name!='gameplay_threequarter' else 160
    scene.render.resolution_percentage=100;scene.render.filepath=str(output/(name+'.png'));bpy.ops.render.render(write_still=True)
    report['views'].append({'name':name,'camera':position,'target':target,'ortho_scale':extent})
(output/'render-info.json').write_text(json.dumps(report,indent=2)+'\n')
