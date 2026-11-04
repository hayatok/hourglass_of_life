"""Export one accepted body with compatible, seam-welded, texture-free LODs."""
from pathlib import Path
import bpy,bmesh,json,sys,hashlib,importlib.util
from mathutils import Matrix
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];sys.path.insert(0,str(ROOT/'build'));import gltf_io
SPECS=json.loads((ROOT/'build/specs.json').read_text());ident=sys.argv[sys.argv.index('--')+1];s=SPECS[ident];build=REPO/f'builds/jrpg-resident-renewal/{ident}';OUT=ROOT/ident/'exports';OUT.mkdir(exist_ok=True);(OUT/".gdignore").touch()
bpy.ops.wm.open_mainfile(filepath=str(build/f'CH_{s["name"]}_Rig.blend'));body=bpy.data.objects[f'CH_{s["name"]}_Body_LOD0'];arm=bpy.data.objects[f'CH_{s["name"]}_Rig'];raw=ROOT/ident/f'raw/CH_{s["name"]}_JRPG_Raw.glb';raw_sha256=hashlib.sha256(raw.read_bytes()).hexdigest()
# Finish all newly baked tracks with deliberate interpolation.
for action in bpy.data.actions:
 for layer in action.layers:
  for strip in layer.strips:
   for bag in strip.channelbags:
    for curve in bag.fcurves:
     for key in curve.keyframe_points:key.interpolation='LINEAR'
# Measure target foot trajectory instead of copying the source's authored speed.
walk=bpy.data.actions['walk'];arm.animation_data_create();arm.animation_data.action=walk;arm.animation_data.action_slot=walk.slots[0];end=int(walk.frame_range[1]);samples=[]
for frame in range(end+1):
 bpy.context.scene.frame_set(frame);bpy.context.view_layer.update();samples.append({side:arm.pose.bones['DEF-foot.'+side].matrix.translation.copy() for side in ['L','R']})
low={side:min(row[side].z for row in samples) for side in ['L','R']};support=[]
for side in ['L','R']:
 for frame in range(end):
  a=samples[frame][side];b=samples[frame+1][side];velocity=(b.y-a.y)*30
  if velocity>0 and max(a.z,b.z)<=low[side]+.04:support.append({'side':side,'frame':frame,'velocity_m_s':velocity,'height_m':a.z})
assert support,'No valid support samples for walk speed';speed=sum(row['velocity_m_s'] for row in support)/len(support);walk['speed_mps']=speed
measurement={'fps':30,'cycle_seconds':end/30,'method':'Mean backward foot-joint velocity in target low-support window (within40mm of each foot minimum).','support_samples':support,'speed_mps':speed,'limitation':'Playback best fit only; variable inherited stance velocity does not prove zero sliding.'}
(ROOT/ident/'review/walk-measurement.json').write_text(json.dumps(measurement,indent=2)+'\n')
arm.animation_data.action=None
for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.scene.frame_set(0)
lods=[]
for level,ratio in [(1,.42),(2,.16)]:
 ob=body.copy();ob.data=body.data.copy();ob.name=f'CH_{s["name"]}_Body_LOD{level}';ob.data.name=ob.name+'_Mesh';bpy.data.collections['LOW'].objects.link(ob);ob.hide_render=False;ob.hide_set(False)
 bm=bmesh.new();bm.from_mesh(ob.data);before=len(bm.verts);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6);welded=len(bm.verts);bm.to_mesh(ob.data);bm.free();ob.data.update();bpy.context.view_layer.objects.active=ob
 dec=ob.modifiers.new('Seam-welded LOD reduction','DECIMATE');dec.ratio=ratio;dec.use_collapse_triangulate=True;bpy.ops.object.modifier_move_up(modifier=dec.name);bpy.ops.object.modifier_apply(modifier=dec.name)
 for v in ob.data.vertices:
  kept=sorted([(g.group,g.weight) for g in v.groups if g.weight>=.01],key=lambda x:-x[1])[:4];total=sum(w for _,w in kept);assert total>0
  for index in [g.group for g in v.groups]:ob.vertex_groups[index].remove([v.index])
  for index,weight in kept:ob.vertex_groups[index].add([v.index],weight/total,'REPLACE')
 ob.data.calc_loop_triangles();lods.append({'level':level,'objects':[ob.name],'tris':len(ob.data.loop_triangles),'preweld_vertices':before,'welded_vertices':welded,'ratio':ratio});ob.hide_render=True;ob.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(build/f'CH_{s["name"]}_AnimationMaster.blend'))
