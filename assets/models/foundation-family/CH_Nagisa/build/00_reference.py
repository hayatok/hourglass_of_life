"""Reproducible reference crops, mattes and pixel measurements; no Blender."""
from pathlib import Path
import json
import math
import statistics
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'ref/turnaround-v1.png'
HEIGHT_M = 1.65
TOP = 14
GROUND = 989
SCALE = HEIGHT_M / (GROUND-TOP)
VIEWS = {
    'front': {'box': [60,0,580,1004], 'axis_source_x':318, 'azimuth':0},
    'side': {'box':[635,0,900,1004], 'axis_source_x':746, 'azimuth':270},
    'back': {'box':[950,0,1490,1004], 'axis_source_x':1217, 'azimuth':180},
}
# Image-space landmarks read from the supplied front/profile; uncertainty 2-4px.
LANDMARKS = {
 'hair_crown':[318,14], 'chin':[318,164], 'hair_lower_edge':[318,174],
 'eye_left':[298,106], 'eye_right':[345,105], 'mouth_center':[320,143],
 'collar_center':[319,193], 'shoulder_left':[232,210], 'shoulder_right':[405,210],
 'elbow_left':[169,350], 'elbow_right':[466,351], 'wrist_left':[128,447], 'wrist_right':[511,447],
 'fingertip_left':[86,523], 'fingertip_right':[551,522],
 'waist_center':[320,363], 'hem_left':[186,605], 'hem_right':[446,605],
 'shoe_sole_left':[251,989], 'shoe_sole_right':[384,989],
}
RATIOS = {
 'head_heights':(GROUND-TOP)/(164-TOP),
 'head_height_over_height':(164-TOP)/(GROUND-TOP),
 'hair_width_over_height':160/(GROUND-TOP),
 'shoulder_joint_width_over_height':173/(GROUND-TOP),
 'waist_width_over_height':140/(GROUND-TOP),
 'apron_hem_width_over_height':260/(GROUND-TOP),
 'apron_hem_height_over_height':(GROUND-613)/(GROUND-TOP),
 'waist_height_over_height':(GROUND-363)/(GROUND-TOP),
 'wrist_height_over_height':(GROUND-447)/(GROUND-TOP),
 'hand_tip_span_over_height':465/(GROUND-TOP),
 'trouser_hem_width_over_height':74/(GROUND-TOP),
 'shoe_front_width_over_height':65/(GROUND-TOP),
 'shoe_side_length_over_height':148/(GROUND-TOP),
 'upper_forearm_width_over_height':43/(GROUND-TOP),
}

def main():
    im=Image.open(SOURCE).convert('RGB')
    if im.size!=(1536,1024): raise ValueError('Reference dimensions changed; recalibrate landmarks')
    report={'source':'ref/turnaround-v1.png','source_size_px':list(im.size),'height_m':HEIGHT_M,
            'hair_crown_y':TOP,'ground_y':GROUND,'m_per_px':SCALE,'landmarks_front':LANDMARKS,
            'ratios':RATIOS,'views':{},
            'measurement_note':'Hand-measured image landmarks, approximate orthographic AI turnaround. 2-4px landmark uncertainty; silhouette mattes use row-local background contrast and erase the printed floor line.',
            'prompt_vs_image':'Prompt intent was 5.3 heads; measured front crown-to-chin is 6.5 heads. Parent approved using actual image proportions without enlarging the head.',
            'inferred':['Crotch/knee centres behind apron and loose trousers','Underlying torso/back anatomy','Side reference neutral root axis at source x746','Exact camera lens: orthographic approximation','Front/back A-pose vs side relaxed-arm pose inconsistency']}
    overlay=im.copy();draw=ImageDraw.Draw(overlay)
    for name,(x,y) in LANDMARKS.items():
        draw.ellipse((x-3,y-3,x+3,y+3),fill=(35,104,200));draw.text((x+5,y-6),name,fill=(20,75,140))
    for name,view in VIEWS.items():
        crop=im.crop(view['box']);w,h=crop.size;px=crop.load()
        mask=Image.new('L',(w,h),0);mp=mask.load()
        for y in range(8,min(988,h)):
            edges=[px[x,y] for x in list(range(8))+list(range(w-8,w))]
            bg=[statistics.median(p[c] for p in edges) for c in range(3)]
            for x in range(w):
                p=px[x,y]
                if sum((p[c]-bg[c])**2 for c in range(3))>30**2: mp[x,y]=255
        mask=mask.filter(ImageFilter.MedianFilter(3))
        exterior=mask.copy();ImageDraw.floodfill(exterior,(0,0),128)
        mask=exterior.point(lambda v:0 if v==128 else 255)
        rgba=crop.convert('RGBA');rgba.putalpha(mask)
        crop.save(ROOT/f'ref/{name}.png');rgba.save(ROOT/f'ref/{name}_clean.png')
        bands=[]
        for j in range(10):
            y=round(TOP+(GROUND-TOP)*(j+.5)/10)
            xs=[x for x in range(w) if mask.getpixel((x,y))>127]
            bands.append({'height_fraction_from_top':(j+.5)/10,'row':y,'width_px':max(xs)-min(xs)+1 if xs else 0})
        view=dict(view);view.update({'axis_col':view['axis_source_x']-view['box'][0],'ground_row':GROUND,'m_per_px':SCALE,
                                    'matte_bbox_px':list(mask.getbbox()),'width_bands':bands,'lens_mm':0,'elevation':0})
        report['views'][name]=view
        x=view['axis_source_x'];draw.line((x,TOP,x,GROUND),fill=(60,140,190),width=1)
    overlay.save(ROOT/'review/reference-measurements.png')
    (ROOT/'ref/calibration.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('Image head count',RATIOS['head_heights'],'metres per pixel',SCALE)

if __name__=='__main__': main()
