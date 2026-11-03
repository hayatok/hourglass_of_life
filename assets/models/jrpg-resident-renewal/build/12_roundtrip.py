"""Clean Blender import: actual skin motion, clip seams and canonical rest scale."""
from pathlib import Path
import bpy,json,math,sys
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];ident=sys.argv[sys.argv.index('--')+1];s=json.loads((ROOT/'build/specs.json').read_text())[ident];OUT=ROOT/ident/'exports';manifest=json.loads((OUT/'asset-manifest.json').read_text());expected=manifest['runtime_contract'];records=[];errors=[]
for level in [0,1,2]:
 path=OUT/f'CH_{s["name"]}{"_LOD"+str(level) if level else ""}.glb';bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(path),merge_vertices=False)
 arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');body=next(o for o in bpy.context.scene.objects if o.type=='MESH')
 connected=body.parent==arm and any(m.type=='ARMATURE' and m.object==arm for m in body.modifiers)
 if not connected:errors.append(f'LOD{level}: skin disconnected')
 if set(b.name for b in arm.data.bones)!=set(expected['skin_bind_names']):errors.append(f'LOD{level}: bone names differ')
 actions={a.name:a for a in bpy.data.actions};arm.animation_data_clear()
 for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
 bpy.context.view_layer.update();points=[body.matrix_world@v.co for v in body.data.vertices];height=max(p.z for p in points)-min(p.z for p in points)
 if abs(height-s['height'])>(1e-5 if level==0 else .01):errors.append(f'LOD{level}: rest height {height}')
 motion={};arm.animation_data_create()
 for name,action in actions.items():
  arm.animation_data.action=None
  for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
  arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0];samples=[]
  for phase in [0,.25,.5,.75,1]:
   frame=action.frame_range[0]+(action.frame_range[1]-action.frame_range[0])*phase;bpy.context.scene.frame_set(math.floor(frame),subframe=frame%1);bpy.context.view_layer.update();ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh();samples.append([body.matrix_world@v.co for v in mesh.vertices]);ev.to_mesh_clear()
  displacement=max((p-q).length for sample in samples[1:-1] for p,q in zip(samples[0],sample));closure=max((p-q).length for p,q in zip(samples[0],samples[-1]));motion[name]={'maximum_sampled_vertex_displacement_m':displacement,'first_last_surface_gap_m':closure,'intentional_hold':name=='rest'}
  if name!='rest' and displacement<1e-5:errors.append(f'LOD{level}: clip {name} is static')
  if name!='wave' and closure>.001:errors.append(f'LOD{level}: clip {name} loop gap {closure}')
 arm.animation_data.action=None
 for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
 bpy.context.scene.frame_set(0);bpy.context.view_layer.update()
 if level==0:
  # Preserve the actual imported scene for fixed-view/engine inspection.
  bpy.ops.wm.save_as_mainfile(filepath=str(REPO/f'builds/jrpg-resident-renewal/{ident}/CH_{s["name"]}_CleanImport.blend'))
  scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.view_settings.view_transform='Standard';scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=360;scene.render.resolution_y=480;scene.render.resolution_percentage=100;scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';world=bpy.data.worlds.new('RoundtripWorld');scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
  for pos,energy,size in [((-2,-3,4),300,4),((3,-2,2.5),140,3),((0,3,3),180,3)]:
   light=bpy.data.lights.new('RoundtripLight','AREA');light.energy=energy;light.size=size;ob=bpy.data.objects.new(light.name,light);scene.collection.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector((0,0,.9))-ob.location).to_track_quat('-Z','Y').to_euler()
  cam=bpy.data.objects.new('RoundtripCamera',bpy.data.cameras.new('RoundtripCamera'));scene.collection.objects.link(cam);scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=1.95;center=Vector((0,0,s['height']/2))
  for angle,label in [(0,'front'),(65,'threequarter')]:
   az=math.radians(angle);cam.location=center+Vector((4*math.sin(az),-4*math.cos(az),.1));cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(ROOT/ident/f'review/roundtrip-{label}.png');bpy.ops.render.render(write_still=True)
 records.append({'level':level,'skin_connected':connected,'bone_count':len(arm.data.bones),'vertices':len(body.data.vertices),'rest_height_m':height,'motion':motion})
report={'resident':ident,'all_pass':not errors,'errors':errors,'blender_version':bpy.app.version_string,'lods':records,'limitation':'Agent-rendered asset motion/scale evidence. Actual game interaction, feet/furniture contacts and facial behavior are separate acceptance steps.'};(ROOT/ident/'review/roundtrip-check.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if errors:raise RuntimeError('Clean import checks failed: '+str(errors))
