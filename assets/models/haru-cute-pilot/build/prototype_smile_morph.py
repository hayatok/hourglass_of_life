#!/usr/bin/env python3
"""Bounded geometry-Smile prototype on a copy of Haru LOD0, not a production export.

Run: Blender --background --python assets/models/haru-cute-pilot/build/prototype_smile_morph.py
A compact smooth 3D field moves coincident seam vertices by exactly the same delta.
The original UVs, atlas, binding and source files remain intact. No drawn mouth/fill.
"""
from pathlib import Path
import hashlib
import json
import math
import struct
import sys
import bpy
from mathutils import Matrix, Vector

def smile_delta(point, left_corner, right_corner, radii, lift, spread, forward):
    """Reusable seam-independent field; importing this module performs no scene/file work.

    Coordinates: canonical 1.71m rest body in Blender metres, X right, Y back,
    Z up (front -Y). For a mesh with transforms, evaluate point in that frame
    and convert the returned displacement back with the inverse mesh basis.
    Evaluate AFTER each LOD geometry has been finalized, before skinning.
    Do not apply Decimate on a mesh with pre-existing Smile keys.
    """
    point=Vector(point);radii=Vector(radii)
    delta=Vector()
    for corner, sign in [(Vector(left_corner),-1),(Vector(right_corner),1)]:
        distance=sum(((point[i]-corner[i])/radii[i])**2 for i in range(3))
        if distance<1:
            delta+=Vector((sign*spread,-forward,lift))*((1-distance)**3)
    return delta


def triangle_stability(body):
    """Check local face orientation/area on the real nonzero morph."""
    body.data.calc_loop_triangles()
    base=body.data.shape_keys.key_blocks['Basis'].data
    shaped=body.data.shape_keys.key_blocks['Smile'].data
    normal_dots=[]
    area_ratios=[]
    for triangle in body.data.loop_triangles:
        ids=triangle.vertices
        if not any((shaped[i].co-base[i].co).length>1e-8 for i in ids):
            continue
        a,b,c=[base[i].co for i in ids]
        x,y,z=[shaped[i].co for i in ids]
        before=(b-a).cross(c-a)
        after=(y-x).cross(z-x)
        if before.length<1e-12:
            continue
        assert after.length>1e-12, 'Morph collapsed a nonzero triangle'
        normal_dots.append(before.normalized().dot(after.normalized()))
        area_ratios.append(after.length/before.length)
    assert normal_dots and min(normal_dots)>0, 'Morph flipped a triangle'
    return {'affected_triangles':len(normal_dots),'minimum_normal_dot':min(normal_dots),'area_ratio_min':min(area_ratios),'area_ratio_max':max(area_ratios),'flipped_or_collapsed_triangles':0}


