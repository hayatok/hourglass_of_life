"""Distinct original resident forms built in the calibrated canonical metre space.

Heights/widths use each profile and front matte. Hidden garment depth, construction,
accessory pivots and all movement are authored inferences, not measured human data.
These are functional WIP models; silhouette/cloth/contact art acceptance remains separate.
"""
import math,bpy,bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import resident_forms as R

COSTUMES={'apron','cardigan_skirt','sweater','hood_jacket'}

def rounded_box(b,name,size,location,material,bind='chest_rigid',radius=.008):
    ob=b.H.box(b.PREFIX+name+'_LOD0',size,location=location)
    b.H.bevel(ob,radius,3)
    return b.finish(ob,material,bind)

def hair(b,f,p,detail=False):
    kind=p['hair']['style'];color=p['hair']['color']
    dark=b.material('Hair',color,.76)
    mid=b.material('Hair mid',[min(.8,c*1.25) for c in color],.75)
    light=b.material('Hair strand',[min(.9,c*1.5) for c in color],.72)
    if detail:
        for i in range(3):
            a=.25+i*.9
            f.hair_lock('HairAccent%02d'%i,[(.015,.018,1.643),(.07*math.cos(a),.085*math.sin(a),1.638),
                (.12*math.cos(a),.12*math.sin(a),1.59),(.105*math.cos(a),.11*math.sin(a),1.53)],.010,mid,light)
        return
    bob=kind=='wavy_bob'
    lower=1.415 if bob else 1.475
    rows=[(lower,.085,.085),(1.48,.112,.108),(1.53,.117,.111),
          (1.58,.10,.10),(1.62,.070,.073),(1.645,.026,.03),(1.65,.002,.003)]
    verts=[];faces=[];n=48
    for z,rx,ry in rows:
        for i in range(n):
            a=math.tau*i/n
            zz=max(z,1.565) if math.sin(a)<-.35 else z
            verts.append((rx*math.cos(a),.018+ry*math.sin(a),zz))
    for j in range(len(rows)-1):
        for i in range(n):
            ids=(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)
            if len({tuple(verts[k]) for k in ids})>=3:faces.append(ids)
    f.mesh('HairCap',verts,faces,dark,thickness=.002)
    for i in range(13):
        a=-.22+i*(math.pi+.44)/12;c=math.cos(a);s=math.sin(a)
        end=1.418+.013*math.sin(i*1.8) if bob else 1.482+.015*math.sin(i*1.7)
        er=.101 if bob else .113
        f.hair_lock('HairMass%02d'%i,[(.016,.014,1.642),(.11*c,.11*s+.018,1.615),
            (.135*c,.133*s+.018,1.49 if bob else 1.555),(er*c,.095*s+.018,end)],
            .031 if bob else .033,mid if i%3==0 else dark,light if i%4==0 else None)
    if kind=='swept':
        ends=[(-.095,-.065,1.555),(-.061,-.085,1.577),(.01,-.098,1.575),(.082,-.079,1.548)]
    elif kind=='parted':
        ends=[(-.086,-.078,1.51),(-.047,-.10,1.545),(.015,-.106,1.532),(.085,-.084,1.514)]
    elif kind=='shaggy':
        ends=[(-.091,-.082,1.50),(-.045,-.105,1.53),(.008,-.111,1.51),(.084,-.086,1.496)]
    else:
        ends=[(-.09,-.081,1.485),(-.047,-.105,1.52),(.025,-.108,1.551),(.091,-.083,1.478)]
    for i,end in enumerate(ends):
        f.hair_lock('Fringe%02d'%i,[(.026,-.015,1.645),(-.013+i*.023,-.09,1.633),
            (end[0]*1.14,end[1]-.012,end[2]+.035),end],.032,mid,light if i%2==0 else None)
    if kind=='ponytail':
        b.tube('PonytailMass',[(0,.11,1.51),(-.065,.17,1.46),(-.10,.20,1.38),(-.115,.204,1.30),(-.12,.19,1.265)],
            [.026,.047,.050,.031,.002],dark,'head',n=24)
        tie=b.material('Hair tie',(.36,.18,.035),.9)
        b.oval('PonytailTie',(0,.132,1.505),(.033,.012,.020),tie,'head',u=16,v=8)
        for i in range(6):
            x=(i-2.5)*.012
            f.hair_lock('PonytailLock%02d'%i,[(x,.14,1.50),(-.07+x*1.5,.232,1.45),
                (-.11+x*1.8,.242,1.34),(-.12+x*.4,.20,1.267)],.019,mid if i%2==0 else dark,light if i==2 else None)

