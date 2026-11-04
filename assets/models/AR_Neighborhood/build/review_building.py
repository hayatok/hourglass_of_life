"""Fixed-view review of one assembled building, with its full export or source parts."""
from pathlib import Path
import sys, os, importlib.util, bpy
ROOT=Path(__file__).resolve().parents[1]
skill=Path(os.environ.get('BLENDER_ASSET_SKILL',str(Path.home()/'.codex/skills/blender-image-to-3d')))
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
phase=args[0] if args else '02'
kind=args[1] if len(args)>1 else 'Workshop'
suffix={'02':'blockout','03':'forms','05':'delivery'}[phase]
blend=ROOT/('AR_Neighborhood_'+suffix+'.blend')
bpy.ops.wm.open_mainfile(filepath=str(blend))
source=bpy.data.objects['AR_'+kind+('_Export' if phase=='05' else '')]
names=','.join(o.name for o in source.children_recursive if o.type=='MESH')
spec=importlib.util.spec_from_file_location('review_architecture',skill/'scripts/review_render.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
module.main(module.parse(['--blend',str(blend),'--out',str(ROOT/'review'/(phase+'_'+suffix)/kind),
    '--only',names,'--views','front,side,back,threequarter','--ref-cam','30','25','50',
    '--mode','material' if phase=='05' else 'clay','--res','512','--gameplay-px','128',
    '--samples','16','--turntable','12' if phase=='05' else ('8' if phase=='03' else '0')]))
