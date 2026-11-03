"""Resident-specific silhouettes and clothing in the common canonical construction space.
All real dimensions come from each asset profile; hidden anatomy and garment depth are inferred.
"""
import math,json,bpy,bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from dimensions import Dimensions

class FrontContours:
    """Loft stations measured from the original front matte, at the authored metre scale.
    Side depth remains inferred. Keep sparse stations; do not reproduce raster edge noise.
    """
    def __init__(self,root):
        self.c=json.loads((root/'ref/calibration.json').read_text());self.d=Dimensions(root)
    def interval(self,z,sign=0):
        row=round(self.c['ground_y']-self.d.z(z)/self.c['meters_per_pixel'])
        row=max(0,min(len(self.c['front_runs'])-1,row))
        axis=self.c['views']['front']['axis_x'];mp=self.c['meters_per_pixel']
        runs=[((a-axis)*mp,(b-axis)*mp) for a,b in self.c['front_runs'][row]]
        center=next(((a,b) for a,b in runs if a<=0<=b),None)
        if not sign:return center
        if center and min(abs(center[0]),abs(center[1]))>.015:
            return (0,center[1]) if sign>0 else (center[0],0)
        candidates=[(a,b) for a,b in runs if (a+b)*sign>0]
        return min(candidates,key=lambda ab:abs((ab[0]+ab[1])/2)) if candidates else None
    def sections(self,rows,sign=0,inner_gap=0):
        out=[]
        for z,rx,ry,cx,cy in rows:
            interval=self.interval(z,sign)
            if interval and z>.15:
                a,b=interval
                if inner_gap:
                    if sign>0:a=max(a,inner_gap)
                    if sign<0:b=min(b,-inner_gap)
                left=self.d.to_base((a,cy*self.d.depth,self.d.z(z))).x
                right=self.d.to_base((b,cy*self.d.depth,self.d.z(z))).x
                radius=max(.022,(right-left)/2)
                ry*=max(.65,min(1.35,(radius/rx)**.5))
                rx=radius;cx=(left+right)/2
            out.append((z,rx,ry,cx,cy))
        return out

def remove(prefix,roles):
    for ob in list(bpy.data.objects):
        if ob.name.startswith(tuple(prefix+r for r in roles)):bpy.data.objects.remove(ob,do_unlink=True)

def open_ends(ob,thickness=.002):
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if len(f.verts)>4],context='FACES')
    bm.to_mesh(ob.data);bm.free()
    if thickness:ob.modifiers.new('Sewn thickness','SOLIDIFY').thickness=thickness
    return ob

def hair(b,f,p,detail=False):
    h=p['hair'];kind=h['style'];color=h['color']
    dark=b.material('Hair',color,.76)
    mid=b.material('Hair mid',tuple(c*1.35 for c in color),.75)
    light=b.material('Hair strand',tuple(c*1.75 for c in color),.72)
    if not detail:
        rows=[(1.47,.078,.072),(1.51,.105,.091),(1.56,.11,.101),
              (1.60,.083,.082),(1.634,.047,.049),(1.65,.002,.003)]
        verts=[];faces=[];n=48
        for z,rx,ry in rows:
            for i in range(n):
                a=math.tau*i/n;zz=max(z,1.56) if math.sin(a)<-.35 else z
                verts.append((rx*math.cos(a),.018+ry*math.sin(a),zz))
        for j in range(len(rows)-1):
            for i in range(n):
                ids=(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)
                if len({tuple(verts[k]) for k in ids})>=3:faces.append(ids)
        f.mesh('HairCap',verts,faces,dark,thickness=.002)
        # Swept side clumps establish the primary silhouette before face detailing.
        count=9 if kind=='quiff' else 13
        for i in range(count):
            a=-.22+i*(math.pi+.44)/(count-1);c=math.cos(a);s=math.sin(a)
            end=1.49 if kind=='quiff' else 1.51+.018*math.sin(i*1.7)
            end_r=.112 if kind=='quiff' else (.13 if i%3==0 else .11)
            f.hair_lock('HairMass%02d'%i,[(.012,.016,1.642),(.10*c,.10*s+.018,1.62),
                 (.127*c,.12*s+.018,1.55),(end_r*c,.095*s+.018,end)],.037,mid if i%3==0 else dark)
        # Four separate forehead locks retain an open face and different adult/child silhouettes.
        ends=[(-.082,-.083,1.515),(-.045,-.100,1.54),(.005,-.105,1.525),(.076,-.088,1.502)]
        if kind=='quiff':ends=[(-.09,-.075,1.53),(-.055,-.092,1.558),(.001,-.10,1.548),(.079,-.082,1.526)]
        for i,end in enumerate(ends):
            f.hair_lock('Fringe%02d'%i,[(.025,-.015,1.645),(-.015+i*.024,-.082,1.642),
               (end[0]*1.15,end[1]-.014,end[2]+.025),end],.032,mid,light if i%2==0 else None)
    else:
        for i in range(4):
            a=.1+i*.72;c=math.cos(a);s=math.sin(a)
            f.hair_lock('HairAccent%02d'%i,[(.02,.02,1.645),(.06*c,.08*s,1.64),
                (.13*c,.12*s,1.60),(.13*c,.11*s,1.54)],.012,mid,light)