def primary(root,b,f,p):
    prefix=root.name+'_';f.P=prefix
    if p['costume']!='apron':
        R.primary(root,b,f,p)
        R.remove(prefix,['Hair','Fringe'])
    else:
        R.remove(prefix,['Hair','Forearm.','BowBlockout'])
        skin=b.material('Skin',p.get('skin_color',[.91,.65,.45]),.82)
        for v in bpy.data.objects[prefix+'Head_LOD0'].data.vertices:
            if v.co.z<1.455:
                t=max(0,min(1,(1.455-v.co.z)/.065));v.co.x*=1+p.get('jaw',0)*t;v.co.y-=.008*t
        fit=R.FrontContours(root)
        skirt=bpy.data.objects[prefix+'ApronSkirt_LOD0']
        # The front matte establishes the apron widths; depth and folds remain inferred.
        stations=sorted({round(v.co.z,4) for v in skirt.data.vertices})
        for z in stations:
            interval=fit.interval(z)
            if not interval:continue
            original=max(abs(v.co.x) for v in skirt.data.vertices if abs(v.co.z-z)<.0001)
            target=(interval[1]-interval[0])/2/fit.d.width
            if original and .54<z<1.075:
                ratio=max(.8,min(1.2,target/original))
                for v in skirt.data.vertices:
                    if abs(v.co.z-z)<.0001:v.co.x*=ratio
        R.open_ends(skirt)
        for s,side in [(1,'L'),(-1,'R')]:
            b.oval('ShoulderDrape.'+side,(s*.12,0,1.295),(.049,.052,.047),
                bpy.data.materials['Sage'],'arm.'+side)
            b.tube('ArmSkin.'+side,[(s*.123,0,1.30),(s*.18,-.003,1.16),(s*.210,-.005,1.075),
                (s*.233,-.007,1.047),(s*.267,-.01,.981),(s*.300,-.014,.921),(s*.312,-.012,.90)],
                [.032,.030,.027,.029,.026,.020,.017],skin,'arm_skin.'+side,n=20)
            leg=b.rings('UnderlyingLeg.'+side,[(.07,.025,.027,s*.069,0),(.20,.030,.034,s*.069,.01),
                (.50,.044,.046,s*.069,.018),(.72,.056,.060,s*.068,.008),(.95,.062,.063,s*.068,0)],
                skin,'leg.'+side,collection='HIGH');leg.hide_render=True;leg.hide_set(True)
            if p['id']=='osamu':
                R.remove(prefix,['Trousers.'+side,'TrouserCuff.'+side])
                pants=b.material('Ivory',p['pants_color'],.94)
                ob=b.rings('Trousers.'+side,fit.sections([(.09,.043,.045,s*.07,0),(.18,.043,.045,s*.07,0),
                    (.32,.048,.05,s*.069,.012),(.5,.055,.057,s*.069,.018),(.65,.064,.069,s*.069,.01),
                    (.90,.071,.073,s*.066,0)],s),pants,'leg.'+side)
                ob['coverage_cut_z']=.76
        b.material('Sage',p['top_color'],.95)
        b.material('Ivory',p['pants_color'],.94)
        b.material('Terracotta',p['apron_color'],.95)
        b.material('Leather',p['shoe_color'],.65)
    costume=p['costume']
    if costume!='apron':
        # At some heights the generated matte joins a sleeve to the torso. Those pixels
        # cannot be used as torso radii; keep the inner tee inside the jacket envelope.
        for role in ['Tee','Overshirt']:
            ob=bpy.data.objects.get(prefix+role+'_LOD0')
            if ob:
                for z in sorted({round(v.co.z,5) for v in ob.data.vertices}):
                    ring=[v for v in ob.data.vertices if abs(v.co.z-z)<.00001]
                    rx=max(abs(v.co.x) for v in ring);ry=max(abs(v.co.y) for v in ring)
                    limit=.116 if role=='Tee' else .135
                    sx=min(1,limit/rx) if z<1.20 else 1
                    sy=min(1,(.065 if role=='Tee' else .088)/ry)
                    for v in ring:v.co.x*=sx;v.co.y*=sy
        if p['id'] in ['fumi','aoi']:
            rubber=b.material('Walking sole',(.026,.022,.019),.85)
            for side in ['L','R']:
                sole=bpy.data.objects[prefix+'ShoeSole.'+side+'_LOD0']
                sole.data.materials.clear();sole.data.materials.append(rubber)
    if costume=='cardigan_skirt':
        R.remove(prefix,['Trousers.','TrouserHips','Socks.'])
        skirt=b.material('Trousers',p['pants_color'],.96)
        rows=[(.22,.226,.131,0,0),(.30,.222,.13,0,0),(.50,.19,.12,0,0),
              (.72,.155,.105,0,0),(.92,.125,.09,0,0),(1.03,.112,.08,0,0)]
        fitted=R.FrontContours(root).sections(rows[:4])+rows[4:]
        ob=R.open_ends(b.rings('LongSkirt',fitted,skirt,'long_skirt',n=64))
        for v in ob.data.vertices:
            a=math.atan2(v.co.y,v.co.x)
            v.co.y*=1+.022*math.cos(a*12)
        skin=bpy.data.materials['Skin']
        for s,side in [(1,'L'),(-1,'R')]:
            b.rings('SkirtLeg.'+side,[(.08,.026,.028,s*.069,0),(.17,.027,.031,s*.069,.006),
                (.28,.029,.033,s*.069,.01),(.50,.035,.040,s*.069,.018),
                (.72,.050,.056,s*.068,.008),(.94,.060,.061,s*.068,0)],skin,'leg.'+side)
    if costume=='sweater':
        R.remove(prefix,['Overshirt','Tee'])
        top=bpy.data.materials['Top']
        b.rings('CrewneckSweater',[(.91,.119,.087,0,0),(1.02,.122,.09,0,0),
            (1.18,.137,.091,0,0),(1.29,.148,.077,0,0),(1.345,.043,.041,0,0)],top)
    if costume in ['cardigan_skirt','sweater','hood_jacket']:
        if costume!='sweater':
            # A blouse/hooded top fills the opening without an undershirt ending at the waist.
            tee=bpy.data.objects[prefix+'Tee_LOD0']
            for v in tee.data.vertices:
                if v.co.z<.98:v.co.z-=.025
        if costume=='cardigan_skirt':
            # Longer soft cardigan sleeves, using the arm axis instead of a detached cuff.
            R.remove(prefix,['Sleeve.','SleeveHem.'])
            for s,side in [(1,'L'),(-1,'R')]:
                b.tube('Sleeve.'+side,[(s*.123,0,1.30),(s*.18,-.003,1.16),
                    (s*.24,-.008,1.03),(s*.27,-.01,.985)],[(.047,.052),(.047,.052),(.046,.049),(.033,.037)],
                    bpy.data.materials['Top'],'arm.'+side)
    hair(b,f,p)
    for ob in b.H.col('LOW').objects:ob['owner']='phase:02_blockout'

