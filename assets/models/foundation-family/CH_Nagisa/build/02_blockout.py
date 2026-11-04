"""Measured primary masses for the new mother model; no old mesh is reused.
Metres, Z up, -Y forward. See asset-brief.md/ref/calibration.json for dimensions.
Anatomy below clothes, cross-section curvature and thickness are inferred.
"""
from pathlib import Path
import sys
import math
import json
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
import mesh_helpers as H
H.OWNER_TAG='phase:02_blockout_foundation'
ROOT=Path(__file__).resolve().parents[1]
PREFIX='CH_Nagisa_Foundation_'
PARTS=[]


def mat(name,color,roughness=.85):
    return H.material(PREFIX+name,(*color,1),roughness=roughness)


def finish(ob,material,region,collection='LOW'):
    H.assign(ob,material);ob['region']=region;PARTS.append(ob)
    if ob.type=='MESH':
        for face in ob.data.polygons: face.use_smooth=True
    return ob


def hull(name,sections,material,region,n=32,collection='LOW'):
    # z, x radius, front depth, back depth, centre x, centre y.
    rings=[]
    for z,rx,front,back,cx,cy in sections:
        rings.append([(cx+rx*math.cos(a*math.tau/n),cy+(front if math.sin(a*math.tau/n)<0 else back)*math.sin(a*math.tau/n),z) for a in range(n)])
    return finish(H.loft(PREFIX+name+'_LOD0',rings,collection=collection),material,region)


def oval(name,loc,size,material,region,collection='LOW'):
    return finish(H.sphere(PREFIX+name+'_LOD0',1,collection=collection,location=loc,scale=size,u=32,v=20),material,region)


def tube(name,points,radii,material,region,n=20):
    rings=[]
    for i,point in enumerate(points):
        p=Vector(point);t=(Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])).normalized()
        u=t.cross(Vector((0,1,0))).normalized();v=t.cross(u).normalized()
        rx,ry=radii[i] if isinstance(radii[i],tuple) else (radii[i],radii[i])
        rings.append([p+rx*math.cos(a*math.tau/n)*u+ry*math.sin(a*math.tau/n)*v for a in range(n)])
    return finish(H.loft(PREFIX+name+'_LOD0',rings),material,region)


def apron_panel(name,angles,material):
    # Measured hem width .440m/z .636m; waist width .237m/z1.059m.
    # Profile depth .28m and front/back material clearance are inferred from side.
    stations=[(.636,.220,.145),(.65,.220,.145),(.76,.206,.136),(.88,.180,.123),
              (1.01,.139,.106),(1.060,.119,.096),(1.066,.118,.096)]
    rings=[]
    for z,rx,ry in stations:
        rings.append([(rx*math.cos(a),-.005+ry*(1.16 if math.sin(a)<0 else 1.0)*math.sin(a),z) for a in angles])
    ob=H.loft(PREFIX+name+'_LOD0',rings,close_sections=False,cap_ends=False)
    H.solidify(ob,.003,offset=0)
    return finish(ob,material,'apron')


