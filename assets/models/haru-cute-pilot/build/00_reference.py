"""Measure the selected front concept for raw-model review; no mesh edits."""
from pathlib import Path
from PIL import Image, ImageFilter
from collections import deque
import json,statistics
ROOT = Path(__file__).resolve().parents[1]
image = Image.open(ROOT/'ref/front.png').convert('RGBA')
w,h = image.size
# The supplied front concept shows the sole contact near y=1499/1536.
# It has no physical ruler: 1.77 m and an orthographic camera are review inferences.
ground_row = round(h*1499/1536)
pixels=image.load(); mask=Image.new('L',(w,h)); out=mask.load()
for y in range(ground_row+1):
    left=pixels[3,y][:3];right=pixels[w-4,y][:3]
    for x in range(w):
        t=x/(w-1);background=[left[i]*(1-t)+right[i]*t for i in range(3)]
        if max(abs(pixels[x,y][i]-background[i]) for i in range(3))>30:out[x,y]=255
# Fill enclosed holes, retaining the real openings between arms, legs and fingers.
seen=bytearray(w*h);q=deque()
for x in range(w):
    for y in [0,h-1]:
        if not out[x,y]:seen[y*w+x]=1;q.append((x,y))
for y in range(h):
    for x in [0,w-1]:
        if not out[x,y] and not seen[y*w+x]:seen[y*w+x]=1;q.append((x,y))
while q:
    x,y=q.popleft()
    for a,b in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
        if 0<=a<w and 0<=b<h and not seen[b*w+a] and not out[a,b]:seen[b*w+a]=1;q.append((a,b))
for y in range(h):
    for x in range(w):
        if not seen[y*w+x]:out[x,y]=255
matte=image.copy();matte.putalpha(mask);matte.save(ROOT/'ref/front-matte.png')
box=mask.getbbox();height=box[3]-box[1];widths=[]
for fraction in [.05,.15,.25,.35,.45,.55,.65,.75,.85,.95]:
    row=min(h-1,round(box[1]+height*fraction));xs=[x for x in range(w) if out[x,row]]
    widths.append({'height_fraction_from_top':fraction,'row':row,'width_pixels':max(xs)-min(xs)+1 if xs else 0,'width_over_total_height':(max(xs)-min(xs)+1)/height if xs else 0})
axis_samples=[]
for row in [237,270,600]:
    xs=[x for x in range(w) if out[x,row]];runs=[]
    for x in xs:
        if not runs or x>runs[-1][1]+1:runs.append([x,x])
        else:runs[-1][1]=x
    a,b=next((a,b) for a,b in runs if a<=w/2<=b)
    axis_samples.append({'row':row,'interval':[a,b],'midpoint':(a+b)/2})
axis_column=statistics.median(s['midpoint'] for s in axis_samples)
record={'image_size':[w,h],'foreground_bbox':box,'axis_column':axis_column,'axis_samples':axis_samples,'ground_row':ground_row,'subject_fraction':height/h,'ground_fraction':(h-ground_row)/h,'review_height_m':1.77,'meters_per_pixel':1.77/height,'width_profile':widths,'inferred':['physical scale 1.77 m from the existing Haru presentation, not image evidence','front camera approximated as orthographic','back, side depth, hidden costume surfaces and exact joints not shown'],'matte_method':'row-edge background difference >30/255, outside flood fill, sole shadow cut at manual ground row; approximate concept matte, inspect before interpreting IoU'}
(ROOT/'ref/calibration.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2))
