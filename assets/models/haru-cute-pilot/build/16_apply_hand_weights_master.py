"""Apply an isolated weight-only delivery candidate to a copy of the master.

Run in Blender, after 15_repair_hand_weights.py. No mesh, UV, material, rest,
animation, or raw source is rebuilt. The existing master is never overwritten.
The clean GLB reimport is a separate delivery check, not proof of motion quality.
"""
import argparse
import json
from pathlib import Path
import struct
import sys
import bpy
from mathutils.kdtree import KDTree
from mathutils import Matrix


def read_glb(path):
    raw = path.read_bytes()
    offset = 12
    document, binary = None, None
    while offset < len(raw):
        size, kind = struct.unpack_from('<II', raw, offset)
        chunk = raw[offset + 8:offset + 8 + size]
        if kind == 0x4E4F534A:
            document = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + size
    return document, binary


def accessor(document, binary, index):
    entry = document['accessors'][index]
    view = document['bufferViews'][entry['bufferView']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[entry['type']]
    code = {5121: 'B', 5123: 'H', 5125: 'I', 5126: 'f'}[entry['componentType']]
    fmt = '<' + code * width
    stride = view.get('byteStride', struct.calcsize(fmt))
    start = view.get('byteOffset', 0) + entry.get('byteOffset', 0)
    return [struct.unpack_from(fmt, binary, start + stride * index) for index in range(entry['count'])]


def position_key(point):
    return tuple(round(float(value), 6) for value in point)


def hand_weights(path):
    document, binary = read_glb(path)
    names = [document['nodes'][index]['name'] for index in document['skins'][0]['joints']]
    result = {}
    for mesh in document['meshes']:
        for primitive in mesh['primitives']:
            attrs = primitive['attributes']
            if 'JOINTS_0' not in attrs:
                continue
            for pos, joints, weights in zip(accessor(document, binary, attrs['POSITION']), accessor(document, binary, attrs['JOINTS_0']), accessor(document, binary, attrs['WEIGHTS_0'])):
                if not (.70 < pos[1] < .87 and abs(pos[0]) > .28):
                    continue
                # glTF Y-up/+Z-forward to the calibrated Z-up/-Y-forward master.
                key = position_key((pos[0], -pos[2], pos[1]))
                record = {names[joint]: weight for joint, weight in zip(joints, weights) if weight > 0.000001}
                if key in result:
                    if any(abs(record.get(name, 0) - result[key].get(name, 0)) > 0.00001 for name in record.keys() | result[key].keys()):
                        raise RuntimeError('Coincident hand seam weights disagree at ' + str(key))
                result[key] = record
    return result


def delivery_master(candidate):
    # The existing 2026-11-03 Delivery.blend predates later delivered LOD edits.
    # Reconstruct a separate authoring copy from the precise current delivery;
    # never move its vertices to fit the older master or overwrite that master.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    low = bpy.data.collections.new('LOW'); scene.collection.children.link(low)
    rig = bpy.data.collections.new('RIG_DEF'); scene.collection.children.link(rig)
    base_arm = None
    base_actions = set()
    rows = []
    for level in range(3):
        source = candidate / ('CH_Haru.glb' if level == 0 else f'CH_Haru_LOD{level}.glb')
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
        added = set(bpy.data.objects) - before
        arms = [obj for obj in added if obj.type == 'ARMATURE']
        meshes = [obj for obj in added if obj.type == 'MESH' and any(modifier.type == 'ARMATURE' for modifier in obj.modifiers)]
        if len(arms) != 1 or len(meshes) != 1:
            raise RuntimeError('Expected one delivered armature and body per LOD: ' + repr([(obj.name,obj.type) for obj in added]))
        arm, mesh = arms[0], meshes[0]
        if base_arm is None:
            base_arm = arm; arm.name = 'CH_Haru_Rig'
            base_actions = set(bpy.data.actions)
            for collection in list(arm.users_collection): collection.objects.unlink(arm)
            rig.objects.link(arm)
        else:
            if [bone.name for bone in arm.data.bones] != [bone.name for bone in base_arm.data.bones]:
                raise RuntimeError('LOD bone families disagree')
            world = mesh.matrix_world.copy()
            mesh.parent = base_arm; mesh.matrix_world = world
            for modifier in mesh.modifiers:
                if modifier.type == 'ARMATURE': modifier.object = base_arm
            bpy.data.objects.remove(arm, do_unlink=True)
            for action in list(bpy.data.actions):
                if action not in base_actions: bpy.data.actions.remove(action)
        for collection in list(mesh.users_collection): collection.objects.unlink(mesh)
        low.objects.link(mesh)
        mesh.name = f'CH_Haru_Body_LOD{level}'
        mesh.hide_render = level != 0; mesh.hide_set(level != 0)
        rows.append({'lod': level, 'method': 'Clean current-delivery import; compatible LOD meshes share the first imported rig', 'vertices': len(mesh.data.vertices)})
    if base_arm.animation_data:
        base_arm.animation_data.action = None
        for track in base_arm.animation_data.nla_tracks: track.mute = True
    for action in base_actions: action.use_fake_user = True
    for bone in base_arm.pose.bones: bone.matrix_basis = Matrix.Identity(4)
    scene.frame_set(0)
    scene['target_height_m'] = 1.71
    scene['authoring_up'] = 'Z'; scene['authoring_forward'] = '-Y'
    scene['hand_weight_source'] = str(candidate)
    scene['master_scope'] = 'Current delivery reimport, because the older Delivery.blend has different LOD vertex positions. Original authoring master retained.'
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--master', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rebuild-from-delivery', action='store_true', help='Create a distinct current-delivery authoring copy when the older master is stale')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.output.resolve() == args.master.resolve():
        raise RuntimeError('Preserve the source master; choose a distinct output')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report = {'scope': 'Hand-weight authoring copy plus clean GLB reimport. Actual skinned motion is reviewed separately in Godot.', 'master': str(args.master), 'output': str(args.output), 'applied': [], 'roundtrip': []}
    if args.rebuild_from_delivery:
        report['applied'] = delivery_master(args.candidate)
        report['master_method'] = 'Explicit clean current-delivery reconstruction; older master retained unchanged'
    else:
        bpy.ops.wm.open_mainfile(filepath=str(args.master.resolve()))
    for level in ([] if args.rebuild_from_delivery else range(3)):
        filename = 'CH_Haru.glb' if level == 0 else f'CH_Haru_LOD{level}.glb'
        source = args.candidate / filename
        lookup = hand_weights(source)
        keys = list(lookup)
        tree = KDTree(len(keys))
        for index, key in enumerate(keys):
            tree.insert(key, index)
        tree.balance()
        obj = bpy.data.objects.get(f'CH_Haru_Body_LOD{level}')
        if obj is None:
            raise RuntimeError('Missing master LOD ' + str(level))
        matched, changed = 0, 0
        for vertex in obj.data.vertices:
            world = obj.matrix_world @ vertex.co
            if not (.70 < world.z < .87 and abs(world.x) > .28):
                continue
            weights = lookup.get(position_key(world))
            if weights is None:
                _nearest, index, distance = tree.find(world)
                if distance > 0.000001:
                    raise RuntimeError('Master hand has no delivery-position match within 1um: ' + str(tuple(world)) + ' nearest_m=' + str(distance))
                weights = lookup[keys[index]]
            before = {obj.vertex_groups[group.group].name: group.weight for group in vertex.groups}
            matched += 1
            if any(abs(before.get(name, 0) - weights.get(name, 0)) > 0.00001 for name in before.keys() | weights.keys()):
                changed += 1
            for group in list(vertex.groups):
                obj.vertex_groups[group.group].remove([vertex.index])
            for name, weight in weights.items():
                group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                group.add([vertex.index], weight, 'REPLACE')
        if matched == 0:
            raise RuntimeError('No hand positions were matched')
        report['applied'].append({'lod': level, 'matched_master_vertices': matched, 'changed_master_vertices': changed})
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
    for level in range(3):
        source = args.candidate / ('CH_Haru.glb' if level == 0 else f'CH_Haru_LOD{level}.glb')
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
        armatures = [obj for obj in bpy.data.objects if obj.type == 'ARMATURE']
        meshes = [obj for obj in bpy.data.objects if obj.type == 'MESH' and any(modifier.type == 'ARMATURE' for modifier in obj.modifiers)]
        row = {'lod': level, 'armatures': len(armatures), 'bones': len(armatures[0].data.bones) if armatures else 0, 'meshes': len(meshes), 'actions': [action.name for action in bpy.data.actions], 'unweighted_vertices': sum(not vertex.groups for obj in meshes for vertex in obj.data.vertices), 'maximum_influences': max((len(vertex.groups) for obj in meshes for vertex in obj.data.vertices), default=0), 'preserve_volume': any(modifier.use_deform_preserve_volume for obj in meshes for modifier in obj.modifiers if modifier.type == 'ARMATURE')}
        if row['bones'] != 35 or row['unweighted_vertices'] or row['maximum_influences'] > 4 or row['preserve_volume']:
            raise RuntimeError('Clean reimport failed: ' + str(row))
        report['roundtrip'].append(row)
    (args.output.parent / 'master-and-roundtrip.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Hand master and clean reimport: PASS')


main()
