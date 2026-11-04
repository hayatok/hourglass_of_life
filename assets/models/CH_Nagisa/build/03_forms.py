"""Secondary forms. Face/costume details follow the authored reference; depth is inferred.
Run after 02_blockout.py. Each owned detail can be rebuilt without accumulating objects.
"""
import sys, math, json
from pathlib import Path
import bpy, bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
import mesh_helpers as H
import importlib
B=importlib.import_module('02_blockout')
H.OWNER_TAG='phase:03_forms'
ROOT=Path(__file__).resolve().parents[1]
P='CH_Nagisa_'
FACE_TREE=None
HAIR_TREE=None

def mat(name,color,roughness=.85,metallic=0):return B.material(name,color,roughness,metallic)
def finish(ob, material, bind='head', face=''):
    ob.data.materials.append(material);ob['bind']=bind
    if ob.type=='MESH':
        for poly in ob.data.polygons:poly.use_smooth=True
    if face:
        ob['face_group']=face
        ob.visible_shadow=False
    return H.own(ob)

def mesh(name,verts,faces,material,bind='head',face='',thickness=0):
    me=bpy.data.meshes.new(P+name);me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new(P+name+'_LOD0',me);H.col('LOW').objects.link(ob)
    for poly in me.polygons:poly.use_smooth=True
    if thickness:
        mod=ob.modifiers.new('Sewn thickness','SOLIDIFY');mod.thickness=thickness
    return finish(ob,material,bind,face)

def tube(name,points,radius,material,bind='head',face=''):
    ob=H.curve_tube(P+name+'_LOD0',points,radius,resolution=2,bevel_res=1)
    finish(ob,material,bind,face)
    return ob

def surface_y(x,z):
    # Elliptic contour of the approved skull, sampled at the eye/mouth height.
    if FACE_TREE is not None:
        hit=FACE_TREE.ray_cast(Vector((x,-2,z)),Vector((0,1,0)))
        if hit[0] is not None:return hit[0].y
    profile=[(1.385,.012,.021,-.048),(1.398,.045,.039,-.036),
       (1.42,.071,.060,-.019),(1.45,.087,.074,-.008),(1.485,.093,.085,.004),
       (1.52,.095,.087,.006),(1.56,.089,.081,.012),(1.60,.071,.065,.016),
       (1.626,.038,.041,.015)]
    lo,hi=profile[0],profile[-1]
    for a,b in zip(profile,profile[1:]):
        if a[0]<=z<=b[0]:lo,hi=a,b;break
    t=max(0,min(1,(z-lo[0])/(hi[0]-lo[0])))
    rx=lo[1]*(1-t)+hi[1]*t;ry=lo[2]*(1-t)+hi[2]*t;cy=lo[3]*(1-t)+hi[3]*t
    return cy-ry*math.sqrt(max(.01,1-(x/rx)**2))

def eye_patch(name,cx,cz,rx,rz,material,offset,side,almond=False):
    verts=[(cx,surface_y(cx,cz)-offset,cz)];faces=[];n=36;nr=4
    for ri in range(1,nr+1):
        r=ri/nr
        for i in range(n):
            theta=math.tau*i/n
            xx=cx+rx*r*math.cos(theta)
            zz=cz+rz*r*math.sin(theta)*(abs(math.sin(theta))**(-.13) if almond and abs(math.sin(theta))>.0001 else 1)
            zz+=.003*(xx-cx)/rx*(1 if cx>0 else -1)
            yy=surface_y(xx,zz)-offset
            verts.append((xx,yy,zz))
    for i in range(n):faces.append((0,1+i,1+(i+1)%n))
    for ring in range(nr-1):
        for i in range(n):
            a=1+ring*n+i;b=1+ring*n+(i+1)%n
            faces.append((a,b,b+n,a+n))
    return mesh(name,verts,faces,material,face='eye.'+side)

def bezier(points,t):
    p=[Vector(v) for v in points]
    while len(p)>1:p=[a.lerp(b,t) for a,b in zip(p,p[1:])]
    return p[0]