for action in list(bpy.data.actions):
 if action.name.startswith('_'):bpy.data.actions.remove(action)
arm.animation_data.action=bpy.data.actions['idle'];arm.animation_data.action_slot=bpy.data.actions['idle'].slots[0];bpy.context.scene.frame_set(0);delivery_path=build/f'CH_{s["name"]}_Delivery.blend';bpy.ops.wm.save_as_mainfile(filepath=str(delivery_path))
module_path=Path(__file__).resolve().parent/'vendor/export_delivery.py';module_spec=importlib.util.spec_from_file_location('delivery',module_path);delivery=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(delivery)
args=delivery.parse(['--blend',str(delivery_path),'--out',str(OUT),'--name','CH_'+s['name'],'--format','GLB','--collections','LOW,RIG_DEF','--no-apply','--engine','Godot4.7 Compatibility','--inferred','real height,side/back anatomy,hidden garment depth,joints,body animation retarget'])
delivery.main(args)
body=bpy.data.objects[f'CH_{s["name"]}_Body_LOD0'];arm=bpy.data.objects[f'CH_{s["name"]}_Rig'];base=OUT/f'CH_{s["name"]}.glb';gltf_io.preserve_source_textures(base,raw)
mp=OUT/'asset-manifest.json';manifest=json.loads(mp.read_text())
for level in [1,2]:
 ob=bpy.data.objects[f'CH_{s["name"]}_Body_LOD{level}'];ob.hide_render=False;ob.hide_set(False);path=OUT/f'CH_{s["name"]}_LOD{level}.glb';delivery.export(str(path),[ob,arm],args);gltf_io.geometry_only_material(path);ob.hide_render=True;ob.hide_set(True);manifest['files'][f'LOD{level}']=path.name
manifest['files']={k:Path(v).name for k,v in manifest['files'].items()};manifest['lods']+=lods;manifest.update({'resident':ident,'revision':'body-r1','raw_source':str(raw.relative_to(REPO)),'raw_source_sha256':raw_sha256,'provenance_only':{'declared_raw_source_sha256':s['raw_sha256'],'observed_raw_source_sha256':raw_sha256,'policy':'Identifiers only; no fingerprint comparison or quality gate.'},'exported_glb_sha256':hashlib.sha256(base.read_bytes()).hexdigest(),'lod_sha256':{path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in OUT.glob('*.glb')},'source_images':gltf_io.source_images(raw),'source':str(delivery_path.relative_to(REPO)),'canonical_rest_height_m':s['height'],'dependencies':[],'locomotion_measurement':measurement,'body_binding':json.loads((ROOT/ident/'production-inputs/bind-report.json').read_text()),'forms_gate':{'bbox':json.loads((ROOT/ident/'production-inputs/forms-compare-front.json').read_text()),'world':json.loads((ROOT/ident/'production-inputs/forms-world-front/gate_front.json').read_text())},'face_controls':{'supported':False,'names':[],'status':'Body delivery only. Individual UV-eye calibration/actor integration supplied separately by GP; no facial blend shapes are present.'},'texture_contract':{'policy':'LOD0 exact original encoded images/UVs/material metadata; distance LODs have zero images and one slot, retaining actor override.','basecolor':'sRGB','normal':'raw tangent normal, Non-Color','distance_lod_standalone_preview':'intentionally untextured; source PBR inspection through LOD0/actor'},'production_status':'Body candidate pending roundtrip/engine/contact acceptance; no final character/fun claim.'})
document,_=gltf_io.read(base);bind_names=[document['nodes'][i]['name'] for i in document['skins'][0]['joints']]
part_key=f'CH_{s["name"]}_Body'
manifest['runtime_contract']={'bone_count':len(arm.data.bones),'required_named_bones':bind_names,'skin_bind_count':len(bind_names),'skin_bind_names':bind_names,'mesh_part_keys':[part_key],'surface_counts':{part_key:1}}
mp.write_text(json.dumps(manifest,indent=2)+'\n');cp=OUT/'animation-contract.json';contract=json.loads(cp.read_text());contract['locomotion_measurement']=measurement
for clip in contract['clips']:
 if clip['name']=='rest':clip['intentional_hold_pose']=True
cp.write_text(json.dumps(contract,indent=2)+'\n');print('EXPORT_BODY',ident,manifest['lods'],speed)
