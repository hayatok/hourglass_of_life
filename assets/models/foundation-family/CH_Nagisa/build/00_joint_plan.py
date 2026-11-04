"""Image-derived provisional 35-bone layout. Pillow only; no model/rig is built.

Front landmarks are measured; joint depth, covered hips/knees and finger axes are
inferred. This plan must be adjusted to the chosen actual mesh before skinning.
"""
from pathlib import Path
import json
import math
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CAL = json.loads((ROOT / 'ref/calibration.json').read_text())
BONES = []


def bone(name, head, tail, parent=None, evidence='inferred'):
    BONES.append({'name': 'DEF-' + name, 'parent': 'DEF-' + parent if parent else None,
                  'head_m': list(head), 'tail_m': list(tail), 'evidence': evidence})


def create_plan():
    BONES.clear()
    bone('root', (0, 0, 0), (0, 0, .15), evidence='authored floor origin')
    bone('pelvis', (0, 0, .945), (0, -.008, 1.045), 'root')
    bone('spine_01', (0, -.008, 1.045), (0, -.015, 1.155), 'pelvis')
    bone('spine_02', (0, -.015, 1.155), (0, -.020, 1.24), 'spine_01')
    bone('chest', (0, -.020, 1.24), (0, -.020, 1.318), 'spine_02')
    bone('neck', (0, -.020, 1.318), (0, -.018, 1.398), 'chest')
    bone('head', (0, -.018, 1.398), (0, -.004, 1.622), 'neck',
         'front chin/crown measured; pivot and depth inferred')
    bone('apron_front', (0, -.115, 1.065), (0, -.166, .641), 'pelvis')
    bone('apron_back', (0, .086, 1.065), (0, .135, .641), 'pelvis')
    for side, sign in [('L', 1), ('R', -1)]:
        bone('clavicle.' + side, (sign * .034, -.020, 1.318),
             (sign * .146, .002, 1.318), 'chest')
        bone('upper_arm.' + side, (sign * .146, .002, 1.318),
             (sign * .251, .014, 1.082), 'clavicle.' + side,
             'front shoulder/elbow measured 2-4px; depth inferred')
        bone('forearm.' + side, (sign * .251, .014, 1.082),
             (sign * .324, .008, .917), 'upper_arm.' + side,
             'front elbow/wrist measured 2-4px; depth inferred')
        bone('hand.' + side, (sign * .324, .008, .917),
             (sign * .354, .005, .847), 'forearm.' + side)
        for finger, (offset, length) in enumerate([
                (-.025, .052), (-.013, .064), (0, .071), (.013, .066), (.024, .053)]):
            z = .873 if finger == 0 else .846
            x = sign * (.355 + offset)
            bone('finger%d.%s' % (finger, side), (x, .003, z),
                 (x + sign * .020, -.004, z - length), 'hand.' + side)
        bone('thigh.' + side, (sign * .090, 0, .945),
             (sign * .108, .028, .485), 'pelvis')
        bone('shin.' + side, (sign * .108, .028, .485),
             (sign * .111, .027, .105), 'thigh.' + side)
        bone('foot.' + side, (sign * .111, .027, .105),
             (sign * .112, -.083, .037), 'shin.' + side)
        bone('toe.' + side, (sign * .112, -.083, .037),
             (sign * .112, -.145, .028), 'foot.' + side)
    assert len(BONES) == 35 and len({b['name'] for b in BONES}) == 35
    names = {b['name'] for b in BONES}
    assert all(b['parent'] is None or b['parent'] in names for b in BONES)
    assert all(math.isfinite(v) for b in BONES for key in ['head_m', 'tail_m'] for v in b[key])


