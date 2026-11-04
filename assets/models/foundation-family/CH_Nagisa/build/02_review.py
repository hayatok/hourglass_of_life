"""Sequential low-cost blockout gates; only run while owning the heavy slot."""
from pathlib import Path
import os,json,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
SKILL=Path('/Users/hayatok/.codex/skills/blender-image-to-3d')
BLENDER=os.environ.get('BLENDER_BIN','/Applications/Blender.app/Contents/MacOS/Blender')
OUT=ROOT/'review/02_blockout'

def call(script,args):
    subprocess.run([BLENDER,'--background','--factory-startup','--python',str(SKILL/'scripts'/script),'--',*map(str,args)],check=True,stdout=subprocess.DEVNULL)


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    call('review_render.py',['--blend',ROOT/'CH_Nagisa_master.blend','--out',OUT,'--collections','LOW','--views','front,left,back,threequarter','--ref-cam',30,50,43,'--mode','clay','--res',512,'--gameplay-px',128,'--engine','workbench'])
    cal=json.loads((ROOT/'ref/calibration.json').read_text())
    results={}
    for name in ['front','side','back']:
        v=cal['views'][name]
        call('world_gate.py',['--blend',ROOT/'CH_Nagisa_master.blend','--out',OUT/'world','--matte',ROOT/f'ref/{name}_clean.png','--az',v['azimuth'],'--m-per-px',v['m_per_px'],'--axis-col',v['axis_col'],'--ground-row',v['ground_row'],'--collections','LOW','--name',name,'--scale',1])
        fixed='left' if name=='side' else name
        subprocess.run([sys.executable,str(SKILL/'scripts/compose_review.py'),'--ref',str(ROOT/f'ref/{name}_clean.png'),'--render',str(OUT/f'clay_{fixed}.png'),'--out',str(OUT/f'compare_{name}.png'),'--measure','--gameplay-px','128'],check=True,stdout=subprocess.DEVNULL)
        result=json.loads((OUT/'world'/f'gate_{name}.json').read_text());results[name]=result
        print(name,json.dumps(result,ensure_ascii=False))
    (OUT/'gate_summary.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':main()