def build():
    H.open_master(str(ROOT/'CH_Nagisa_master.blend'));H.clear_owned()
    PARTS.clear()
    skin=mat('Skin',(.84,.61,.44),.78);hair=mat('Chestnut',(.18,.075,.035),.60)
    blouse=mat('SageBlouse',(.39,.43,.25),.91);apron=mat('TerracottaApron',(.56,.24,.16),.92)
    pants=mat('IvoryTrousers',(.82,.75,.60),.91);leather=mat('BrownLeather',(.22,.105,.052),.62)
    sole=mat('Sole',(.10,.065,.042),.82);eye=mat('EyeBlockout',(.96,.94,.86),.5)
    # Complete covered anatomy stays in HIGH; export garments are independent.
    body=hull('UnderlyingTorso',[(.89,.145,.095,.09,0,0),(1.01,.125,.09,.085,0,0),
        (1.07,.108,.08,.075,0,0),(1.19,.135,.105,.095,0,0),(1.30,.153,.075,.075,0,0),(1.34,.065,.045,.045,0,0)],skin,'body',collection='HIGH')
    body.hide_render=True;body.hide_set(True)
    hip=oval('UnderlyingPelvis',(0,0,.96),(.171,.105,.14),skin,'pelvis',collection='HIGH');hip.hide_render=True;hip.hide_set(True)
    # Full loose adult trouser columns follow front widths at y650/750/850/945.
    for side,sign in [('L',1),('R',-1)]:
        hull('Trousers.'+side,[(.07,.060,.069,.067,sign*.111,.0),(.10,.063,.073,.073,sign*.111,.0),
            (.17,.067,.074,.075,sign*.110,.026),(.30,.073,.074,.078,sign*.108,.032),
            (.44,.072,.080,.078,sign*.108,.022),(.58,.077,.090,.083,sign*.103,-.006),
            (.74,.082,.086,.086,sign*.096,.008),(.91,.088,.091,.086,sign*.090,0),
            (1.055,.088,.085,.079,sign*.086,0)],pants,'leg.'+side,n=32)
        hull('TrouserCuff.'+side,[(.068,.061,.071,.069,sign*.111,0),(.086,.064,.074,.071,sign*.111,0),(.107,.064,.074,.072,sign*.111,0)],pants,'shin.'+side)
        # Shoes .110m wide/.250m long measured, supportive heel/sole 35mm inferred.
        hull('Sole.'+side,[(.003,.053,.174,.069,sign*.112,0),(.014,.056,.179,.071,sign*.112,0),(.033,.055,.174,.069,sign*.112,0)],sole,'foot.'+side)
        hull('ShoeUpper.'+side,[(.030,.055,.173,.067,sign*.112,0),(.047,.055,.169,.067,sign*.112,0),
            (.067,.051,.151,.060,sign*.112,.003),(.090,.039,.095,.049,sign*.112,.009),(.108,.030,.046,.039,sign*.112,.018)],leather,'foot.'+side)
    # Rounded blouse, healthy waist and visible shoulder/cuff layers.
    hull('Blouse',[(1.037,.116,.093,.086,0,0),(1.070,.120,.097,.089,0,0),
        (1.13,.132,.116,.095,0,-.002),(1.22,.149,.130,.099,0,-.002),
        (1.292,.160,.081,.078,0,0),(1.329,.117,.056,.060,0,0),(1.355,.044,.038,.038,0,0)],blouse,'torso',n=40)
    hull('Neck',[(1.316,.036,.035,.034,0,.002),(1.35,.036,.035,.034,0,.002),
                  (1.405,.036,.035,.034,0,.003),(1.43,.041,.040,.036,0,.003)],skin,'neck')
    for side,sign in [('L',1),('R',-1)]:
        shoulder=(sign*.146,.0,1.318);cuff=(sign*.196,-.003,1.169)
        elbow=(sign*.251,-.006,1.083);wrist=(sign*.324,-.012,.917)
        tube('Sleeve.'+side,[shoulder,(sign*.163,0,1.275),(sign*.182,-.002,1.216),cuff],
             [(.066,.064),(.063,.061),(.058,.056),(.052,.051)],blouse,'upper_arm.'+side)
        tube('RolledCuff.'+side,[(sign*.188,-.002,1.199),(sign*.201,-.003,1.165)],[(.057,.055),(.054,.052)],blouse,'upper_arm.'+side)
        tube('Arm.'+side,[(sign*.199,-.003,1.168),elbow,(sign*.286,-.01,1.009),wrist],
             [(.040,.041),(.039,.038),(.032,.032),(.024,.022)],skin,'arm.'+side)
        tube('Palm.'+side,[wrist,(sign*.344,-.015,.872),(sign*.357,-.015,.845)],
             [(.023,.019),(.029,.022),(.025,.018)],skin,'hand.'+side,n=20)
        # Separate rough fingers from measured .128m wrist→tip vertical extent.
        for finger,(offset,length) in enumerate([(-.025,.052),(-.013,.064),(0,.071),(.013,.066),(.024,.053)]):
            z=.873 if finger==0 else .846
            x=sign*(.355+offset)
            tube('Finger%d.%s'%(finger,side),[(x,-.017,z),(x+sign*.015,-.022,z-length*.5),(x+sign*.020,-.024,z-length)],
                 [.0095,.009,.0065],skin,'finger%d.%s'%(finger,side),n=10)
    # Measured adult cheek/jaw volume, not a single scaled UV sphere.
    hull('Head',[(1.396,.018,.032,.032,0,-.030),(1.407,.050,.048,.048,0,-.014),
        (1.429,.078,.064,.063,0,-.006),(1.46,.097,.078,.080,0,.001),
        (1.494,.103,.085,.089,0,.004),(1.53,.101,.080,.094,0,.006),
        (1.567,.091,.073,.090,0,.012),(1.60,.073,.058,.075,0,.014),
        (1.625,.038,.035,.040,0,.016),(1.632,.006,.009,.010,0,.016)],skin,'head',n=48)
    oval('Nose',(0,-.087,1.478),(.0125,.027,.018),skin,'head')
    for side,sign in [('L',1),('R',-1)]:
        oval('Ear.'+side,(sign*.101,.004,1.478),(.018,.017,.032),skin,'head')
        oval('EyeMass.'+side,(sign*.040,-.078,1.496),(.021,.014,.018),eye,'head')
    # Bob lower envelope: open across the face, continuous back and side volume.
    angles=[-.25+(math.pi+.5)*i/40 for i in range(41)]
    rings=[]
    for z,rx,ry,cy in [(1.381,.104,.102,.030),(1.402,.122,.122,.023),(1.445,.136,.140,.015),
                        (1.50,.137,.145,.010),(1.55,.122,.134,.010),(1.59,.096,.111,.012)]:
        rings.append([(rx*math.cos(a),cy+ry*math.sin(a),z) for a in angles])
    ob=H.loft(PREFIX+'BobBackSides_LOD0',rings,close_sections=False,cap_ends=False)
    H.solidify(ob,.006,offset=-1);finish(ob,hair,'head')
    hull('BobCrown',[(1.535,.128,.112,.134,0,.008),(1.57,.117,.111,.126,0,.012),
        (1.61,.089,.087,.094,0,.016),(1.637,.052,.055,.055,0,.016),(1.65,.004,.004,.004,0,.016)],hair,'head',n=48)
    # Apron is layered cloth with a true back split, not a closed stiff cone.
    apron_panel('ApronFront',[math.pi+math.pi*i/28 for i in range(29)],apron)
    apron_panel('ApronBackLeft',[.0+(math.pi*.5-.10)*i/18 for i in range(19)],apron)
    apron_panel('ApronBackRight',[math.pi*.5+.10+(math.pi*.5-.10)*i/18 for i in range(19)],apron)
    # Bib curvature stays fitted over blouse; 3mm material thickness inferred.
    rows=[]
    for z,rx,cy in [(1.061,.108,-.105),(1.13,.111,-.124),(1.20,.112,-.131),(1.255,.104,-.105)]:
        rows.append([(rx*(2*i/20-1),cy+.022*(2*i/20-1)**2,z) for i in range(21)])
    ob=H.loft(PREFIX+'ApronBib_LOD0',rows,close_sections=False,cap_ends=False);H.solidify(ob,.003,offset=0);finish(ob,apron,'chest')
    hull('WaistTie',[(1.046,.122,.103,.096,0,-.003),(1.078,.123,.104,.097,0,-.003)],apron,'pelvis')
    for side,sign in [('L',1),('R',-1)]:
        tube('ApronStrap.'+side,[(sign*.087,-.105,1.247),(sign*.087,-.065,1.323),
             (sign*.086,.016,1.338),(sign*.088,.079,1.287),(sign*.09,.093,1.081)],
             [(.014,.004)]*5,apron,'chest',n=12)
        oval('BowLoop.'+side,(sign*.045,-.124,1.030),(.043,.020,.029),apron,'pelvis')
    oval('BowKnot',(0,-.132,1.050),(.018,.018,.022),apron,'pelvis')
    # Collar construction is a primary garment mass; seams/pockets wait for forms.
    for side,sign in [('L',1),('R',-1)]:
        ob=H.profile_extrude(PREFIX+'Collar.'+side+'_LOD0',[(sign*.025,1.351),(sign*.073,1.326),(sign*.070,1.278),(sign*.014,1.312)],.008)
        # Profile is XY by helper: map its Y to world Z, extrusion to front depth.
        for v in ob.data.vertices:
            x,y,z=v.co;v.co=(x,-.070-z,y)
        finish(ob,blouse,'chest')
    # Profile correction from world gate r1: head/torso silhouette was 12-20px
    # posterior to the actual sheet, while shoes were 10px anterior. Front
    # widths are unchanged. These are measured profile offsets, not rescaling.
    for ob in PARTS:
        region=ob.get('region','')
        if region in ['head','neck','torso','chest']: ob.location.y-=.020
        elif region.startswith(('arm.','upper_arm.','hand.','finger')): ob.location.y+=.020
        elif region.startswith('foot.'): ob.location.y+=.020
    # Keep apron waist/tie position consistent with the shifted blouse; the
    # main wrap already received only the missing front-depth correction.
    for ob in PARTS:
        if any(token in ob.name for token in ['WaistTie','BowLoop','BowKnot']): ob.location.y-=.015
    # Store measured reference contract; refinement must preserve this outline.
    scene=bpy.context.scene;scene['asset']='CH_Nagisa_Foundation';scene['target_height_m']=1.65
    scene['reference_head_heights']=6.5;scene['blockout_is_delivery']=False
    H.save_master(str(ROOT/'CH_Nagisa_master.blend'))
    summary={'phase':'02_blockout','parts':len(PARTS),'height_target_m':1.65,'reference_heads':6.5,
             'inferred':'hidden anatomy, cross-section roundness and cloth thickness; see brief',
             'render_gate':'pending; run fixed/world-registered silhouettes before forms'}
    (ROOT/'review/blockout-build.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('BLOCKOUT',len(PARTS),'parts; gate pending')

if __name__=='__main__': build()