def primary(root,b,f,p):
    prefix=root.name+'_';f.P=prefix
    remove(prefix,['Blouse','Hair','Sleeve.','Cuff.','Trousers.','TrouserCuff.','Ankle.',
                   'Shoe.','Apron','WaistTie','BowBlockout','Forearm.'])
    skin=b.material('Skin',(.91,.65,.45),.82)
    ivory=b.material('Ivory',(.78,.73,.61),.95)
    brass=b.material('Brass',(.63,.38,.10),.4,.65)
    top=b.material('Top',p['top_color'],.95)
    pants=b.material('Trousers',p['pants_color'],.94)
    leather=b.material('Leather',p['shoe_color'],.65)
    kid=p['costume']=='overalls'
    fit=FrontContours(root)
    # Canonical face outline is deliberately different: a stronger adult jaw, softer child cheeks.
    head=bpy.data.objects[prefix+'Head_LOD0']
    for v in head.data.vertices:
        if v.co.z<1.455:
            t=max(0,min(1,(1.455-v.co.z)/.065))
            v.co.x*=1+p.get('jaw',0)*t
            v.co.y-=.008*t
    tee=[(.97 if kid else .90,.107,.074,0,0),(1.12,.108,.078,0,0),
        (1.24,.132,.082,0,0),(1.30,.142,.065,0,0),(1.34,.042,.036,0,0)]
    fitted=fit.sections(tee[:2])
    tee=fitted+tee[2:]
    if not kid:tee=[(z,rx*.91,ry,cx,cy) for z,rx,ry,cx,cy in tee]
    b.rings('Tee',tee,ivory)
    if not kid:
        # Open overshirt built around the tee, with a genuine gap at the front.
        rows=[(.87,.119,.084),(1.03,.12,.088),(1.20,.137,.088),(1.30,.151,.074),(1.34,.047,.042)]
        fitted=fit.sections([(z,rx,ry,0,0) for z,rx,ry in rows[:2]])
        rows=[(z,rx,ry) for z,rx,ry,_,_ in fitted]+rows[2:]
        verts=[];faces=[];n=36
        for z,rx,ry in rows:
            for i in range(n+1):
                a=-math.pi/2+.23+(math.tau-.46)*i/n
                verts.append((rx*math.cos(a),ry*math.sin(a),z))
        for j in range(len(rows)-1):
            for i in range(n):
                a=j*(n+1)+i;faces.append((a,a+1,a+n+2,a+n+1))
        f.mesh('Overshirt',verts,faces,top,'chest',thickness=.003)
        b.rings('TrouserHips',[(.835,.126,.085,0,.003),(1.035,.116,.078,0,0)],pants,'hips')
    else:
        b.rings('OverallHips',[(.74,.129,.085,0,.003),(.99,.12,.081,0,0),(1.07,.105,.078,0,-.003)],pants,'hips')
        verts=[(-.081,-.084,1.065),(.081,-.084,1.065),(.085,-.089,1.24),(-.085,-.089,1.24)]
        f.mesh('OverallBib',verts,[(0,1,2,3)],pants,'chest',thickness=.003)
        for sign,side in [(1,'L'),(-1,'R')]:
            f.ribbon('OverallStrap.'+side,[(sign*.072,-.092,1.23),(sign*.076,-.068,1.30),
                (sign*.076,0,1.325),(sign*.075,.07,1.29),(sign*.07,.085,1.06)],.021,pants,'chest',normal=(1,0,0))
    for sign,side in [(1,'L'),(-1,'R')]:
        # Complete arms/legs remain in the source; only costume-covered export regions are cut.
        arm=b.tube('ArmSkin.'+side,[(sign*.123,0,1.30),(sign*.18,-.003,1.16),
            (sign*.210,-.005,1.075),(sign*.233,-.007,1.047),(sign*.267,-.01,.981),
            (sign*.300,-.014,.921),(sign*.312,-.012,.90)],
            [.032,.030,.027,.029,.026,.020,.017],skin,'arm_skin.'+side,n=20)
        # Keep the continuous arm under the sleeve: coarse coverage deletion left an elbow gap.
        sleeve_end=1.19 if kid else 1.045
        endpoint=(sign*(.175 if kid else .232),-.004,sleeve_end)
        b.tube('Sleeve.'+side,[(sign*.123,0,1.30),(sign*.155,0,1.23),endpoint],
            [(.047,.051),(.047,.050),(.041,.045)],ivory if kid else top,'arm.'+side)
        b.oval('ShoulderDrape.'+side,(sign*.12,0,1.295),(.049,.052,.047),ivory if kid else top,'arm.'+side)
        b.tube('SleeveHem.'+side,[(endpoint[0]-sign*.004,endpoint[1],sleeve_end+.014),endpoint],
            [(.044,.048),(.044,.048)],ivory if kid else top,'arm.'+side)
        bare=[(.085,.023,.027,sign*.069,0),(.19,.025,.030,sign*.069,.008),
              (.35,.031,.035,sign*.069,.018),(.50,.035,.040,sign*.069,.018),
              (.65,.045,.050,sign*.069,.012),(.94,.061,.060,sign*.068,0)]
        skin_leg=b.rings('UnderlyingLeg.'+side,bare,skin,'leg.'+side,collection='HIGH')
        skin_leg.hide_render=True;skin_leg.hide_set(True)
        if kid:
            samples=[]
            for z in [.085,.17,.22,.28,.35,.42,.50,.56,.615]:
                for a,c in zip(bare,bare[1:]):
                    if a[0]<=z<=c[0]:
                        t=(z-a[0])/(c[0]-a[0])
                        samples.append((z,)+tuple(a[i]*(1-t)+c[i]*t for i in range(1,5)));break
            visible_leg=fit.sections(samples,sign)
            visible_leg.append((.66,)+visible_leg[-1][1:])
            b.rings('BareLeg.'+side,visible_leg,skin,'leg.'+side)
            open_ends(b.rings('OverallShorts.'+side,fit.sections([(.65,.065,.068,sign*.069,.012),
                (.68,.070,.073,sign*.069,.01),(.86,.071,.073,sign*.066,.003),(.94,.069,.072,sign*.066,0)],sign,.012),pants,'leg.'+side))
            open_ends(b.rings('ShortHem.'+side,fit.sections([(.635,.070,.073,sign*.069,.012),(.675,.071,.073,sign*.069,.012)],sign,.012),pants,'leg.'+side))
        else:
            b.rings('Trousers.'+side,fit.sections([(.105,.043,.044,sign*.07,0),(.18,.043,.045,sign*.07,0),
                (.33,.048,.048,sign*.069,.012),(.50,.057,.056,sign*.069,.018),
                (.65,.065,.069,sign*.069,.01),(.89,.073,.077,sign*.066,.003),(.96,.073,.077,sign*.066,0)],sign),pants,'leg.'+side)
        b.rings('Socks.'+side,[(.07,.027,.029,sign*.069,0),(.14,.028,.030,sign*.069,0),
            (.20 if kid else .15,.028,.030,sign*.069,0)],ivory,'shin.'+side)
        b.rings('ShoeSole.'+side,[(.005,.046,.109,sign*.077,-.045),(.028,.047,.11,sign*.077,-.045)],ivory,'foot.'+side)
        b.rings('ShoeUpper.'+side,[(.026,.045,.106,sign*.077,-.045),(.053,.044,.103,sign*.077,-.045),
            (.083,.036,.074,sign*.074,-.023),(.118,.03,.045,sign*.069,.006)],leather,'foot.'+side)
    hair(b,f,p)
    for ob in b.H.col('LOW').objects:ob['owner']='phase:02_blockout'