def hair_lock(name,points,width,material,highlight=None):
    verts=[];faces=[];ns=14;across=8
    for i in range(ns+1):
        t=i/ns;c=bezier(points,t)
        tangent=(bezier(points,min(1,t+.01))-bezier(points,max(0,t-.01))).normalized()
        normal=Vector((c.x,c.y-.012,(c.z-1.49)*.8)).normalized()
        u=tangent.cross(normal).normalized()
        width_now=width*(.12+.88*math.sin(math.pi*t)**.5)*(1-.75*t**7)
        for j in range(across+1):
            s=j/across*2-1
            point=c+u*s*width_now+normal*(.004*(1-s*s))
            if HAIR_TREE is not None:
                center=Vector((0,.014,1.51));ray=(point-center).normalized()
                hit=HAIR_TREE.ray_cast(center,ray)
                if hit[0] is not None and (hit[0]-center).length>(point-center).length-.003:
                    point=hit[0]+ray*.003
            verts.append(point)
    for i in range(ns):
        for j in range(across):
            a=i*(across+1)+j;faces.append((a,a+1,a+across+2,a+across+1))
    ob=mesh(name,verts,faces,material,thickness=.002)
    if highlight:
        ob.data.materials.append(highlight)
        # Subtle intrinsic strand tint; lighting stays in the engine.
        for poly in ob.data.polygons:
            if poly.index%across in [3,4]:poly.material_index=1
    return ob

def ribbon(name,points,width,material,bind='chest',normal=(0,-1,0)):
    verts=[];faces=[]
    for i,point in enumerate(points):
        p=Vector(point)
        tangent=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        side=tangent.cross(Vector(normal)).normalized()*width/2
        verts.extend([p-side,p+side])
    for i in range(len(points)-1):faces.append((2*i,2*i+1,2*i+3,2*i+2))
    return mesh(name,verts,faces,material,bind,thickness=.002)