def mature_face(b,f,p):
    if not p.get('mature'):return
    shade=b.material('Age lines',(.48,.27,.17),.95)
    for s,side in [(1,'L'),(-1,'R')]:
        for i in range(2):
            pts=[]
            for j in range(7):
                x=s*(.063+j*.003);z=1.474-i*.005-.003*math.sin(j/6*math.pi)
                pts.append((x,f.surface_y(x,z)-.0017,z))
            f.tube('EyeLine%d.%s'%(i,side),pts,.00075,shade,face='age_lines')
        pts=[]
        for j in range(8):
            z=1.454-j*.0035;x=s*(.029+.005*math.sin(j/7*math.pi))
            pts.append((x,f.surface_y(x,z)-.0015,z))
        f.tube('SmileLine.'+side,pts,.0008,shade,face='age_lines')
    if p.get('glasses'):
        metal=b.material('Spectacle metal',(.10,.065,.028),.4,.6)
        for s,side in [(1,'L'),(-1,'R')]:
            pts=[]
            for j in range(49):
                a=math.tau*j/48;x=s*.041+.029*math.cos(a);z=1.49+.026*math.sin(a)
                pts.append((x,f.surface_y(x,z)-.015,z))
            f.tube('GlassesFrame.'+side,pts,.0015,metal)
            f.tube('GlassesTemple.'+side,[(s*.07,-.082,1.495),(s*.095,-.035,1.49),
                (s*.108,.006,1.48)],.0015,metal)
        f.tube('GlassesBridge',[(-.012,-.11,1.494),(0,-.117,1.501),(.012,-.11,1.494)],.0015,metal)

