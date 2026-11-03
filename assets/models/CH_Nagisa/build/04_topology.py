"""Keep the editable source intact; create a clean delivery copy with per-part binding tags."""
import bpy,bmesh,sys,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import mesh_helpers as H
ROOT=Path(__file__).resolve().parents[1]

def build():
    H.open_master(str(ROOT/'CH_Nagisa_master.blend'))
    source=list(bpy.data.collections['LOW'].objects)
    groups={'Body':[],'Face':[]}
    for ob in source:
        if ob.hide_render:
            for c in list(ob.users_collection):c.objects.unlink(ob)
            H.col('HIGH').objects.link(ob)
            continue
        bind=ob.get('bind','chest');face=ob.get('face_group','')
        if 'Finger' in ob.name:
            suffix=ob.name.split('Finger',1)[1].split('_LOD',1)[0]
            bind='finger'+suffix
        bpy.ops.object.select_all(action='DESELECT');ob.hide_set(False);ob.select_set(True)
        bpy.context.view_layer.objects.active=ob
        if ob.type=='CURVE':bpy.ops.object.convert(target='MESH')
        for modifier in list(ob.modifiers):
            if modifier.type!='ARMATURE':bpy.ops.object.modifier_apply(modifier=modifier.name)
        # Tags survive mesh joining and provide intentional region weights and face morph masks.
        tag=ob.vertex_groups.new(name='TAG_'+bind)
        tag.add(list(range(len(ob.data.vertices))),1,'REPLACE')
        if face:
            tag=ob.vertex_groups.new(name='FACE_'+face)
            tag.add(list(range(len(ob.data.vertices))),1,'REPLACE')
            if any(word in ob.name for word in ['Iris','Pupil','Glint']):
                tag=ob.vertex_groups.new(name='GAZE');tag.add(list(range(len(ob.data.vertices))),1,'REPLACE')
        bm=bmesh.new();bm.from_mesh(ob.data)
        if 'coverage_cut_z' in ob:
            bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.calc_center_median().z>ob['coverage_cut_z']],context='FACES')
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
        bad=[f for f in bm.faces if f.calc_area()<1e-10]
        bmesh.ops.delete(bm,geom=bad,context='FACES')
        loose=[v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm,geom=loose,context='VERTS')
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(ob.data);bm.free()
        ob.data.validate(clean_customdata=True);ob.data.update()
        groups['Face' if face else 'Body'].append(ob)
    counts={}
    for kind,objects in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for ob in objects:ob.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        bpy.ops.object.join();ob=bpy.context.object
        ob.name='CH_Nagisa_'+kind+'_LOD0';ob.data.name=ob.name+'_Mesh'
        ob['owner']='phase:04_topology';ob['mesh_role']=kind.lower()
        # Lock delivery triangulation. The source master retains its quad cage.
        bm=bmesh.new();bm.from_mesh(ob.data)
        bmesh.ops.triangulate(bm,faces=list(bm.faces),quad_method='BEAUTY',ngon_method='BEAUTY')
        bm.to_mesh(ob.data);bm.free()
        ob.data.validate(clean_customdata=True);ob.data.update()
        counts[kind]={'vertices':len(ob.data.vertices),'triangles':len(ob.data.polygons)}
    bpy.context.scene.view_settings.view_transform='Standard'
    H.save_master(str(ROOT/'CH_Nagisa_topology.blend'))
    (ROOT/'review/04_topology').mkdir(parents=True,exist_ok=True)
    (ROOT/'review/04_topology/counts.json').write_text(json.dumps(counts,indent=2))
    print('DELIVERY COUNTS',counts)

if __name__=='__main__':build()