def build():
    H.open_master(str(ROOT/'CH_Nagisa_master.blend'));H.clear_owned()
    skin=mat('Skin',(.91,.65,.45),.82)
    hair=mat('Hair',(.055,.028,.021),.76)
    hairmid=mat('Hair mid',(.078,.039,.027),.75)
    hairlight=mat('Hair strand',(.105,.052,.032),.72)
    sage=mat('Sage',(.27,.29,.14),.95);sage_dark=mat('Sage seam',(.15,.17,.077),.95)
    terra=mat('Terracotta',(.46,.14,.065),.95);terra_dark=mat('Terracotta seam',(.28,.073,.031),.95)
    terra_light=mat('Terracotta stitch',(.57,.21,.105),.95)
    brass=mat('Brass',(.63,.38,.10),.4,.7)
    white=mat('Eyes ivory',(.94,.90,.80),.6);ink=mat('Eyes ink',(.018,.009,.006),.75)
    amber_dark=mat('Iris rim',(.095,.032,.006),.7)
    amber=mat('Iris amber',(.48,.21,.028),.7)
    amber_light=mat('Iris lower',(.78,.42,.07),.7)
    shine=mat('Eye glint',(1,1,.98),.35)
    lip=mat('Mouth',(.20,.058,.031),.9)

    # Idempotent changes to the approved primary topology (source measurements remain in 02).
    head=bpy.data.objects[P+'Head_LOD0']
    for v in head.data.vertices:
        if v.co.z<1.45 and not head.get('forms_applied'):
            v.co.y-=max(0,(1.45-v.co.z)/.065)*.017
    head['forms_applied']=True
    if not head.get('face_surface_v2'):
        # A broad, smooth anime cheek plane; a tiny continuous nose replaces an attached wedge.
        for v in head.data.vertices:
            if v.co.y<0:
                v.co.y-=.010*math.exp(-((v.co.z-1.48)/.09)**2)*(1-min(1,abs(v.co.x)/.095))
        for e in head.data.edges:e.use_edge_sharp=False
        bpy.context.view_layer.objects.active=head
        sub=head.modifiers.new('Continuous cheek loops','SUBSURF');sub.levels=1
        bpy.ops.object.modifier_apply(modifier=sub.name)
        for v in head.data.vertices:
            if v.co.y<-.035:
                v.co.y-=.009*math.exp(-(v.co.x/.010)**2-((v.co.z-1.464)/.018)**2)
        head['face_surface_v2']=True
    global FACE_TREE
    FACE_TREE=BVHTree.FromPolygons([v.co for v in head.data.vertices],
                                  [list(p.vertices) for p in head.data.polygons])
    for poly in bpy.data.objects[P+'ApronBib_LOD0'].data.polygons:poly.use_smooth=True
    for side in ['L','R']:
        forearm=bpy.data.objects[P+'Forearm.'+side+'_LOD0'];forearm.hide_render=True;forearm.hide_set(True)
        sign=1 if side=='L' else -1
        hidden_leg=B.rings('UnderlyingLegSkin.'+side,[(.07,.025,.027,sign*.069,0),
            (.20,.030,.034,sign*.069,.01),(.40,.042,.044,sign*.069,.018),
            (.50,.044,.046,sign*.069,.018),(.72,.056,.060,sign*.068,.008),
            (.95,.062,.063,sign*.068,0)],skin,'leg.'+side,collection='HIGH')
        hidden_leg.hide_render=True;hidden_leg.hide_set(True)
        B.tube('ArmSkin.'+side,[(sign*.123,0,1.30),(sign*.18,-.003,1.16),
            (sign*.210,-.005,1.075),(sign*.233,-.007,1.047),(sign*.267,-.01,.981),
            (sign*.300,-.014,.921),(sign*.312,-.012,.90)],
            [.030,.027,.027,.029,.026,.020,.017],skin,'arm_skin.'+side,n=20)
        trousers=bpy.data.objects[P+'Trousers.'+side+'_LOD0']
        # Complete trousers remain in this master; the export copy cuts only the covered hip shell.
        trousers['coverage_cut_z']=.76
        if not trousers.get('forms_applied'):
            for v in trousers.data.vertices:
                z=v.co.z
                if .22<z<.61:
                    cy=.012 if z<.36 else .018
                    v.co.y=cy+(v.co.y-cy)*1.30
            trousers['forms_applied']=True
        if not trousers.get('side_stance_v2'):
            stations=[(.177,.025),(.22,.026),(.30,.022),(.40,.005),(.48,-.006),(.60,-.015),(.91,0)]
            for v in trousers.data.vertices:
                z=v.co.z
                for (za,ya),(zb,yb) in zip(stations,stations[1:]):
                    if za<=z<=zb:
                        t=(z-za)/(zb-za);v.co.y+=ya*(1-t)+yb*t;break
            trousers['side_stance_v2']=True
        for part,shift in [('TrouserCuff.',.025),('Ankle.',.024),('Shoe.',.015)]:
            ob=bpy.data.objects[P+part+side+'_LOD0']
            if not ob.get('side_stance_v2'):
                for v in ob.data.vertices:v.co.y+=shift
                ob['side_stance_v2']=True
        shoe=bpy.data.objects[P+'Shoe.'+side+'_LOD0']
        if not shoe.get('shoe_length_v3'):
            for v in shoe.data.vertices:v.co.y=.07+(v.co.y-.07)*1.08
            shoe['shoe_length_v3']=True
    blouse=bpy.data.objects[P+'Blouse_LOD0']
    if not blouse.get('side_profile_v2'):
        for v in blouse.data.vertices:
            if 1.08<v.co.z<1.26:v.co.y=v.co.y*.90-.009
        blouse['side_profile_v2']=True
    B.rings('CollarStand',[(1.327,.039,.052,0,.016),(1.355,.038,.051,0,.016),
            (1.365,.035,.046,0,.016)],sage,'neck')
    # Face: conform each surface to the skull instead of placing spherical eyes outside it.
    nose=bpy.data.objects[P+'Nose_LOD0'];nose.hide_render=True;nose.hide_set(True)
    for sign,side in [(1,'L'),(-1,'R')]:
        cx=sign*.041;cz=1.491
        eye_patch('Sclera.'+side,cx,cz,.025,.0175,white,.003,side,True)
        eye_patch('IrisRim.'+side,cx,cz,.0120,.017,amber_dark,.005,side)
        eye_patch('Iris.'+side,cx,cz-.001,.0097,.0143,amber,.0065,side)
        eye_patch('IrisGold.'+side,cx,cz-.007,.0080,.0065,amber_light,.008,side)
        eye_patch('Pupil.'+side,cx,cz+.002,.0054,.0102,ink,.010,side)
        eye_patch('Glint.'+side,cx-sign*.0045,cz+.008,.0038,.0044,shine,.012,side)
        eye_patch('GlintSmall.'+side,cx+sign*.0055,cz-.007,.0015,.0019,shine,.012,side)
        upper=[];lower=[];brow=[]
        for i in range(13):
            t=i/12;xx=cx+sign*(t-.5)*.051
            zz=cz+.017*math.sin(math.pi*t)+.006*(t-.5)
            upper.append((xx,surface_y(xx,zz)-.006,zz))
            zz=cz-.014*math.sin(math.pi*t)+.006*(t-.5)
            lower.append((xx,surface_y(xx,zz)-.004,zz))
            xx=cx+sign*(t-.5)*.048;zz=1.53+.008*math.sin(math.pi*t)-.004*t
            brow.append((xx,surface_y(xx,zz)-.003,zz))
        tube('UpperLash.'+side,upper,.0017,ink,face='eye.'+side)
        tube('LowerLash.'+side,lower[1:-1],.00075,amber_dark,face='eye.'+side)
        tube('Brow.'+side,brow,.0015,hair,face='brow.'+side)
        out=upper[-1]
        tube('LashTip.'+side,[out,(out[0]+sign*.007,out[1]+.002,out[2]+.007)],.0016,ink,face='eye.'+side)
        # Ears: inner concha remains a warm recess, not a hole through the head.
        tube('EarFold.'+side,[(sign*.099,-.011,1.49),(sign*.107,-.014,1.477),
             (sign*.103,-.012,1.459)],.0027,mat('Ear shade',(.70,.40,.27)),face='')
    mouth=[]
    for i in range(17):
        x=(i/16-.5)*.043;z=1.432+.006*(abs(x)/.0215)**1.7
        mouth.append((x,surface_y(x,z)-.002,z))
    tube('Smile',mouth,.0011,lip,face='mouth')
    tube('LowerLip',[(-.01,surface_y(-.01,1.426)-.001,1.426),
         (0,surface_y(0,1.424)-.001,1.424),(.01,surface_y(.01,1.426)-.001,1.426)],.0012,
         mat('Lip highlight',(.94,.62,.43)),face='mouth')

    # Back and side locks: large readable clumps with pointed, inward-curled ends.
    cap=bpy.data.objects[P+'Hair_LOD0']
    if not cap.get('nape_taper_v4'):
        for v in cap.data.vertices:
            t=max(0,min(1,(1.445-v.co.z)/.05))
            v.co.x*=1-.12*t
        cap['nape_taper_v4']=True
    if not cap.get('fringe_open_v2'):
        bm=bmesh.new();bm.from_mesh(cap.data)
        discard=[]
        for f in bm.faces:
            c=f.calc_center_median()
            if c.y<-.025 and abs(c.x)<.098 and c.z<1.57+.014*(1-abs(c.x)/.1):discard.append(f)
        bmesh.ops.delete(bm,geom=discard,context='FACES')
        bm.to_mesh(cap.data);bm.free();cap['fringe_open_v2']=True
    global HAIR_TREE
    HAIR_TREE=BVHTree.FromPolygons([v.co for v in cap.data.vertices],
                                 [list(p.vertices) for p in cap.data.polygons])
    for i in range(13):
        a=-.20+i*(math.pi+.4)/12
        c,s=math.cos(a),math.sin(a)
        points=[(.018,.015,1.645),(.11*c,.116*s+.012,1.62),
                (.136*c,.137*s+.014,1.47),(.080*c,.103*s+.018,1.407+.009*math.sin(i*1.3))]
        hair_lock('BobLock%02d'%i,points,.025 if i in [0,12] else .032,
                  hairmid if i%3==0 else hair,hairlight if i%4==0 else None)
    # Asymmetric parted fringe, using the original drawing's swept left-hand silhouette.
    bangs=[([(.027,-.028,1.643),(-.018,-.105,1.635),(-.078,-.122,1.535),(-.074,-.103,1.498)],.032),
           ([(.025,-.035,1.642),(.008,-.112,1.62),(-.014,-.128,1.55),(-.046,-.105,1.513)],.030),
           ([(.034,-.023,1.640),(.083,-.080,1.63),(.103,-.117,1.53),(.085,-.093,1.438)],.026),
           ([(-.005,-.011,1.644),(-.088,-.069,1.61),(-.135,-.101,1.48),(-.082,-.081,1.414)],.026)]
    for i,(points,width) in enumerate(bangs):hair_lock('Fringe%02d'%i,points,width,hairmid,hairlight)

    # Major cloth folds, kept below 1 cm and aligned to the waist construction.
    skirt=bpy.data.objects[P+'ApronSkirt_LOD0']
    if not skirt.get('open_hem_v4'):
        bm=bmesh.new();bm.from_mesh(skirt.data)
        bmesh.ops.delete(bm,geom=[f for f in bm.faces if len(f.verts)>4],context='FACES')
        bm.to_mesh(skirt.data);bm.free()
        thickness=skirt.modifiers.new('Open cloth hem','SOLIDIFY');thickness.thickness=.002
        skirt['open_hem_v4']=True
    if not skirt.get('forms_applied'):
        for v in skirt.data.vertices:
            t=max(0,min(1,(1.09-v.co.z)/.55))
            if v.co.y<-.02:
                v.co.y-=.006*math.sin(v.co.x*65+t*2)**2*math.sin(t*math.pi)
        skirt['forms_applied']=True
    for sign,side in [(1,'L'),(-1,'R')]:
        shoulder=B.oval('ShoulderDrape.'+side,(sign*.12,0,1.29),(.049,.052,.047),sage,'arm.'+side,u=24,v=12)
        shoulder['owner']=H.OWNER_TAG
        # Rolled sleeve creases have a continuous axis rather than detached elbow cylinders.
        for i in range(2):
            z=1.11+i*.045;x=sign*(.194-i*.021)
            tube('SleeveFold%d.%s'%(i,side),[(x-sign*.025,-.035,z-.012),
                (x,-.05,z),(x+sign*.024,-.031,z+.009)],.003,sage_dark,'arm.'+side)
        # Small leaf collar, clearly separated from the neck, follows the blouse neckline.
        mesh('Collar.'+side,[(sign*.033,-.027,1.355),(sign*.067,-.049,1.32),
            (sign*.045,-.077,1.293),(sign*.010,-.048,1.321)],[(0,1,2,3)],sage,'chest',thickness=.003)
        ribbon('ApronStrap.'+side,[(sign*.074,-.091,1.28),(sign*.074,-.072,1.314),
            (sign*.072,-.025,1.343),(sign*.068,.025,1.339),(sign*.064,.065,1.305)],.018,terra)
        ribbon('CrossStrap.'+side,[(sign*.064,.065,1.305),(sign*.032,.079,1.23),
            (-sign*.012,.085,1.16),(-sign*.062,.079,1.095)],.021,terra,normal=(0,1,0))
        # Brass buttons and bib seams.
        button=B.oval('Button.'+side,(sign*.074,-.097,1.271),(.008,.0027,.008),brass,'chest',u=16,v=8)
        button['owner']=H.OWNER_TAG
        tube('BibEdge.'+side,[(sign*.086,-.102,1.094),(sign*.093,-.130,1.15),
             (sign*.099,-.135,1.22),(sign*.089,-.095,1.278)],.0018,terra_light,'chest')
        # Curved patch pockets laid on the apron surface.
        verts=[];faces=[]
        for j in range(5):
            z=.78+j*.12/4
            for k in range(7):
                x=sign*.11+(k/6-.5)*.080
                radius=.126+(.87-z)*.05
                y=-.014-radius*math.sqrt(max(.01,1-(x/(.16+(.87-z)*.16))**2))-.004
                verts.append((x,y,z))
        for j in range(4):
            for k in range(6):
                a=j*7+k;faces.append((a,a+1,a+8,a+7))
        mesh('Pocket.'+side,verts,faces,terra,'pelvis',thickness=.002)
        tube('PocketStitch.'+side,[verts[0],verts[6],verts[34],verts[28],verts[0]],.0013,terra_light,'pelvis')
    tube('BibTop',[(-.088,-.093,1.278),(0,-.099,1.278),(.088,-.093,1.278)],.0018,terra_light,'chest')
    for i in range(2):
        z=1.31+i*.025
        button=B.oval('BlouseButton%d'%i,(0,-.062,z),(.003,.002,.003),brass,'chest',u=12,v=6)
        button['owner']=H.OWNER_TAG
    bow=bpy.data.objects[P+'BowBlockout_LOD0'];bow.hide_render=True;bow.hide_set(True)
    knot=H.box(P+'BowKnot_LOD0',(.026,.021,.027),location=(0,-.139,1.079))
    H.bevel(knot,.004,3);finish(knot,terra,'pelvis')
    for sign,side in [(1,'L'),(-1,'R')]:
        ribbon('BowLoop.'+side,[(0,-.135,1.08),(sign*.033,-.148,1.090),
             (sign*.063,-.143,1.079),(sign*.052,-.144,1.054),(sign*.015,-.146,1.078)],.025,terra,'pelvis')
        ribbon('BowTail.'+side,[(sign*.009,-.144,1.069),(sign*.019,-.143,1.008),
             (sign*.030,-.147,.903)],.028,terra,'pelvis')
    # Sewn hem follows the same ellipse as the skirt.
    pts=[]
    for i in range(65):
        a=i*math.tau/64;pts.append((.194*math.cos(a),-.014+.134*math.sin(a),.562))
    tube('ApronHem',pts,.0018,terra_light,'pelvis')
    # Reproduce the edit actually performed in Blender, so a rebuild preserves the authored change.
    edits=json.loads((ROOT/'build/manual-scene-edits.json').read_text())
    ob=bpy.data.objects[edits['object']]
    median=sum(v.co.x for v in ob.data.vertices)/len(ob.data.vertices)
    for v in ob.data.vertices:
        v.co.x=median+(v.co.x-median)*edits['scale_x_about_median']
        v.co.y+=edits['translate_y_m']
    H.save_master(str(ROOT/'CH_Nagisa_master.blend'))
    print('SECONDARY FORMS SAVED')

if __name__=='__main__':build()
