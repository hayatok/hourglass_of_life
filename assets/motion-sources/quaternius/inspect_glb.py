"""Inspect source GLB data using only Python's standard library; no engine import."""
from pathlib import Path
import json
import math
import struct
import statistics
import zipfile

HERE = Path(__file__).resolve().parent
FORMATS = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def load_glb(path):
    blob = path.read_bytes()
    magic, version, total = struct.unpack_from('<4sII', blob)
    if magic != b'glTF' or version != 2 or total != len(blob):
        raise ValueError('Not a complete glTF 2 GLB')
    chunks = {}
    cursor = 12
    while cursor < len(blob):
        size, kind = struct.unpack_from('<II', blob, cursor)
        cursor += 8
        chunks[kind] = blob[cursor:cursor+size]
        cursor += size
    return json.loads(chunks[0x4E4F534A]), chunks.get(0x004E4942, b'')


def accessor(doc, binary, index):
    item = doc['accessors'][index]
    if 'sparse' in item:
        raise ValueError('Sparse accessors are not implemented by this inspector')
    view = doc['bufferViews'][item['bufferView']]
    fmt, width = FORMATS[item['componentType']]
    count = WIDTHS[item['type']]
    stride = view.get('byteStride', width * count)
    offset = view.get('byteOffset', 0) + item.get('byteOffset', 0)
    return [struct.unpack_from('<' + fmt * count, binary, offset + i * stride) for i in range(item['count'])]


def multiply(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def local_matrix(node):
    if 'matrix' in node:
        return [[node['matrix'][c*4+r] for c in range(4)] for r in range(4)]
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    scale = node.get('scale', [1, 1, 1])
    rotation = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]
    translation = node.get('translation', [0, 0, 0])
    return [[rotation[r][c] * scale[c] for c in range(3)] + [translation[r]] for r in range(3)] + [[0, 0, 0, 1]]


def world_matrices(nodes):
    parents = {child: i for i, node in enumerate(nodes) for child in node.get('children', [])}
    cache = {}
    def world(i):
        if i not in cache:
            local = local_matrix(nodes[i])
            cache[i] = multiply(world(parents[i]), local) if i in parents else local
        return cache[i]
    return [world(i) for i in range(len(nodes))], parents


def position(matrix):
    return [matrix[r][3] for r in range(3)]


def pose_summary(nodes):
    worlds, parents = world_matrices(nodes)
    indices = {node['name']: i for i, node in enumerate(nodes)}
    result = {'world_joint_positions_m': {name: position(worlds[indices[name]]) for name in [
        'root', 'pelvis', 'Head', 'upperarm_l', 'lowerarm_l', 'hand_l',
        'upperarm_r', 'lowerarm_r', 'hand_r', 'thigh_l', 'calf_l', 'foot_l', 'ball_l',
        'thigh_r', 'calf_r', 'foot_r', 'ball_r'] if name in indices},
        'coordinate_note': 'glTF coordinates: metres, right-handed, Y up. World positions are calculated from encoded node TRS; they are not rendered measurements.'}
    result['upperarm_angle_from_horizontal_degrees'] = {}
    for side in ['l', 'r']:
        a = position(worlds[indices['upperarm_'+side]])
        b = position(worlds[indices['lowerarm_'+side]])
        delta = [b[i]-a[i] for i in range(3)]
        result['upperarm_angle_from_horizontal_degrees'][side] = math.degrees(math.atan2(abs(delta[1]), math.hypot(delta[0], delta[2])))
    return result


