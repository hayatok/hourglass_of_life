"""Shared immutable raw import and calibrated reference setup for three residents."""
from pathlib import Path
import bpy,json,hashlib,struct,importlib.util
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];SPECS=json.loads((ROOT/'build/specs.json').read_text())
VENDOR=Path(__file__).resolve().parent/'vendor'
spec=importlib.util.spec_from_file_location('init_master',VENDOR/'init_master.py');init=importlib.util.module_from_spec(spec);spec.loader.exec_module(init)
def geometry_values(ob):
    return ([tuple(v.co) for v in ob.data.vertices],[tuple(face.vertices) for face in ob.data.polygons])
def geometry_hash(ob):
    h=hashlib.sha256()
    for v in ob.data.vertices:h.update(struct.pack('<3f',*v.co))
    for face in ob.data.polygons:
        for i in face.vertices:h.update(struct.pack('<I',i))
    return h.hexdigest()
for ident,s in SPECS.items():
    asset=ROOT/ident;ref=asset/'ref';raw=asset/f'raw/CH_{s["name"]}_JRPG_Raw.glb';raw_sha256=hashlib.sha256(raw.read_bytes()).hexdigest();cal=json.loads((ref/'calibration.json').read_text());build=REPO/f'builds/jrpg-resident-renewal/{ident}';build.mkdir(parents=True,exist_ok=True);master=build/f'CH_{s["name"]}_RawReview.blend'
    init.main(init.parse(['--out',str(master),'--name',f'CH_{s["name"]}','--height',str(s['height']),'--ref-front',str(ref/'front.png'),'--subject-frac',str(cal['subject_fraction']),'--ground-frac',str(cal['ground_fraction']),'--cam-elev','45','--cam-az','30','--cam-dist','10','--cam-lens','50']))
    refob=bpy.data.objects['REF_img_front'];refob.empty_display_size=cal['meters_per_pixel']*cal['image_size'][1];refob.empty_image_offset=(-cal['axis_column']/cal['image_size'][0],-cal['ground_fraction'])
    before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(raw),merge_vertices=False);imported=set(bpy.data.objects)-before;meshes=[o for o in imported if o.type=='MESH'];assert len(meshes)==1
    ob=meshes[0];ghash=geometry_hash(ob);local_geometry_before=geometry_values(ob);points=[ob.matrix_world@Vector(c) for c in ob.bound_box];lo=Vector([min(p[i] for p in points) for i in range(3)]);hi=Vector([max(p[i] for p in points) for i in range(3)]);scale=s['height']/(hi.z-lo.z)
    parent=bpy.data.objects.new(f'REVIEW_{s["name"]}_ScaleAndGround',None);bpy.data.collections['LOW'].objects.link(parent)
    for obj in imported:
        if obj.parent not in imported:world=obj.matrix_world.copy();obj.parent=parent;obj.matrix_world=world
        for col in list(obj.users_collection):col.objects.unlink(obj)
        bpy.data.collections['LOW'].objects.link(obj)
    parent.scale=(scale,scale,scale);parent.location=(-(lo.x+hi.x)*.5*scale,-(lo.y+hi.y)*.5*scale,-lo.z*scale);ob.name=f'CH_{s["name"]}_Body_LOD0';bpy.context.view_layer.update();local_geometry_unchanged=geometry_values(ob)==local_geometry_before;assert local_geometry_unchanged,'Review transform changed local vertex values or face indices'
    ob.data.calc_loop_triangles();images=[{'name':im.name,'size':list(im.size),'colorspace':im.colorspace_settings.name} for mat in ob.data.materials for node in mat.node_tree.nodes if node.type=='TEX_IMAGE' and (im:=node.image)]
    report={'raw_sha256':raw_sha256,'raw_bytes':raw.stat().st_size,'provenance_only':{'declared_raw_sha256':s['raw_sha256'],'observed_raw_sha256':raw_sha256,'raw_local_geometry_sha256_before':ghash,'raw_local_geometry_sha256_after':geometry_hash(ob),'policy':'Identifiers only; no fingerprint comparison or quality gate.'},'local_geometry_unchanged':local_geometry_unchanged,'geometry_comparison':'Direct vertex-coordinate and polygon-index arrays, not fingerprints.','original_bounds':{'min':list(lo),'max':list(hi)},'review_scale':scale,'review_height_m':s['height'],'vertices':len(ob.data.vertices),'triangles':len(ob.data.loop_triangles),'meshes':1,'materials':len(ob.material_slots),'images':images,'skins':sum(o.type=='ARMATURE' for o in imported),'clips':list(bpy.data.actions.keys()),'shape_keys':list(ob.data.shape_keys.key_blocks.keys()) if ob.data.shape_keys else [],'inferred':'Side/back and physical height/joints; single front concept only.'};(asset/'review/raw-import.json').write_text(json.dumps(report,indent=2)+'\n');bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(master));print('RAW_REVIEW',ident,json.dumps(report))
