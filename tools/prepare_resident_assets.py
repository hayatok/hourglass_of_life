"""Copy original concept references and record reproducible masks/proportion measurements.
Run with the project's asset-tools Python, never through Godot's importer.
"""
from pathlib import Path
import json,shutil
from copy import deepcopy
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets/artwork/v02-jrpg'
PROFILES={
 'Ryo':{'id':'ryo','height':1.76,'head_scale':1.03,'head_x':1.07,'width':1.14,'depth':1.05,
        'arm_length':1.12,'arm_close':.09,'stance':.04,'shoe_stance':.064,'foot_turn':.18,'jaw':.20,'costume':'overshirt',
        'top_color':[.052,.080,.18],'pants_color':[.41,.32,.20],'shoe_color':[.78,.73,.61],
        'hair':{'style':'quiff','color':[.045,.022,.012]},'motion':{'walk_frames':26,'stride':.95},
        'sheet':'07-ryo-turnaround.png','ground':841,'top':17,'axis':[263,224,261]},
 'Rin':{'id':'rin','height':1.22,'head_scale':.98,'head_x':1.03,'width':.86,'depth':.90,
        'arm_length':1.0,'arm_close':.11,'stance':.04,'shoulder_width':.68,'shoulder_z':1.30,
        'foot_turn':.15,'jaw':.12,'costume':'overalls',
        'top_color':[.78,.73,.61],'pants_color':[.65,.34,.035],'shoe_color':[.19,.073,.025],
        'hair':{'style':'shaggy','color':[.12,.046,.018]},'motion':{'walk_frames':20,'stride':1.05},
        'sheet':'08-rin-turnaround.png','ground':858,'top':22,'axis':[261,225,258]}
}
# The mature design is inferred from Rin's original identity and Ryo's adult rig family.
# Preserve an adult head/body ratio instead of scaling a child's head into adulthood.
adult=deepcopy(PROFILES['Ryo']);factor=1.68/1.76
for key in ['height','head_scale','head_x','width','depth']:adult[key]*=factor
adult.update({'id':'rin_adult','jaw':.12,'eye_height':.016,'top_color':[.65,.34,.035],
              'pants_color':[.055,.075,.12],'shoe_color':[.19,.073,.025],
              'hair':{'style':'shaggy','color':[.12,.046,.018]},
              'motion':{'walk_frames':24,'stride':1},'inferred_adult':True})
PROFILES['RinAdult']=adult

