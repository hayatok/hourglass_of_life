"""Stage distance LODs with shared geometry across UV seams before reduction.

The immutable raw and production LOD0 remain untouched. UVs stay per loop while
coincident mesh vertices weld, so edge collapse cannot open each atlas island.
"""
from pathlib import Path
import bpy,bmesh,json,struct,copy,hashlib,importlib.util,shutil
from collections import Counter
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];BUILD=REPO/'builds/haru-cute-pilot';OUT=BUILD/'r3-seam-fixed';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'source/CH_Haru_LegacyDelivery.blend'))
body=bpy.data.objects['CH_Haru_Body_LOD0'];arm=bpy.data.objects['CH_Haru_Rig']
source_bvh=BVHTree.FromPolygons([v.co for v in body.data.vertices],[list(p.vertices) for p in body.data.polygons],all_triangles=True)
for ob in list(bpy.data.collections['LOW'].objects):
    if ob.type=='MESH' and ob!=body:bpy.data.objects.remove(ob,do_unlink=True)
def uvs(ob):return Counter(tuple(round(v,8) for v in d.uv) for d in ob.data.uv_layers.active.data)
def topology(ob):
    bm=bmesh.new();bm.from_mesh(ob.data);r={'vertices':len(bm.verts),'faces':len(bm.faces),'boundary_edges':sum(e.is_boundary for e in bm.edges),'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges)};bm.free();return r
records=[]
for level,ratio in [(1,.42),(2,.12)]:
    ob=body.copy();ob.data=body.data.copy();ob.name=f'CH_Haru_Body_LOD{level}';ob.data.name=f'CH_Haru_BodyMesh_LOD{level}';bpy.data.collections['LOW'].objects.link(ob);ob.hide_render=False;ob.hide_set(False)
    before=topology(ob);uv_before=uvs(ob)
    bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6);bm.to_mesh(ob.data);bm.free();ob.data.update()
    after_weld=topology(ob);uv_after=uvs(ob);print('WELD_UV',before,after_weld,'lost',sum((uv_before-uv_after).values()),'added',sum((uv_after-uv_before).values()))
    assert not (uv_after-uv_before),'Weld invented original UV-loop coordinates'
    # Merge cleanup exposes a few millimetre-scale boundary patches. Close only
    # those bounded holes, projecting their UVs from the original nearby triangle.
    bm=bmesh.new();bm.from_mesh(ob.data);uv_layer=bm.loops.layers.uv.active
    filled=bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if e.is_boundary],sides=16)['faces']
    repair_areas=[]
    for face in filled:
        area=face.calc_area();assert area<1e-5,('Unexpected large repair',area);repair_areas.append(area)
        nearest,normal,index,distance=source_bvh.find_nearest(face.calc_center_median());source_face=body.data.polygons[index]
        points=[body.data.vertices[i].co for i in source_face.vertices]
        uv_points=[Vector((*body.data.uv_layers.active.data[i].uv,0)) for i in source_face.loop_indices]
        for loop in face.loops:loop[uv_layer].uv=barycentric_transform(loop.vert.co,*points,*uv_points).xy
        face.smooth=True
    wire=[e for e in bm.edges if not e.link_faces]
    if wire:bmesh.ops.delete(bm,geom=wire,context='EDGES')
    loose=[v for v in bm.verts if not v.link_faces]
    if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
    bm.to_mesh(ob.data);bm.free();ob.data.update();after_repair=topology(ob)
    bpy.context.view_layer.objects.active=ob
    modifier=ob.modifiers.new('Shared-vertex LOD reduction','DECIMATE');modifier.ratio=ratio;modifier.use_collapse_triangulate=True
    bpy.ops.object.modifier_move_up(modifier=modifier.name);bpy.ops.object.modifier_apply(modifier=modifier.name)
    for v in ob.data.vertices:
        retained=sorted([(g.group,g.weight) for g in v.groups if g.weight>=.01],key=lambda x:-x[1])[:4];total=sum(w for _,w in retained);assert total>0
        for index in [g.group for g in v.groups]:ob.vertex_groups[index].remove([v.index])
        for index,weight in retained:ob.vertex_groups[index].add([v.index],weight/total,'REPLACE')
    records.append({'level':level,'ratio':ratio,'before':before,'after_weld':after_weld,'after_small_repairs':after_repair,'small_repair_faces':len(filled),'repair_areas_m2':repair_areas,'uv_repair_policy':'New tiny patch UVs projected from nearest original source triangle; original retained UV-loop coordinates unchanged by weld.','after_reduction':topology(ob),'retained_uv_loop_coordinates_preserved_by_weld':True,'uv_loops_removed_during_merge':sum((uv_before-uv_after).values()),'max_weights':max(len(v.groups) for v in ob.data.vertices)})
    ob.hide_render=True;ob.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'CH_Haru_LodFix.blend'))
skill=Path.home()/'.codex/skills/blender-image-to-3d/scripts/export_delivery.py';spec=importlib.util.spec_from_file_location('delivery',skill);delivery=importlib.util.module_from_spec(spec);spec.loader.exec_module(delivery)
args=delivery.parse(['--blend',str(OUT/'CH_Haru_LodFix.blend'),'--out',str(OUT),'--name','CH_Haru','--format','GLB','--no-apply'])
shutil.copyfile(REPO/'game/assets/models/haru/CH_Haru.glb',OUT/'CH_Haru.glb')
def read(path):
    raw=path.read_bytes();n,k=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+n]);o=20+n;length,kind=struct.unpack_from('<II',raw,o);return doc,raw[o+8:o+8+length]
def write(path,doc,binary):
    js=json.dumps(doc,separators=(',',':')).encode();js+=b' '*((-len(js))%4);binary+=b'\0'*((-len(binary))%4);path.write_bytes(struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(binary))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(binary),0x004e4942)+binary)
for level in [1,2]:
    ob=bpy.data.objects[f'CH_Haru_Body_LOD{level}'];ob.hide_render=False;ob.hide_set(False);path=OUT/f'CH_Haru_LOD{level}.glb';delivery.export(str(path),[ob,arm],args);ob.hide_render=True;ob.hide_set(True)
    doc,binary=read(path)
    for field in ['images','textures','samplers']:doc.pop(field,None)
    doc['materials']=[{'name':'CH_Haru_GeometryOnly_RuntimeOverride','pbrMetallicRoughness':{'baseColorFactor':[1,1,1,1],'metallicFactor':0,'roughnessFactor':1}}]
    used={a['bufferView'] for a in doc['accessors'] if 'bufferView' in a};mapping={old:new for new,old in enumerate(sorted(used))};compact=bytearray();views=[]
    for old in sorted(used):
        v=copy.deepcopy(doc['bufferViews'][old]);start=v.get('byteOffset',0);data=binary[start:start+v['byteLength']];compact.extend(b'\0'*((-len(compact))%4));v['byteOffset']=len(compact);v['buffer']=0;compact.extend(data);views.append(v)
    for a in doc['accessors']:
        if 'bufferView' in a:a['bufferView']=mapping[a['bufferView']]
    doc['bufferViews']=views;doc['buffers']=[{'byteLength':len(compact)}];write(path,doc,bytes(compact))
report={'revision':'r3-seam-fixed-staging','installed':False,'weld_distance_m':1e-6,'source_lod0_unchanged':True,'raw_source_unchanged':True,'records':records,'glb_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('*.glb')}}
(ROOT/'review/lod-seams/seam-fixed-build.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