def face(root,b,f,p):
    f.P=root.name+'_';prefix=f.P
    head=bpy.data.objects[prefix+'Head_LOD0'];nose=bpy.data.objects[prefix+'Nose_LOD0']
    nose.hide_render=True;nose.hide_set(True)
    kid=p['costume']=='overalls'
    for v in head.data.vertices:
        if v.co.z<1.47:v.co.x*=.92 if kid else 1.10
        if v.co.y<0:v.co.y-=.01*math.exp(-((v.co.z-1.48)/.09)**2)*(1-min(1,abs(v.co.x)/.095))
    if kid:
        for side in ['L','R']:
            ear=bpy.data.objects[prefix+'Ear.'+side+'_LOD0']
            # Child concha is smaller than the mature adult ear in the source base.
            ear.scale*=.85
    bpy.context.view_layer.objects.active=head
    sub=head.modifiers.new('Continuous anime cheek','SUBSURF');sub.levels=1
    bpy.ops.object.modifier_apply(modifier=sub.name)
    for v in head.data.vertices:
        if v.co.y<-.035:v.co.y-=.010*math.exp(-(v.co.x/.010)**2-((v.co.z-1.464)/.018)**2)
    f.FACE_TREE=BVHTree.FromPolygons([v.co for v in head.data.vertices],[list(poly.vertices) for poly in head.data.polygons])
    white=b.material('Eyes ivory',(.94,.90,.80),.6)
    ink=b.material('Eyes ink',(.018,.009,.006),.75)
    rim=b.material('Iris rim',(.095,.032,.006),.7)
    amber=b.material('Iris amber',(.48,.21,.028),.7)
    gold=b.material('Iris lower',(.78,.42,.07),.7)
    shine=b.material('Eye glint',(1,1,.98),.35)
    lip=b.material('Mouth',(.20,.058,.031),.9)
    eye_height=p.get('eye_height',.0175 if kid else .0145)
    for sign,side in [(1,'L'),(-1,'R')]:
        cx=sign*.041;cz=1.491
        f.eye_patch('Sclera.'+side,cx,cz,.025,eye_height,white,.003,side,True)
        f.eye_patch('IrisRim.'+side,cx,cz,.012,eye_height*.97,rim,.005,side)
        f.eye_patch('Iris.'+side,cx,cz-.001,.0097,eye_height*.82,amber,.0065,side)
        f.eye_patch('IrisGold.'+side,cx,cz-.006,.008,.0055,gold,.008,side)
        f.eye_patch('Pupil.'+side,cx,cz+.002,.0054,eye_height*.58,ink,.010,side)
        f.eye_patch('Glint.'+side,cx-sign*.0045,cz+.007,.0038,.0044,shine,.012,side)
        top=[];bottom=[];brow=[]
        for i in range(13):
            t=i/12;x=cx+sign*(t-.5)*.051
            z=cz+eye_height*math.sin(math.pi*t)+.006*(t-.5)
            top.append((x,f.surface_y(x,z)-.006,z))
            z=cz-eye_height*.8*math.sin(math.pi*t)+.006*(t-.5)
            bottom.append((x,f.surface_y(x,z)-.004,z))
            z=1.526+.006*math.sin(math.pi*t)-.004*t
            brow.append((x,f.surface_y(x,z)-.003,z))
        f.tube('UpperLash.'+side,top,.0015,ink,face='eye.'+side)
        f.tube('LowerLash.'+side,bottom[1:-1],.0007,rim,face='eye.'+side)
        f.tube('Brow.'+side,brow,.0015 if kid else .0025,bpy.data.materials['Hair'],face='brow.'+side)
    points=[]
    for i in range(17):
        x=(i/16-.5)*.043;z=1.432+.006*(abs(x)/.0215)**1.7
        points.append((x,f.surface_y(x,z)-.002,z))
    f.tube('Smile',points,.0011,lip,face='mouth')

