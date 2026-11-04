"""Representative prop review; perspective concept comparison, not a metric front gate."""
from pathlib import Path
import sys,importlib.util,os,bpy
ROOT=Path(__file__).resolve().parents[1]
skill=Path(os.environ.get('BLENDER_ASSET_SKILL',str(Path.home()/'.codex/skills/blender-image-to-3d')))
phase=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else '02'
suffix='blockout' if phase=='02' else 'forms';blend=ROOT/('PR_LifeFurniture_'+suffix+'.blend')
bpy.ops.wm.open_mainfile(filepath=str(blend))
names=','.join(o.name for o in bpy.data.objects['PR_Bench'].children)
spec=importlib.util.spec_from_file_location('review_prop',skill/'scripts/review_render.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
module.main(module.parse(['--blend',str(blend),'--out',str(ROOT/'review'/(phase+'_'+suffix)),
    '--only',names,'--views','front,side,back,threequarter','--ref-cam','-30','25','50',
    '--mode','clay','--res','640','--gameplay-px','128','--turntable','8' if phase=='03' else '0']))
