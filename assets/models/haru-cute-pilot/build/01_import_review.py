"""Import the frozen GLB for review only. No mesh vertex/topology edits."""
from pathlib import Path
import bpy,json,hashlib,struct,math
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parents[2]
MASTER=REPO/'builds/haru-cute-pilot/CH_Haru_JRPG_Pilot_Review.blend'
RAW=ROOT/'raw/CH_Haru_JRPG_Pilot_Raw.glb'
bpy.ops.wm.open_mainfile(filepath=str(MASTER))
# Idempotent: remove only a preceding review import and its placement parent.
for obj in list(bpy.data.collections['LOW'].objects):bpy.data.objects.remove(obj,do_unlink=True)
cal=json.loads((ROOT/'ref/calibration.json').read_text())
reference=bpy.data.objects.get('REF_img_front')
if reference:
    reference.empty_display_size=cal['meters_per_pixel']*cal['image_size'][1]
    reference.empty_image_offset=(-cal['axis_column']/cal['image_size'][0],-cal['ground_fraction'])
previous=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(RAW),merge_vertices=False)
imported=set(bpy.data.objects)-previous
meshes=[obj for obj in imported if obj.type=='MESH']
def local_hash(obj):
    digest=hashlib.sha256()
    for vertex in obj.data.vertices:digest.update(struct.pack('<3f',*vertex.co))
    for face in obj.data.polygons:
        for index in face.vertices:digest.update(struct.pack('<I',index))
    return digest.hexdigest()
before={obj.name:local_hash(obj) for obj in meshes}
points=[obj.matrix_world@Vector(c) for obj in meshes for c in obj.bound_box]
lo=Vector([min(p[i] for p in points) for i in range(3)])
hi=Vector([max(p[i] for p in points) for i in range(3)])
original_bounds={'min':list(lo),'max':list(hi),'size':list(hi-lo)}
scale=1.77/(hi.z-lo.z) # inferred: match current Haru presentation, not measured reference metres.
driver=bpy.data.objects.new('REVIEW_ScaleAndGround',None);bpy.data.collections['LOW'].objects.link(driver)
for obj in imported:
    if obj.parent not in imported:
        world=obj.matrix_world.copy();obj.parent=driver;obj.matrix_world=world
    for collection in list(obj.users_collection):collection.objects.unlink(obj)
    bpy.data.collections['LOW'].objects.link(obj)
driver.scale=(scale,scale,scale)
driver.location=(-(lo.x+hi.x)*.5*scale,-(lo.y+hi.y)*.5*scale,-lo.z*scale)
bpy.context.view_layer.update()
mesh_records=[]
for index,obj in enumerate(meshes):
    obj.data.calc_loop_triangles()
    # Changing the review object's label does not alter its raw mesh data.
    original_name=obj.name
    obj.name='CH_Haru_JRPG_Pilot_Body_LOD0' if len(meshes)==1 else f'CH_Haru_JRPG_Pilot_Part{index}_LOD0'
    assert before[original_name]==local_hash(obj)
    mesh_records.append({'source_object':original_name,'review_object':obj.name,'vertices':len(obj.data.vertices),'polygons':len(obj.data.polygons),'triangles':len(obj.data.loop_triangles),'uv_layers':list(obj.data.uv_layers.keys()),'material_slots':len(obj.material_slots),'shape_keys':list(obj.data.shape_keys.key_blocks.keys()) if obj.data.shape_keys else [],'geometry_hash_before':before[original_name],'geometry_hash_after':local_hash(obj)})
materials=[]
for material in {slot.material for obj in meshes for slot in obj.material_slots if slot.material}:
    materials.append({'name':material.name,'nodes':[(node.type,node.image.name if node.type=='TEX_IMAGE' and node.image else '') for node in material.node_tree.nodes]})
images=[{'name':image.name,'size':list(image.size),'color_space':image.colorspace_settings.name,'packed':bool(image.packed_file)} for image in bpy.data.images if image.name not in ['Render Result','Viewer Node'] and image.source!='GENERATED' and image.name!='front.png']
report={'raw_file':str(RAW.relative_to(REPO)),'raw_sha256':hashlib.sha256(RAW.read_bytes()).hexdigest(),'raw_bytes':RAW.stat().st_size,'blender_version':bpy.app.version_string,'source_bounds_m_as_imported':original_bounds,'review_parent_uniform_scale':scale,'review_parent_translation':list(driver.location),'normalised_review_height_m':1.77,'mesh_local_geometry_unchanged':True,'meshes':mesh_records,'materials':materials,'images':images,'armatures':sum(obj.type=='ARMATURE' for obj in imported),'animations':list(bpy.data.actions.keys()),'note':'Review placement is on one empty parent; raw file, local vertices and face indices remain unchanged. Physical height is inferred. Rig/skin/animation integration is not complete.'}
(ROOT/'review/raw-import.json').write_text(json.dumps(report,indent=2)+'\n')
# Embed review dependencies; the immutable raw GLB remains the adopted download.
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(MASTER))
print(json.dumps(report,indent=2))