def run_prototype():
    REPO = Path(__file__).resolve().parents[4]
    PILOT = REPO / 'assets/models/haru-cute-pilot'
    OUT = PILOT / 'review/smile-morph'
    VARIANT = 'cheek-supported' if '--cheek-supported' in sys.argv else 'tight-corners'
    if VARIANT == 'cheek-supported':
        OUT = OUT / VARIANT
    SOURCE = PILOT / 'source/CH_Haru_LegacyDelivery.blend'
    RAW = PILOT / 'raw/CH_Haru_JRPG_Pilot_Raw.glb'
    GAME = REPO / 'game/assets/models/haru/CH_Haru.glb'
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    source_hashes = {str(path.relative_to(REPO)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [SOURCE, RAW, GAME]}
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    body = bpy.data.objects['CH_Haru_Body_LOD0']
    arm = bpy.data.objects['CH_Haru_Rig']
    scene = bpy.context.scene
    # Freeze the actual rig in its rest pose; do not apply/bake away the Armature modifier.
    arm.animation_data_clear()
    for bone in arm.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    scene.frame_set(0)
    bpy.context.view_layer.update()
    for obj in scene.objects:
        if obj.type in ['MESH', 'CURVE', 'FONT']:
            obj.hide_render = obj != body
    body.hide_set(False)
    body.hide_render = False


    def uv_hash():
        return hashlib.sha256(b''.join(struct.pack('<2f', *item.uv) for item in body.data.uv_layers.active.data)).hexdigest()


    def weights_hash():
        values = [(v.index, [(g.group, g.weight) for g in v.groups]) for v in body.data.vertices]
        return hashlib.sha256(json.dumps(values).encode()).hexdigest()


    def packed_images():
        return {image.name: hashlib.sha256(bytes(image.packed_file.data)).hexdigest() for image in bpy.data.images if image.packed_file}


    def barycentric(point, a, b, c):
        denominator = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(denominator) < 1e-12:
            return None
        u = ((b[1]-c[1])*(point[0]-c[0])+(c[0]-b[0])*(point[1]-c[1]))/denominator
        v = ((c[1]-a[1])*(point[0]-c[0])+(a[0]-c[0])*(point[1]-c[1]))/denominator
        w = 1-u-v
        return (u, v, w) if min(u, v, w) >= -1e-6 else None


    def point_from_gltf_uv(uv, coordinates=None):
        """Use the source painted-mouth UV only to calibrate an actual 3D landmark."""
        wanted = (uv[0], 1-uv[1])  # Blender/glTF V convention.
        uv_data = body.data.uv_layers.active.data
        hits = []
        for triangle in body.data.loop_triangles:
            weights = barycentric(wanted, *[uv_data[i].uv for i in triangle.loops])
            if weights is None:
                continue
            point = sum(((coordinates[i] if coordinates is not None else body.data.vertices[i].co) * weight for i, weight in zip(triangle.vertices, weights)), Vector())
            hits.append(point)
        if not hits:
            raise RuntimeError(f'No mesh triangle covers source UV {uv}')
        return min(hits, key=lambda p: p.y)  # Haru faces Blender -Y.


    body.data.calc_loop_triangles()
    uv_before = uv_hash()
    weights_before = weights_hash()
    images_before = packed_images()
    base_positions = [vertex.co.copy() for vertex in body.data.vertices]
    landmarks = json.loads((PILOT/'production-inputs/texture-face/landmarks.json').read_text())
    original_curve = landmarks['original_mouth']
    left = point_from_gltf_uv(original_curve[0][:2])
    right = point_from_gltf_uv(original_curve[-1][2:])
    center = point_from_gltf_uv(landmarks['mouth']['center']['uv'])
    assert left.x < 0 < right.x
    # Measured calibration landmarks come from the unchanged painted mouth. The
    # movement below is an authored small expression, not inferred muscle anatomy.
    RADII = Vector((.034, .030, .027)) if VARIANT == 'cheek-supported' else Vector((.023, .024, .021))  # X, depth Y, height Z; compact support in metres.
    LIFT = .0050 if VARIANT == 'cheek-supported' else .0045
    SPREAD = .0015 if VARIANT == 'cheek-supported' else .0012
    FORWARD = .0004


    def field(point):
        return smile_delta(point,left,right,RADII,LIFT,SPREAD,FORWARD)


    # Imported UV/normal seams may duplicate vertices. Group only already-coincident
    # positions and evaluate one 3D field per group; do not weld or change topology.
    groups = {}
    for vertex in body.data.vertices:
        key = tuple(round(float(value), 7) for value in vertex.co)
        groups.setdefault(key, []).append(vertex.index)
    assert body.data.shape_keys is None, 'Prototype must start from the source without replacing existing shapes'
    basis = body.shape_key_add(name='Basis', from_mix=False)
    smile = body.shape_key_add(name='Smile', from_mix=False)
    smile.slider_min = 0
    smile.slider_max = 1
    moved = []
    max_delta = 0.0
    max_group_delta_error = 0.0
    for ids in groups.values():
        representative = sum((base_positions[i] for i in ids), Vector())/len(ids)
        delta = field(representative)
        for index in ids:
            smile.data[index].co = base_positions[index]+delta
            if delta.length > 1e-8:
                moved.append(index)
                max_delta = max(max_delta, delta.length)
        if len(ids) > 1:
            first = smile.data[ids[0]].co-basis.data[ids[0]].co
            for index in ids[1:]:
                max_group_delta_error = max(max_group_delta_error, (smile.data[index].co-basis.data[index].co-first).length)
    assert moved and max_delta > .001, 'Smile must contain an actual visible geometry change'
    assert max_group_delta_error < 1e-7
    assert all((vertex.co-base_positions[vertex.index]).length == 0 for vertex in body.data.vertices)
    lo = [min(base_positions[i][axis] for i in moved) for axis in range(3)]
    hi = [max(base_positions[i][axis] for i in moved) for axis in range(3)]
    # Verify that the eye/brow region is outside the field, not stretched for a smile.
    upper_displacement = max(((smile.data[i].co-basis.data[i].co).length for i,p in enumerate(base_positions) if p.z > 1.49), default=0)
    assert upper_displacement == 0
    triangle_check=triangle_stability(body)
    shaped_positions = [point.co.copy() for point in smile.data]
    mouth_deltas = {
        'left':point_from_gltf_uv(original_curve[0][:2],shaped_positions)-left,
        'right':point_from_gltf_uv(original_curve[-1][2:],shaped_positions)-right,
        'center':point_from_gltf_uv(landmarks['mouth']['center']['uv'],shaped_positions)-center,
    }
    assert mouth_deltas['left'].z > .001 and mouth_deltas['right'].z > .001

    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.cycles.device = 'CPU'
    scene.render.resolution_x = scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    for obj in list(scene.objects):
        if obj.type == 'LIGHT':
            bpy.data.objects.remove(obj, do_unlink=True)
    world = scene.world or bpy.data.worlds.new('SmileWorld')
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.13,.16,.21,1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = .35
    for name, position, energy, size in [('Key',(-2,-3,4),250,4),('Fill',(3,-2,2.5),120,3),('Rim',(0,3,3),200,3)]:
        light = bpy.data.lights.new('Smile'+name,'AREA')
        light.energy = energy
        light.size = size
        obj = bpy.data.objects.new(light.name,light)
        scene.collection.objects.link(obj)
        obj.location = position
        obj.rotation_euler = (Vector((0,0,1.5))-obj.location).to_track_quat('-Z','Y').to_euler()
    camera = bpy.data.objects.new('SmileCamera',bpy.data.cameras.new('SmileCamera'))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = .44
    focus = Vector((0,-.025,1.515))
    renders = []
    for angle, view in [(0,'front'),(30,'threequarter')]:
        radians = math.radians(angle)
        camera.location = focus+Vector((3.5*math.sin(radians),-3.5*math.cos(radians),0))
        camera.rotation_euler = (focus-camera.location).to_track_quat('-Z','Y').to_euler()
        for strength, label in [(0,'neutral'),(.5,'smile-half'),(1,'smile-full')]:
            smile.value = strength
            bpy.context.view_layer.update()
            name = f'{view}-{label}.png'
            scene.render.filepath = str(OUT/name)
            bpy.ops.render.render(write_still=True)
            renders.append({'file':name,'angle_degrees':angle,'strength':strength})
    smile.value = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'CH_Haru_Smile_Prototype.blend'))
    # Export only the prototype LOD0 + unchanged skin; the body-action library is
    # deliberately not exported here. This file is not a game-model replacement.
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.gltf(filepath=str(OUT/'CH_Haru_Smile_Prototype.glb'),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_morph=True,export_morph_normal=True,export_extras=True)
    export_bytes = (OUT/'CH_Haru_Smile_Prototype.glb').read_bytes()
    json_size = struct.unpack_from('<I',export_bytes,12)[0]
    export_doc = json.loads(export_bytes[20:20+json_size])
    export_binary = export_bytes[28+json_size:]
    assert len(export_doc['meshes']) == 1 and len(export_doc['skins']) == 1 and len(export_doc['skins'][0]['joints']) == 35
    primitive = export_doc['meshes'][0]['primitives'][0]
    assert export_doc['meshes'][0]['extras']['targetNames'] == ['Smile'] and len(primitive['targets']) == 1
    exported_images = {}
    for image in export_doc['images']:
        view = export_doc['bufferViews'][image['bufferView']]
        start = view.get('byteOffset',0)
        exported_images[image['name']] = hashlib.sha256(export_binary[start:start+view['byteLength']]).hexdigest()
    report = {
        'purpose':'Geometry Smile feasibility on a copied rigged LOD0; not production integration or gameplay.',
        'variant':VARIANT,
        'provenance':{'source_files_sha256':source_hashes,'source_files_sha256_after':{name:hashlib.sha256((REPO/name).read_bytes()).hexdigest() for name in source_hashes},'note':'Fingerprints identify source data only and are not acceptance tests.'},
        'morph':'Smile',
        'strength_range':[0,1],
        'field':'Two compact C2 kernels: w=max(0,1-squared_ellipsoid_distance)^3. Same 3D field for all coincident UV/normal seam vertices.',
        'corner_landmarks_m':{'left':list(left),'right':list(right),'mouth_center':list(center)},
        'field_radii_m':list(RADII),'corner_target_lift_m':LIFT,'corner_target_spread_m':SPREAD,'corner_target_forward_m':FORWARD,
        'actual_painted_mouth_displacement_m':{name:list(delta) for name,delta in mouth_deltas.items()},
        'moved_vertices':len(moved),'vertices':len(body.data.vertices),'triangles':len(body.data.polygons),
        'affected_bounds_m':{'min':lo,'max':hi},'maximum_vertex_displacement_m':max_delta,
        'coincident_vertex_groups':sum(len(ids)>1 for ids in groups.values()),'maximum_delta_difference_at_coincident_vertices_m':max_group_delta_error,
        'upper_face_displacement_m':upper_displacement,
        'triangle_stability':triangle_check,
        'exported_morph_target':{'name':'Smile','attributes':list(primitive['targets'][0]),'skin_bind_count':35,'body_animations_exported':False},
        'basis_vertices_unchanged':True,'body_binding_preserved':any(m.type=='ARMATURE' and m.object==arm for m in body.modifiers),
        'blender_version':bpy.app.version_string,'renderer':'Cycles CPU16, Standard, fixed neutral lights',
        'renders':renders,'limits':['Closed painted mouth only; no oral cavity, speech, jaw rig, or new texture.','Blender neutral render, not Godot shader/actual town evidence.','Only copied LOD0; no production LOD or adapter switch.','Exported prototype omits body animations; unchanged source body-action library remains in the .blend copy.']
    }
    report['provenance'].update({'uv_sha256_before':uv_before,'uv_sha256_after':uv_hash(),'skin_weights_sha256_before':weights_before,'skin_weights_sha256_after':weights_hash(),'packed_images_sha256_before':images_before,'packed_images_sha256_after':packed_images(),'exported_images_sha256':exported_images})
    (OUT/'morph-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('SMILE_MORPH_PROTOTYPE_DONE',json.dumps({'moved':len(moved),'max_mm':max_delta*1000,'seam_delta_error_m':max_group_delta_error}))


if __name__ == "__main__":
    run_prototype()
