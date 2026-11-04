"""Run explicit ordered Blender stages per resident, preserving raw build logs."""
import argparse,os,subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

ROOT=Path(__file__).resolve().parents[1]
BLENDER=os.environ.get('BLENDER_BIN','/Applications/Blender.app/Contents/MacOS/Blender')
STAGES={'02':'02_blockout','03':'03_forms','04':'04_topology','05':'05_materials','06':'06_rig',
        '08':'08_animation','08-check':'08_check_animation','09':'09_export','09-check':'09_check_import'}

def build(name,stages):
    asset=ROOT/'assets/models'/('CH_'+name)
    logs=ROOT/'builds/asset-build'/name;logs.mkdir(parents=True,exist_ok=True)
    for stage in stages:
        log=logs/(STAGES[stage]+'.log')
        with log.open('w') as output:
            subprocess.run([BLENDER,'--background','--python-exit-code','1','--python',str(asset/'build'/(STAGES[stage]+'.py'))],
                cwd=ROOT,stdout=output,stderr=subprocess.STDOUT,check=True)
        print(name,stage,'completed',flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--stages',nargs='+',choices=list(STAGES),required=True)
    parser.add_argument('--names',nargs='+',required=True);args=parser.parse_args()
    with ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(lambda name:build(name,args.stages),args.names):pass
