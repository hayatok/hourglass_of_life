"""The generic roundtrip renders the first imported clip (eat). Measure scale in the rest pose.
Check the exported geometry, skin, morphs, images, clip times, and absence of external GLB data.
"""
import bpy,json,struct,sys
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
profile_path=ROOT/'profile.json'
expected_height=json.loads(profile_path.read_text()).get('height',1.65) if profile_path.exists() else 1.65
manifest=json.loads((ROOT/'exports/asset-manifest.json').read_text())
contract=json.loads((ROOT/'exports/animation-contract.json').read_text())
report={'lods':[],'failures':[]}
for lod in [0,1,2]:
    file=ROOT/'exports'/('CH_Nagisa.glb' if lod==0 else f'CH_Nagisa_LOD{lod}.glb')
    raw=file.read_bytes();length=struct.unpack_from('<I',raw,12)[0];gltf=json.loads(raw[20:20+length])
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(file))
    scene=bpy.context.scene;arms=[o for o in scene.objects if o.type=='ARMATURE']
    for arm in arms:
        arm.animation_data_clear();arm.data.pose_position='REST'
        for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();points=[];tris=0
    low=bpy.data.collections.new('LOW');scene.collection.children.link(low)
    for ob in list(scene.objects):
        if ob.type!='MESH' or not any(m.type=='ARMATURE' for m in ob.modifiers):continue
        low.objects.link(ob)
        if ob.data.shape_keys:
            ob.data.shape_keys.animation_data_clear()
            for key in ob.data.shape_keys.key_blocks:key.value=0
            if len(ob.data.shape_keys.key_blocks)!=7:report['failures'].append(f'LOD{lod} missing face morphs')
        e=ob.evaluated_get(dg);mesh=e.to_mesh();tris+=sum(len(p.vertices)-2 for p in mesh.polygons)
        points.extend(e.matrix_world@Vector(v) for v in e.bound_box);e.to_mesh_clear()
    height=max(p.z for p in points)-min(p.z for p in points);floor=min(p.z for p in points)
    expected=next(r['tris'] for r in manifest['lods'] if r['level']==lod)
    if abs(height-expected_height)/expected_height>.01:report['failures'].append(f'LOD{lod} rest height {height}')
    if floor<-.002:report['failures'].append(f'LOD{lod} below floor')
    if tris!=expected:report['failures'].append(f'LOD{lod} triangle count {tris} != {expected}')
    expected_bones=set(manifest['skeleton'][0]['deform_bones'])
    if len(arms)!=1 or set(b.name for b in arms[0].data.bones)!=expected_bones:report['failures'].append(f'LOD{lod} bone mismatch')
    imported={a['name']:a for a in gltf.get('animations',[])}
    if set(imported)!={c['name'] for c in contract['clips']}:report['failures'].append(f'LOD{lod} clip mismatch')
    for clip in contract['clips']:
        animation=imported[clip['name']]
        end=max(gltf['accessors'][s['input']]['max'][0] for s in animation['samplers'])
        if abs(end-clip['length_s'])>.0001:report['failures'].append(f'LOD{lod} clip duration {clip["name"]}')
    if any('uri' in r for r in gltf.get('images',[])+gltf.get('buffers',[])):report['failures'].append(f'LOD{lod} external dependency')
    if len(gltf.get('images',[]))!=3:report['failures'].append(f'LOD{lod} image mismatch')
    row={'level':lod,'rest_height_m':round(height,5),'floor_min_m':round(floor,5),'triangles':tris,
         'bones':len(arms[0].data.bones),'clips':len(imported),'embedded_images':len(gltf['images'])}
    report['lods'].append(row)
    directory=ROOT/'review/09_roundtrip'/f'LOD{lod}';directory.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(directory/'imported-rest.blend'))
(ROOT/'review/09_roundtrip/rest-contract-checks.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
if report['failures']:raise RuntimeError('Imported contract differs from delivery')