def refine(root,b,f,p):
    f.P=root.name+'_';b.H.OWNER_TAG='phase:03_forms'
    face(root,b,f,p);hair(b,f,p,True)
    prefix=root.name+'_';kid=p['costume']=='overalls'
    cloth=bpy.data.materials['Trousers' if kid else 'Top'];brass=b.material('Brass',(.63,.38,.10),.4,.65)
    for sign,side in [(1,'L'),(-1,'R')]:
        if kid:
            if side=='L':
                f.mesh('BibPocket',[(-.048,-.094,1.105),(.048,-.094,1.105),(.048,-.094,1.19),(-.048,-.094,1.19)],
                    [(0,1,2,3)],cloth,'chest',thickness=.002)
                seam=b.material('Trouser seam',(.36,.17,.012),.96)
                f.tube('OverallCenterSeam',[(0,-.087,.98),(0,-.089,.82),(0,-.086,.67)],.0016,seam,'hips')
            b.oval('StrapButton.'+side,(sign*.072,-.096,1.23),(.008,.003,.008),brass,'chest',u=12,v=8)
        else:
            b.tube('RolledCuff.'+side,[(sign*.210,-.005,1.10),(sign*.233,-.008,1.04)],
                [(.058,.052),(.052,.048)],cloth,'arm.'+side)
            # Collar and breast pockets follow the overshirt surface instead of floating boxes.
            f.mesh('Collar.'+side,[(sign*.02,-.045,1.337),(sign*.067,-.065,1.31),
                (sign*.049,-.09,1.275),(sign*.016,-.065,1.306)],[(0,1,2,3)],cloth,'chest',thickness=.003)
            f.mesh('Pocket.'+side,[(sign*.047,-.086,1.15),(sign*.102,-.069,1.15),
                (sign*.103,-.072,1.215),(sign*.049,-.088,1.215)],[(0,1,2,3)],cloth,'chest',thickness=.002)
        for i in range(4):
            z=.061+i*.008;y=-.116+i*.014
            f.tube('Lace%d.%s'%(i,side),[(sign*.077-.022,y,z),(sign*.077+.022,y,z+.002)],.0015,
                bpy.data.materials['Ivory'],'foot.'+side)
    if not kid:
        for i in range(5):b.oval('ShirtButton%02d'%i,(-.029,-.09,1.045+i*.052),(.003,.002,.003),brass,'chest',u=12,v=8)
