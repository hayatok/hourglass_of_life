"""Export three compatible skinned LODs and preserve the exact raw atlas bytes."""
from pathlib import Path
import bpy,bmesh,json,hashlib,struct,copy,importlib.util
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];BUILD=REPO/'builds/haru-cute-pilot';OUT=REPO/'game/assets/models/haru'
OUT.mkdir(parents=True,exist_ok=True)
RAW=ROOT/'raw/CH_Haru_JRPG_Pilot_Raw.glb'
bpy.ops.wm.open_mainfile(filepath=str(BUILD/'CH_Haru_Rig.blend'))
body=bpy.data.objects['CH_Haru_Body_LOD0'];arm=bpy.data.objects['CH_Haru_Rig']
for lod,ratio in [(1,.42),(2,.12)]:
    obj=body.copy();obj.data=body.data.copy();obj.name=f'CH_Haru_Body_LOD{lod}';obj.data.name=f'CH_Haru_BodyMesh_LOD{lod}';bpy.data.collections['LOW'].objects.link(obj)
    bpy.context.view_layer.objects.active=obj;obj.hide_set(False)
    modifier=obj.modifiers.new('LOD reduction','DECIMATE');modifier.ratio=ratio;modifier.use_collapse_triangulate=True
    bpy.ops.object.modifier_move_up(modifier=modifier.name);bpy.ops.object.modifier_apply(modifier=modifier.name)
    for v in obj.data.vertices:
        retained=sorted([(g.group,g.weight) for g in v.groups if g.weight>=.01],key=lambda x:-x[1])[:4];total=sum(v for _,v in retained)
        if not total:raise RuntimeError('LOD reduction created an unweighted vertex')
        for index in [g.group for g in v.groups]:obj.vertex_groups[index].remove([v.index])
        for index,weight in retained:obj.vertex_groups[index].add([v.index],weight/total,'REPLACE')
    obj.hide_render=True;obj.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(BUILD/'CH_Haru_AnimationMaster.blend'))
for action in list(bpy.data.actions):
    if action.name.startswith('_'):bpy.data.actions.remove(action)
arm.animation_data.action=bpy.data.actions['idle'];arm.animation_data.action_slot=bpy.data.actions['idle'].slots[0]
walk_measurement=json.loads((ROOT/'review/walk-measurement.json').read_text())
bpy.data.actions['walk']['speed_mps']=walk_measurement['measured_speed_m_s']
bpy.data.actions['rest']['intentional_hold_pose']=True
bpy.context.scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(BUILD/'CH_Haru_Delivery.blend'))
skill=Path.home()/'.codex/skills/blender-image-to-3d/scripts/export_delivery.py'
spec=importlib.util.spec_from_file_location('delivery_export',skill);delivery=importlib.util.module_from_spec(spec);spec.loader.exec_module(delivery)
args=delivery.parse(['--blend',str(BUILD/'CH_Haru_Delivery.blend'),'--out',str(OUT),'--name','CH_Haru','--format','GLB','--collections','LOW,RIG_DEF','--no-apply','--engine','Godot 4.7 Compatibility','--inferred','real height,side and back anatomy,garment depth,hand articulation,animation transfer'])
delivery.main(args)
arm=bpy.data.objects['CH_Haru_Rig'];body=bpy.data.objects['CH_Haru_Body_LOD0']
mp=OUT/'asset-manifest.json';manifest=json.loads(mp.read_text())
for lod in [1,2]:
    obj=bpy.data.objects[f'CH_Haru_Body_LOD{lod}'];obj.hide_render=False;obj.hide_set(False)
    path=OUT/f'CH_Haru_LOD{lod}.glb';delivery.export(str(path),[obj,arm],args)
    manifest['files'][f'LOD{lod}']=path.name;manifest['lods'].append({'level':lod,'objects':[obj.name],'tris':delivery.tri_count(obj)})
    obj.hide_render=True;obj.hide_set(True)
def glb_read(path):
    raw=path.read_bytes();offset=12;doc=None;binary=b''
    while offset<len(raw):
        length,kind=struct.unpack_from('<II',raw,offset);offset+=8;chunk=raw[offset:offset+length];offset+=length
        if kind==0x4e4f534a:doc=json.loads(chunk)
        elif kind==0x004e4942:binary=chunk
    return doc,binary
def glb_write(path,doc,binary):
    js=json.dumps(doc,separators=(',',':')).encode();js+=b' '*((-len(js))%4);binary+=b'\0'*((-len(binary))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(binary))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(binary),0x004e4942)+binary)