def inspect(path):
    doc, binary = load_glb(path)
    nodes = doc['nodes']
    names = {i: node['name'] for i, node in enumerate(nodes)}
    worlds, parents = world_matrices(nodes)
    skins = []
    for skin in doc.get('skins', []):
        bind = accessor(doc, binary, skin['inverseBindMatrices'])
        skins.append({'name': skin.get('name'), 'joint_count': len(skin['joints']),
            'joints': [{'node_index': i, 'name': names[i], 'parent': names.get(parents.get(i)),
                        'local_translation': nodes[i].get('translation', [0, 0, 0]),
                        'local_rotation_xyzw': nodes[i].get('rotation', [0, 0, 0, 1]),
                        'local_scale': nodes[i].get('scale', [1, 1, 1]),
                        'world_bind_position_m': position(worlds[i]),
                        'inverse_bind_matrix_column_major': list(bind[j])}
                       for j, i in enumerate(skin['joints'])]})
    clips = []
    tpose = None
    for animation in doc.get('animations', []):
        times = sorted({float(t[0]) for sampler in animation['samplers'] for t in accessor(doc, binary, sampler['input'])})
        intervals = [b-a for a, b in zip(times, times[1:]) if b-a > 1e-6]
        tracks = []
        pose_nodes = json.loads(json.dumps(nodes)) if animation['name'] == 'A_TPose' else None
        for channel in animation['channels']:
            sampler = animation['samplers'][channel['sampler']]
            values = accessor(doc, binary, sampler['output'])
            target = channel['target']
            if pose_nodes is not None and target['path'] in ['translation', 'rotation', 'scale']:
                pose_nodes[target['node']][target['path']] = list(values[0])
            if names[target['node']] not in ['root', 'pelvis']:
                continue
            entry = {'node': names[target['node']], 'path': target['path'], 'samples': len(values),
                     'first': list(values[0]), 'last': list(values[-1]), 'interpolation': sampler.get('interpolation', 'LINEAR')}
            if target['path'] == 'translation':
                entry['end_minus_start_m'] = [values[-1][k]-values[0][k] for k in range(3)]
                entry['span_m'] = [max(v[k] for v in values)-min(v[k] for v in values) for k in range(3)]
            tracks.append(entry)
        if pose_nodes is not None:
            tpose = pose_summary(pose_nodes)
        clips.append({'name': animation['name'], 'duration_seconds': times[-1]-times[0],
                      'unique_sample_times': len(times), 'median_sample_rate_hz': 1/statistics.median(intervals) if intervals else None,
                      'channels': len(animation['channels']), 'root_and_pelvis_tracks': tracks})
    clip_names = [clip['name'] for clip in clips]
    wanted = {
        'walk': ['Walk_Loop', 'Walk_Formal_Loop'], 'jog': ['Jog_Fwd_Loop'], 'sprint': ['Sprint_Loop'],
        'sit_down': ['Sitting_Enter'], 'stand_up': ['Sitting_Exit'], 'sitting_idle': ['Sitting_Idle_Loop'],
        'standing_idle': ['Idle_Loop'], 'walk_start': [], 'walk_stop': [], 'turn_90': [], 'turn_180': [], 'eight_direction_walk': []}
    result = {'file': str(path.relative_to(HERE)), 'bytes': path.stat().st_size, 'asset': doc['asset'],
              'node_count': len(nodes), 'skin_count': len(skins), 'skins': skins,
              'static_rest_pose': pose_summary(nodes), 'A_TPose_first_sample': tpose,
              'animation_count': len(clips), 'clip_names': clip_names, 'clips': clips,
              'requested_coverage_by_exact_clip_name': wanted,
              'coverage_note': 'Empty categories mean no dedicated clip is named for that action in the free Standard archive. No segmentation or semantic visual assessment was performed.'}
    return result


def main():
    files = sorted((HERE/'Unreal-Godot').glob('*.glb'))
    inventories = [inspect(path) for path in files]
    archive = HERE/'Universal Animation Library[Standard].zip'
    with zipfile.ZipFile(archive) as z:
        entries = [{'path': item.filename, 'bytes': item.file_size, 'compressed_bytes': item.compress_size} for item in z.infolist()]
    result = {'scope': 'Source-file inspection only: ZIP plus glTF 2 JSON and binary accessor decoding. No engine import, rendered quality, contact/foot-slip evaluation or retarget success claim.',
              'edition': 'Standard (free)', 'license': 'CC0-1.0', 'archive_entries': entries, 'files': inventories,
              'same_clip_names_in_both_files': len(inventories) == 2 and inventories[0]['clip_names'] == inventories[1]['clip_names'],
              'root_motion_note': 'Archive README states that _RM bakes root motion and the other file disables root motion. Root translation ranges/end deltas are recorded independently for each clip.'}
    (HERE/'inventory.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    for item in inventories:
        print(item['file'], 'clips', item['animation_count'], 'joints', item['skins'][0]['joint_count'])
        print('static upperarm angles', item['static_rest_pose']['upperarm_angle_from_horizontal_degrees'])
        print('A_TPose angles', item['A_TPose_first_sample']['upperarm_angle_from_horizontal_degrees'])
        for clip in item['clips']:
            if clip['name'] in ['Walk_Loop','Walk_Formal_Loop','Jog_Fwd_Loop','Sprint_Loop','Sitting_Enter','Sitting_Exit']:
                root = next(t for t in clip['root_and_pelvis_tracks'] if t['node'] == 'root' and t['path'] == 'translation')
                print(clip['name'], round(clip['duration_seconds'], 6), 'seconds, root delta', [round(v,6) for v in root['end_minus_start_m']], 'span', [round(v,6) for v in root['span_m']])


if __name__ == '__main__':
    main()
