"""Render reproducible per-resident stage reviews; numeric deviations never imply acceptance."""
import argparse,json,os,subprocess,sys
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

ROOT=Path(__file__).resolve().parents[1]
SKILL=Path(os.environ.get('BLENDER_ASSET_SKILL',str(Path.home()/'.codex/skills/blender-image-to-3d')))
BLENDER=os.environ.get('BLENDER_BIN','/Applications/Blender.app/Contents/MacOS/Blender')

def review(name,phase):
    asset=ROOT/'assets/models'/('CH_'+name)
    stage={'02':'blockout','03':'forms','05':'materials','04':'topology'}[phase]
    out=asset/'review'/(phase+'_'+stage);out.mkdir(parents=True,exist_ok=True)
    blend=asset/(asset.name+'_'+stage+'.blend')
    def blender(script,args,label):
        with (out/(label+'.log')).open('w') as log:
            subprocess.run([BLENDER,'--background','--python-exit-code','1','--python',str(SKILL/'scripts'/script),'--',*map(str,args)],
                           cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    mode='material' if phase=='05' else 'wire' if phase=='04' else 'clay'
    blender('review_render.py',['--blend',blend,'--out',out,'--collections','LOW','--views','front,side,back,threequarter',
         '--ref-cam','0','0','0','--mode',mode,'--res','640','--gameplay-px','128',
         '--turntable','8' if phase=='03' else '12' if phase=='05' else '0'],mode)
    if phase in ['02','03']:
        calibration=json.loads((asset/'ref/calibration.json').read_text())
        blender('world_gate.py',['--blend',blend,'--out',out/'world','--matte',asset/'ref/front-matte.png','--az','0',
            '--m-per-px',calibration['meters_per_pixel'],'--axis-col',calibration['views']['front']['axis_x'],
            '--ground-row',calibration['ground_y'],'--name','front','--scale','2'],'world-front')
        subprocess.run([sys.executable,str(SKILL/'scripts/compose_review.py'),'--ref',str(asset/'ref/front.png'),
            '--render',str(out/'clay_front.png'),'--out',str(out/'compare_front.png'),'--measure','--gameplay-px','128'],
            check=True,stdout=subprocess.DEVNULL)
        gate=json.loads((out/'world/gate_front.json').read_text())
        print(name,phase,'world front IoU',gate['iou'],flush=True)
    else:print(name,phase,'rendered',flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--phase',choices=['02','03','04','05'],required=True)
    parser.add_argument('names',nargs='+');args=parser.parse_args()
    with ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(lambda name:review(name,args.phase),args.names):pass