def draw_plan():
    front = Image.open(ROOT / 'ref/front.png').convert('RGB')
    canvas = Image.new('RGB', (1170, 1070), '#f8f4ed')
    canvas.paste(front, (24, 44))
    draw = ImageDraw.Draw(canvas)
    font_file = '/System/Library/Fonts/Helvetica.ttc'
    font = ImageFont.truetype(font_file, 15)
    title = ImageFont.truetype(font_file, 22)
    small = ImageFont.truetype(font_file, 13)
    axis = CAL['views']['front']['axis_col']
    scale = CAL['m_per_px']

    def point(co):
        x, _, z = co
        return 24 + axis + x / scale, 44 + CAL['ground_y'] - z / scale

    for b in BONES:
        if b['name'].startswith(('DEF-finger', 'DEF-apron', 'DEF-toe', 'DEF-root')):
            continue
        measured = 'measured' in b['evidence']
        color = '#146dab' if measured else '#ad6774'
        p, q = point(b['head_m']), point(b['tail_m'])
        draw.line([p, q], fill=color, width=3)
        for x, y in [p, q]:
            draw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=color)
    draw.text((24, 12), 'NAGISA  /  image-derived provisional rig', fill='#303632', font=title)
    lines = [
        'PLAN ONLY - no skinning or retarget validation',
        '',
        'Reference scale: 1.650 m / 975 px',
        'Actual image: 6.50 head heights',
        'Blender Z up / -Y forward / floor root',
        '',
        'Blue: measured shoulder/elbow/wrist projection',
        'Rose: inferred skeleton inside clothes',
        'All depth values are inferred from profile.',
        'Covered hips/knees must be checked on mesh.',
        '',
        'Image values to preserve',
        '  shoulder span        0.293 m',
        '  waist height         1.059 m',
        '  wrist height         0.917 m',
        '  bob width            0.271 m',
        '  apron hem width      0.440 m',
        '  apron hem height     0.636 m',
        '  shoe length          0.250 m',
        '',
        '35 DEF bones / old family names retained',
        '7 centre + 2 apron + 18 arm/hand + 8 leg',
        'Finger 0=thumb, 1=index, 4=little',
        'L is the character left (image right).',
        '',
        'Face shape-key targets',
        '  Blink: eyelid closure, eyeballs retain volume',
        '  Smile / Sad / Tired: restrained changes',
        '  LookLeft / LookRight: pupil gaze only',
        '',
        'Required pose review after skinning',
        '  walking full stride / stairs / 90 degree turn',
        '  sit on actual chair / stand / bed lie',
        '  both-hand carrying / dish grip / high reach',
        '  cook forward reach / deep bend / squat',
        '',
        'No pose acceptance inherited from old model.',
    ]
    y = 70
    for line in lines:
        draw.text((570, y), line, fill='#37443a', font=font if len(line) < 56 else small)
        y += 24
    canvas.save(ROOT / 'review/reference-rig-plan.png')


def main():
    create_plan()
    data = {
        'status': 'provisional_image_derived_plan_not_a_bound_rig',
        'reference': 'ref/turnaround-v1.png', 'height_m': 1.65,
        'axes': {'up': '+Z', 'forward': '-Y', 'left': '+X'},
        'rest_pose': 'front reference relaxed A-pose; side reference uses different arm pose',
        'bone_family': 'existing 35-bone DEF family with image-faithful joint locations',
        'inferred': ['all joint depths', 'covered hip/knee pivots', 'finger flexion axes',
                     'apron deformation and seat-clearance poses'],
        'reference_uncertainty_px': [2, 4], 'bones': BONES,
        'skin_contract': {'max_influences': 4, 'normalised_weights': True,
                          'no_unweighted_vertices': True, 'no_negative_scale': True},
        'face_shape_keys': ['Blink', 'Smile', 'Sad', 'Tired', 'LookLeft', 'LookRight'],
        'sockets': ['hand.L', 'hand.R', 'head', 'chest', 'foot.L', 'foot.R'],
    }
    (ROOT / 'ref/joint-plan.json').write_text(json.dumps(data, indent=2) + '\n')
    draw_plan()
    print('Provisional 35-bone plan and reference overlay written; model not changed.')


if __name__ == '__main__':
    main()