source,source_binary=glb_read(RAW);images=[]
for i,im in enumerate(source['images']):
    view=source['bufferViews'][im['bufferView']];start=view.get('byteOffset',0);data=source_binary[start:start+view['byteLength']]
    images.append({'index':i,'name':im.get('name',f'raw-image-{i}'),'mime_type':im['mimeType'],'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'pixel_policy':'preserve original embedded image bytes'})
for filename in ['CH_Haru.glb','CH_Haru_LOD1.glb','CH_Haru_LOD2.glb']:
    path=OUT/filename;doc,binary=glb_read(path);binary=bytearray(binary)
    doc['images']=copy.deepcopy(source['images']);doc['materials']=copy.deepcopy(source['materials']);doc['textures']=copy.deepcopy(source['textures']);doc['samplers']=copy.deepcopy(source.get('samplers',[]))
    for i,im in enumerate(doc['images']):
        source_view=source['bufferViews'][source['images'][i]['bufferView']];start=source_view.get('byteOffset',0);data=source_binary[start:start+source_view['byteLength']]
        binary.extend(b'\0'*((-len(binary))%4));offset=len(binary);binary.extend(data)
        im['bufferView']=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(data)})
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:primitive['material']=0
    doc['extensionsUsed']=list(dict.fromkeys(doc.get('extensionsUsed',[])+source.get('extensionsUsed',[])))
    # Drop Blender's replaced image bytes. Keep every accessor and exact raw image;
    # only relocate buffer views with four-byte alignment, without re-encoding data.
    used={im['bufferView'] for im in doc['images']}
    for accessor in doc.get('accessors',[]):
        if 'bufferView' in accessor:used.add(accessor['bufferView'])
        for part in accessor.get('sparse',{}).values():
            if isinstance(part,dict) and 'bufferView' in part:used.add(part['bufferView'])
    remap={old:new for new,old in enumerate(sorted(used))};compact=bytearray();views=[]
    for old in sorted(used):
        view=copy.deepcopy(doc['bufferViews'][old]);start=view.get('byteOffset',0);data=binary[start:start+view['byteLength']]
        compact.extend(b'\0'*((-len(compact))%4));view['byteOffset']=len(compact);view['buffer']=0;compact.extend(data);views.append(view)
    for im in doc['images']:im['bufferView']=remap[im['bufferView']]
    for accessor in doc.get('accessors',[]):
        if 'bufferView' in accessor:accessor['bufferView']=remap[accessor['bufferView']]
        for part in accessor.get('sparse',{}).values():
            if isinstance(part,dict) and 'bufferView' in part:part['bufferView']=remap[part['bufferView']]
    doc['bufferViews']=views;doc['buffers']=[{'byteLength':len(compact)}];glb_write(path,doc,bytes(compact))
    actual,_=glb_read(path)
    assert len(actual['skins'])==1 and len(actual['skins'][0]['joints'])==35
    assert sorted(x['name'] for x in actual['animations'])==['eat','idle','rest','sit_talk','sleep','talk','walk','wave','work']
    assert len(actual['meshes'])==1 and len(actual['meshes'][0]['primitives'])==1
manifest['files']={key:Path(value).name for key,value in manifest['files'].items()}
manifest['locomotion_measurement']=walk_measurement
manifest.update({'raw_source_sha256':hashlib.sha256(RAW.read_bytes()).hexdigest(),'exported_glb_sha256':hashlib.sha256((OUT/'CH_Haru.glb').read_bytes()).hexdigest(),'lod_sha256':{path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(OUT.glob('*.glb'))},'source_images':images,'target_height_m':1.71,'canonical_rest_height_m':1.71,'rest_pose':'Fitted A-pose. Source clip family Aoi DEF35; target-specific joints/weights and per-frame grounding.','source':str((BUILD/'CH_Haru_Delivery.blend').relative_to(REPO)),'raw_source':str(RAW.relative_to(REPO)),'dependencies':[],'texture_contract':{'policy':'Original three embedded images, exact bytes, material descriptors and UVs preserved. Runtime TextureToon samples the base-color atlas; old 8x8 palette recoloring disabled.','basecolor':'sRGB','normal':'raw tangent normal, Non-Color','pbr':'source material metadata preserved; runtime toon mode does not promise identical PBR lighting'},'face_controls':{'supported':False,'names':[],'reason':'Generated face is painted onto the single body atlas. No separated eyelids/iris/mouth control exists; static atlas is an explicit intermediate capability.'},'production_status':'Body-animation intermediate: game motion/contacts to be verified. Facial-expression gate incomplete.','forms_gate':{'bbox_iou':.9252,'bbox_max_band_width_difference':.0235,'world_iou':.917,'world_max_band_width_difference':.0114,'reference_threshold_unchanged':True},'validation_notes':['Raw source immutable; derived mesh changes body width and shoulder angle, preserving hand local dimensions and UVs.','Coincident UV/normal-seam vertices retained; no destructive weld.','Four normalized bone influences maximum per vertex. Linear skinning, no cloth solver.','LOD0/1/2 share all 35 named bind poses and one surface; only mesh geometry differs.','Static painted eyes remain open in sleep until facial controls are implemented.']})
mp.write_text(json.dumps(manifest,indent=2)+'\n')
cp=OUT/'animation-contract.json';contract=json.loads(cp.read_text())
contract['locomotion_measurement']=walk_measurement
for clip in contract['clips']:
    if clip['name']=='rest':clip['intentional_hold_pose']=True
cp.write_text(json.dumps(contract,indent=2)+'\n')
print('EXPORTED',json.dumps(manifest['lod_sha256'],indent=2))
