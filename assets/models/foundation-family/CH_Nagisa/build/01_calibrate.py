"""Run the installed skill calibration with measured Nagisa reference geometry."""
import sys
import runpy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SKILL=Path('/Users/hayatok/.codex/skills/blender-image-to-3d')
sys.argv=['init_master.py','--','--out',str(ROOT/'CH_Nagisa_master.blend'),'--name','CH_Nagisa_Foundation',
 '--height','1.65','--ref-front',str(ROOT/'ref/front.png'),'--ref-left',str(ROOT/'ref/side.png'),
 '--ref-back',str(ROOT/'ref/back.png'),'--ref-extra',str(ROOT/'ref/turnaround-v1.png'),
 '--subject-frac',str((1004-14)/1004),'--ground-frac',str((1004-989)/1004),
 '--cell','2','--door','.85','2.1','--capsule','.24','1.65',
 '--cam-elev','50','--cam-az','30','--cam-dist','8','--cam-lens','43','--fps','30']
runpy.run_path(str(SKILL/'scripts/init_master.py'),run_name='__main__')

# Skill init_master defines subject_frac as crown position above the bottom;
# align every reference's root axis with its measured, non-centred image column.
import bpy
import json
cal=json.loads((ROOT/'ref/calibration.json').read_text())
for ob in bpy.data.collections['REF'].all_objects:
    if ob.type!='EMPTY' or ob.empty_display_type!='IMAGE' or ob.data is None: continue
    stem=Path(ob.data.filepath).stem
    if stem in cal['views']:
        v=cal['views'][stem]
        ob.empty_image_offset=(-float(v['axis_col'])/ob.data.size[0],-(1004-989)/1004)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'CH_Nagisa_master.blend'))
