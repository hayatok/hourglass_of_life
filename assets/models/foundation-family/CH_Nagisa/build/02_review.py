"""Sequential low-cost blockout gates; only run while owning the heavy slot."""
from pathlib import Path
import os,json,subprocess,sys
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
SKILL=Path('/Users/hayatok/.codex/skills/blender-image-to-3d')
BLENDER=os.environ.get('BLENDER_BIN','/Applications/Blender.app/Contents/MacOS/Blender')
OUT=ROOT/'review/02_blockout'

def call(script,args):
    subprocess.run([BLENDER,'--background','--factory-startup','--python',str(SKILL/'scripts'/script),'--',*map(str,args)],check=True,stdout=subprocess.DEVNULL)


def gameplay_strip():
    # review_render's gameplay-px is the canvas size, not the measured subject
    # height. Keep its original output, and add exact-height cutouts from the
    # actual 512px clay frame; do not count this resampling as a new render.
    source=Image.open(OUT/'clay_ref.png').convert('RGBA')
    bounds=source.getchannel('A').getbbox()
    if not bounds:
        raise ValueError('No rendered subject in the gameplay reference frame')
    subject=source.crop(bounds)
    canvas=Image.new('RGB',(360,190),(40,40,40))
    draw=ImageDraw.Draw(canvas)
    samples=[]
    for x,height in [(48,64),(180,128)]:
        scaled=subject.resize((round(subject.width*height/subject.height),height),Image.Resampling.LANCZOS)
        canvas.paste(scaled,(x,160-height),scaled)
        draw.text((x,168),f'{height}px subject',(235,235,235))
        samples.append({'subject_height_px':height,'canvas_position':[x,160-height],
                        'source':'clay_ref.png','source_alpha_bbox':list(bounds)})
    canvas.save(OUT/'gameplay_subject_strip.png')
    (OUT/'gameplay_subject_strip.json').write_text(json.dumps({
        'rendered':False,'method':'alpha crop and resample of actual clay_ref render',
        'camera':{'azimuth':30,'elevation':50,'fov_degrees':43},'samples':samples,
        'remaining':'blockout only; face/hair/clothing forms are not accepted'
    },indent=2)+'\n')


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
    gameplay_strip()

if __name__=='__main__':main()