def apron_details(root,b,f,p):
    top=bpy.data.materials['Sage'];cloth=bpy.data.materials['Terracotta'];brass=bpy.data.materials['Brass']
    stitch=b.material('Apron stitch',[min(.9,c*1.25+.01) for c in p['apron_color']],.96)
    skirt=bpy.data.objects[root.name+'_ApronSkirt_LOD0']
    surface=BVHTree.FromPolygons([v.co for v in skirt.data.vertices],[list(poly.vertices) for poly in skirt.data.polygons])
    b.rings('CollarStand',[(1.327,.039,.036,0,0),(1.355,.036,.033,0,0)],top,'neck')
    for s,side in [(1,'L'),(-1,'R')]:
        f.mesh('Collar.'+side,[(s*.033,-.027,1.355),(s*.067,-.049,1.32),
            (s*.045,-.077,1.293),(s*.01,-.048,1.321)],[(0,1,2,3)],top,'chest',thickness=.003)
        f.ribbon('ApronStrap.'+side,[(s*.074,-.091,1.28),(s*.074,-.072,1.314),
            (s*.072,-.025,1.343),(s*.068,.025,1.339),(s*.064,.065,1.305)],.018,cloth)
        f.ribbon('CrossStrap.'+side,[(s*.064,.065,1.305),(s*.032,.079,1.23),
            (-s*.012,.085,1.16),(-s*.062,.079,1.095)],.021,cloth,normal=(0,1,0))
        b.oval('StrapButton.'+side,(s*.074,-.097,1.271),(.008,.0027,.008),brass,'chest',u=16,v=8)
        verts=[];faces=[]
        for j in range(5):
            for k in range(7):
                x=s*.11+(k/6-.5)*.076;z=.78+j*.03
                hit=surface.ray_cast(Vector((x,-2,z)),Vector((0,1,0)))[0]
                verts.append((x,(hit.y if hit else -.12)-.003,z))
        for j in range(4):
            for k in range(6):
                a=j*7+k;faces.append((a,a+1,a+8,a+7))
        f.mesh('ApronPocket.'+side,verts,faces,cloth,'pelvis',thickness=.002)
        f.ribbon('BowLoop.'+side,[(0,-.135,1.08),(s*.033,-.148,1.09),
            (s*.063,-.143,1.079),(s*.052,-.144,1.054),(s*.015,-.146,1.078)],.025,cloth,'pelvis')
        f.ribbon('BowTail.'+side,[(s*.009,-.144,1.069),(s*.019,-.143,1.008),(s*.030,-.147,.903)],.028,cloth,'pelvis')
    rounded_box(b,'BowKnot',(.026,.021,.027),(0,-.139,1.079),cloth,'pelvis',.004)
    f.tube('BibTop',[(-.088,-.093,1.278),(0,-.099,1.278),(.088,-.093,1.278)],.0018,stitch,'chest')
    for i in range(2):b.oval('BlouseButton%d'%i,(0,-.058,1.31+i*.025),(.003,.002,.003),brass,'chest',u=12,v=8)