def prepare(name,profile):
    asset='CH_'+name;root=ROOT/'assets/models'/asset
    for folder in ['build','ref','review','textures','exports']:(root/folder).mkdir(parents=True,exist_ok=True)
    shutil.copyfile(ART/profile['sheet'],root/'ref/turnaround.png')
    if profile.get('inferred_adult'):
        shutil.copyfile(ART/'08-rin-turnaround.png',root/'ref/child-identity.png')
    sheet=Image.open(ART/profile['sheet']).convert('RGB')
    calibration={'height_m':profile['height'],'meters_per_pixel':profile['height']/(profile['ground']-profile['top']),
                 'top_y':profile['top'],'ground_y':profile['ground'],'views':{}}
    bounds=[(180,0,680,887),(650,0,1150,887),(1080,0,1580,887)]
    for view,box,axis in zip(['front','side','back'],bounds,profile['axis']):
        crop=sheet.crop(box);crop.save(root/f'ref/{view}.png')
        rgb=np.asarray(crop).astype(int)
        mask=(rgb.min(axis=2)<195)|((rgb.max(axis=2)-rgb.min(axis=2))>30)
        mask[profile['ground']:]=False
        # Generated baseline is a drawing aid, not part of the shoes or body silhouette.
        for row in np.where(mask.sum(axis=1)>crop.width*.85)[0]:mask[row]=False
        labels,n=ndimage.label(mask)
        sizes=np.bincount(labels.ravel());sizes[0]=0
        mask=ndimage.binary_fill_holes(labels==sizes.argmax())
        Image.fromarray((mask*255).astype('uint8')).save(root/f'ref/{view}-matte.png')
        ys,xs=np.where(mask);height=int(ys.max()-ys.min()+1)
        widths=[]
        for band in range(10):
            a=int(ys.min()+height*band/10);b=int(ys.min()+height*(band+1)/10)
            _,xx=np.where(mask[a:b]);widths.append(round((int(xx.max()-xx.min()+1))/height,5))
        calibration['views'][view]={'box':list(box),'axis_x':axis,'matte':f'{view}-matte.png',
            'bounds':[int(xs.min()),int(ys.min()),int(xs.max()),int(ys.max())],
            'aspect_w_over_h':round((int(xs.max()-xs.min()+1))/height,5),'band_widths':widths}
        if view=='front':
            runs=[]
            for row in mask:
                xx=np.flatnonzero(row)
                parts=np.split(xx,np.where(np.diff(xx)>1)[0]+1)
                runs.append([[int(part[0]),int(part[-1])] for part in parts if len(part)>1])
            calibration['front_runs']=runs
    (root/'ref/calibration.json').write_text(json.dumps(calibration,indent=2)+'\n')
    profile={**profile,'reference':{'subject_fraction':(profile['ground']-profile['top'])/887,
                                  'ground_fraction':(887-profile['ground'])/887}}
    (root/'profile.json').write_text(json.dumps(profile,indent=2)+'\n')
    for stage,file in [('02','02_blockout'),('03','03_forms'),('04','04_topology'),('05','05_materials'),
                       ('06','06_rig'),('08','08_animation'),('08-check','08_check_animation'),
                       ('09','09_export'),('09-check','09_check_import')]:
        (root/f'build/{file}.py').write_text(
            'from pathlib import Path\nimport sys\nROOT=Path(__file__).resolve().parents[1]\n'
            'sys.path.insert(0,str(ROOT.parent/"common"))\nfrom pipeline import run\n'
            f'run(ROOT,{stage!r})\n')
    brief=f'''ASSET      {asset} — {name}
CATEGORY   character / human biped / original anime JRPG townsfolk
VIEWS      ref/turnaround.png: front, left profile, back. Individual 500x887 crops in ref/. Orthographic-like generated concept; azimuth 0/90/180, elevation 0, lens 0. Front/back A-pose, profile arms lowered. Exact crop boxes/axes/ground in ref/calibration.json.
SCALE      Height {profile['height']}m is an authored fictional dimension. 1 unit = 1m, Z up, -Y front. No individual measurement inferred from population statistics.
PROPORTIONS Ten horizontal silhouette widths per view and width/height ratio measured in ref/calibration.json. Head, body width, depth and arm length are authored in profile.json; compare their resulting silhouette before refining.
PARTS      Body under costume retained in HIGH; neck/head/ears, upper/lower arms, five fingers per hand, full legs; separate shirt, {profile['costume']}, trousers/shorts, socks, shoe soles/uppers, hair cap and grouped locks. Deform with the common humanoid family; surface eye/brow/mouth meshes separate from skin.
SILHOUETTE  {'Swept quiff, open indigo overshirt, long beige trousers, adult shoulders.' if name=='Ryo' else 'Tousled child hair, large head, mustard short overalls, bare lower legs, short child stature.'}
MATERIALS  Skin, grouped brown hair, ivory tee and soles; colors/roughness authored, not sampled physical material. BaseColor sRGB, ORM/Normal Non-Color. No baked directional lighting.
ARTICULATION 35 deformation bones, six face morphs, hand/head/chest/foot sockets. Nine in-place clips with individual stride/cadence. Preserve source rest pose and three LODs.
INFERRED   Real height, hidden anatomy, garment depth and thickness, side arm A-pose, sole underside, face depth, hand contours, material response, all motion. Three generated views contain pose differences and are references rather than engineering blueprints.
TARGET     Godot 4.7 Compatibility, GLB with embedded textures, standard 60000-triangle cap, LOD1/2, elevated three-quarter game camera. Typical height 128px; inspect face and silhouette at that size.
'''
    (root/'asset-brief.md').write_text(brief)
    if profile.get('inferred_adult'):
        with (root/'asset-brief.md').open('a') as f:
            f.write('\nADULT DESIGN INFERRED: ref/turnaround.png and its crops are RYO, used for adult body proportions only. child-identity.png is RIN. Adult hair, face maturation, mustard overshirt, dark full trousers and all unseen aging are authored. No adult Rin orthographic art was supplied. This is not a claim that Ryo\'s identity is Rin\'s reference.\n')
    print(asset,calibration['views']['front'])

if __name__=='__main__':
    for name,profile in PROFILES.items():prepare(name,profile)
