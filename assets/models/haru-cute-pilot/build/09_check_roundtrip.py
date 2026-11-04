"""Clean-import evidence for the delivered skin, nine motions and source images."""
from pathlib import Path
import bpy,json,struct,hashlib,math
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];OUT=REPO/'game/assets/models/haru'
manifest=json.loads((OUT/'asset-manifest.json').read_text());records=[];expected_binds=None
def read(path):
    data=path.read_bytes();n,k=struct.unpack_from('<II',data,12);doc=json.loads(data[20:20+n]);offset=20+n;bn,bk=struct.unpack_from('<II',data,offset);return doc,data[offset+8:offset+8+bn]
def accessor(doc,binary,index):
    a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];start=v.get('byteOffset',0)+a.get('byteOffset',0);components={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];types={5121:'B',5123:'H',5125:'I',5126:'f'};fmt='<'+types[a['componentType']]*components;size=struct.calcsize(fmt);stride=v.get('byteStride',size)
    return [struct.unpack_from(fmt,binary,start+i*stride) for i in range(a['count'])]
for filename in ['CH_Haru.glb','CH_Haru_LOD1.glb','CH_Haru_LOD2.glb']:
    path=OUT/filename;doc,binary=read(path);skin=doc['skins'][0];names=[doc['nodes'][j]['name'] for j in skin['joints']];matrices=accessor(doc,binary,skin['inverseBindMatrices']);binds=list(zip(names,matrices))
    if expected_binds is None:expected_binds=binds
    assert binds==expected_binds,'LOD bind pose/order changed'
    assert len(names)==35 and len(set(names))==35
    images=[]
    for i,im in enumerate(doc['images']):
        v=doc['bufferViews'][im['bufferView']];start=v.get('byteOffset',0);data=binary[start:start+v['byteLength']];sha=hashlib.sha256(data).hexdigest();assert sha==manifest['source_images'][i]['sha256'];images.append(sha)
    primitive=doc['meshes'][0]['primitives'][0];ws=accessor(doc,binary,primitive['attributes']['WEIGHTS_0']);assert all(abs(sum(w)-1)<1e-5 for w in ws);assert all(all(x>=0 for x in w) for w in ws)
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(path),merge_vertices=False)
    arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');body=next(o for o in bpy.context.scene.objects if o.type=='MESH')
    assert len(arm.data.bones)==35
    assert body.parent==arm and any(m.type=='ARMATURE' and m.object==arm for m in body.modifiers)
    actions={a.name:a for a in bpy.data.actions};assert sorted(actions)==['eat','idle','rest','sit_talk','sleep','talk','walk','wave','work']
    arm.animation_data_clear()
    for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update();points=[body.matrix_world@v.co for v in body.data.vertices];height=max(p.z for p in points)-min(p.z for p in points);assert abs(height-1.71)<(1e-5 if filename=='CH_Haru.glb' else .01),(filename,height)
    motion={};arm.animation_data_create()
    for name,action in actions.items():
        arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0];samples=[]
        for phase in [0,.25,.5,.75,1]:
            frame=float(action.frame_range[1])*phase;bpy.context.scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame));bpy.context.view_layer.update();ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh();samples.append([v.co.copy() for v in mesh.vertices]);ev.to_mesh_clear()
        displacement=max((p-q).length for sample in samples[1:-1] for p,q in zip(samples[0],sample));loop_seam=max((p-q).length for p,q in zip(samples[0],samples[-1]));assert name=='rest' or displacement>1e-5,name+' is static'
        if name!='wave':assert loop_seam<.001,(name,loop_seam)
        motion[name]={'max_sampled_vertex_displacement_m':displacement,'loop_seam_max_m':loop_seam,'intentional_hold_pose':name=='rest'}
    records.append({'file':filename,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,'vertices':len(body.data.vertices),'triangles':len(body.data.polygons),'skins':len(doc['skins']),'bones':len(names),'rest_height_m':height,'source_images_sha256':images,'matching_lod_bind_poses':True,'weight_sum_tolerance':1e-5,'motion':motion})
report={'passed':True,'blender_version':bpy.app.version_string,'raw_source_sha256':manifest['raw_source_sha256'],'face_gate':'incomplete/static atlas; not tested as facial animation','lods':records}
(ROOT/'review/roundtrip-check.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