def accessories(b,f,p):
    ivory=bpy.data.materials['Ivory'];brass=bpy.data.materials['Brass']
    black=b.material('Accessory graphite',(.035,.033,.035),.7)
    metal=b.material('Accessory silver',(.38,.40,.42),.35,.6)
    if p['id']=='fumi':
        rounded_box(b,'CameraBody',(.12,.037,.075),(0,-.122,1.10),black)
        rounded_box(b,'CameraTop',(.12,.037,.015),(0,-.122,1.137),metal,radius=.003)
        # The limb-loft helper has no frame for an exactly Y-aligned tube; use proper cylinders.
        lens=b.H.cylinder(b.PREFIX+'CameraLens_LOD0',.028,.03,axis='Y',location=(.012,-.16,1.10),segments=24)
        b.finish(lens,metal,'chest_rigid')
        glass=b.H.cylinder(b.PREFIX+'CameraGlass_LOD0',.022,.003,axis='Y',location=(.012,-.177,1.10),segments=24)
        b.finish(glass,black,'chest_rigid')
        for s,side in [(1,'L'),(-1,'R')]:
            f.ribbon('CameraStrap.'+side,[(s*.05,-.132,1.13),(s*.068,-.10,1.25),
                (s*.05,-.015,1.35),(s*.04,.035,1.35)],.012,black,'chest_rigid',normal=(1,0,0))
    if p['id']=='ritsu':
        for s,side in [(1,'L'),(-1,'R')]:
            b.oval('HeadphonePad.'+side,(s*.066,-.063,1.315),(.028,.027,.041),black,'chest_rigid')
            b.oval('HeadphoneCup.'+side,(s*.078,-.075,1.315),(.019,.022,.034),metal,'chest_rigid')
        pts=[]
        for i in range(25):
            a=math.pi*i/24;pts.append((.08*math.cos(a),-.014+.066*math.sin(a),1.337))
        f.tube('HeadphoneBand',pts,.007,black,'chest_rigid')
    if p['id']=='aoi':
        bag=b.material('Backpack mustard',(.54,.29,.027),.9)
        rounded_box(b,'Backpack',(.20,.115,.27),(0,.165,1.13),bag,radius=.035)
        rounded_box(b,'BackpackPocket',(.153,.032,.10),(0,.234,1.065),bag,radius=.012)
        for s,side in [(1,'L'),(-1,'R')]:
            f.ribbon('BagStrap.'+side,[(s*.074,.145,1.24),(s*.087,.045,1.335),
                (s*.10,-.057,1.30),(s*.105,-.095,1.13),(s*.10,.07,1.015)],.023,bag,'chest',normal=(1,0,0))
            rounded_box(b,'BagBuckle.'+side,(.027,.009,.028),(s*.103,-.101,1.21),metal,'chest_rigid',.003)
        f.tube('BackpackHandle',[(-.027,.17,1.263),(-.025,.17,1.295),(.025,.17,1.295),(.027,.17,1.263)],.005,bag,'chest_rigid')
        # The lowered hood is a hollow cloth crescent with an open neck, not a solid neck torus.
        f.ribbon('HoodEdge',[(-.084,-.025,1.33),(-.086,.07,1.35),(-.055,.123,1.31),
            (0,.14,1.29),(.055,.123,1.31),(.086,.07,1.35),(.084,-.025,1.33)],.045,ivory,'chest',normal=(0,0,1))
        for s,side in [(1,'L'),(-1,'R')]:
            f.tube('HoodString.'+side,[(s*.035,-.043,1.335),(s*.033,-.088,1.27),(s*.031,-.09,1.22)],.0022,ivory,'chest')

def refine(root,b,f,p):
    f.P=root.name+'_';b.H.OWNER_TAG='phase:03_forms'
    # Blender discards unused phase-02 materials when reopening the canonical file.
    b.material('Brass',(.63,.38,.10),.4,.65)
    R.face(root,b,f,p);mature_face(b,f,p);hair(b,f,p,True)
    if p['costume']=='apron':apron_details(root,b,f,p)
    else:
        top=bpy.data.materials['Top'];ivory=bpy.data.materials['Ivory'];brass=bpy.data.materials['Brass']
        if p['costume']=='sweater':
            b.rings('SweaterHem',[(.90,.12,.088,0,0),(.947,.121,.089,0,0)],top)
            b.rings('CrewneckRib',[(1.333,.045,.043,0,0),(1.35,.043,.041,0,0)],top,'neck')
        for s,side in [(1,'L'),(-1,'R')]:
            if p['costume']=='cardigan_skirt':
                b.tube('CardiganCuff.'+side,[(s*.258,-.009,1.008),(s*.277,-.01,.968)],
                    [(.035,.039),(.032,.036)],top,'arm.'+side)
            else:
                b.tube('KnitCuff.'+side,[(s*.218,-.006,1.08),(s*.245,-.008,1.022)],
                    [(.043,.047),(.036,.04)],top,'arm.'+side)
            if p['costume']!='sweater':
                f.mesh('Collar.'+side,[(s*.02,-.045,1.337),(s*.067,-.065,1.31),
                    (s*.049,-.09,1.275),(s*.016,-.065,1.306)],[(0,1,2,3)],
                    ivory if p['id']=='fumi' else top,'chest',thickness=.003)
                f.mesh('LowerPocket.'+side,[(s*.045,-.09,.91),(s*.102,-.065,.91),
                    (s*.105,-.072,1.03),(s*.048,-.092,1.03)],[(0,1,2,3)],top,'chest',thickness=.002)
        if p['costume']!='sweater':
            for i in range(5):b.oval('ShirtButton%02d'%i,(-.029,-.092,.95+i*.065),(.003,.002,.003),brass,'chest',u=12,v=8)
    accessories(b,f,p)
