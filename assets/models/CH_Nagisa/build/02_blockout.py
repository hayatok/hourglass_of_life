"""Primary forms in metres, calibrated to the authored front/side drawings.
Ring heights/widths follow ref/calibration.json; depth and hidden anatomy are inferred.
"""
import sys, math
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).parent))
import mesh_helpers as H
H.OWNER_TAG = 'phase:02_blockout'
ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'CH_Nagisa_'
PARTS = []

def material(name, color, roughness=.85, metallic=0):
    mat=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color=(*color,1)
    shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Roughness'].default_value=roughness
    shader.inputs['Metallic'].default_value=metallic
    return mat

def finish(ob, mat, bind='chest'):
    ob.data.materials.append(mat); ob['bind']=bind
    if ob.type=='MESH':
        for poly in ob.data.polygons:poly.use_smooth=True
    PARTS.append(ob)
    return ob

def rings(name, sections, mat, bind='chest', n=32, collection='LOW'):
    # (z, x radius, y radius, center x, center y). Defined by the view's contour stations.
    loops=[[(cx+rx*math.cos(a*math.tau/n),cy+ry*math.sin(a*math.tau/n),z)
            for a in range(n)] for z,rx,ry,cx,cy in sections]
    return finish(H.loft(PREFIX+name+'_LOD0',loops,collection=collection),mat,bind)

def tube(name, points, radii, mat, bind, n=20):
    loops=[]
    for i,(point,radius) in enumerate(zip(points,radii)):
        p=Vector(point)
        tangent=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        tangent.normalize()
        u=tangent.cross(Vector((0,1,0))).normalized(); v=tangent.cross(u).normalized()
        rx,ry=radius if isinstance(radius,tuple) else (radius,radius)
        loops.append([p+u*math.cos(a*math.tau/n)*rx+v*math.sin(a*math.tau/n)*ry for a in range(n)])
    return finish(H.loft(PREFIX+name+'_LOD0',loops),mat,bind)

def oval(name, loc, scale, mat, bind, u=24,v=12, collection='LOW'):
    return finish(H.sphere(PREFIX+name+'_LOD0',1,location=loc,scale=scale,u=u,v=v,collection=collection),mat,bind)

def build():
    H.open_master(str(ROOT/'CH_Nagisa_master.blend')); H.clear_owned()
    global SKIN,HAIR,BLOUSE,APRON,PANTS,SHOE,TRIM
    SKIN=material('Skin',(.78,.49,.31),.78)
    HAIR=material('Hair',(.045,.024,.018),.72)
    BLOUSE=material('Sage',(.27,.29,.14),.95)
    APRON=material('Terracotta',(.46,.14,.065),.95)
    PANTS=material('Ivory',(.76,.67,.49),.95)
    SHOE=material('Leather',(.10,.048,.022),.58)
    TRIM=material('Brass',(.63,.38,.10),.4,.7)

    # Body coverage is kept in HIGH; the visible neck is LOW. Anatomy under costume is inferred.
    body=rings('UnderlyingBody',[(.86,.115,.085,0,0),(.98,.11,.08,0,0),
        (1.09,.083,.062,0,0),(1.19,.112,.08,0,-.005),(1.29,.14,.065,0,0),
        (1.32,.09,.05,0,0)],SKIN,collection='HIGH')
    body.hide_render=True; body.hide_set(True)
    rings('Blouse',[(1.07,.087,.075,0,-.01),(1.105,.095,.087,0,-.01),
        (1.16,.106,.108,0,-.018),(1.22,.114,.105,0,-.021),(1.285,.139,.080,0,.004),
        (1.32,.125,.060,0,.004),(1.345,.047,.037,0,0)],BLOUSE)
    rings('Neck',[(1.305,.036,.033,0,0),(1.34,.035,.033,0,0),(1.402,.031,.031,0,0)],SKIN,'neck')
    rings('Head',[(1.385,.012,.021,0,-.031),(1.398,.045,.039,0,-.019),
        (1.42,.071,.060,0,-.007),(1.45,.087,.074,0,-.001),(1.485,.093,.085,0,.004),
        (1.52,.095,.087,0,.006),(1.56,.089,.081,0,.012),(1.60,.071,.065,0,.016),
        (1.626,.038,.041,0,.015),(1.635,.006,.01,0,.015)],SKIN,'head',n=48)
    oval('Nose',(0,-.090,1.467),(.012,.023,.018),SKIN,'head',u=16,v=8)
    # Hair primary envelope: back and sides surround the jaw; front opens at the brow.
    verts=[]; faces=[]; n=48
    hair_sections=[(1.397,.071,.085,.018),(1.425,.111,.111,.02),
        (1.47,.125,.125,.012),(1.52,.127,.128,.010),(1.57,.108,.123,.006),
        (1.61,.084,.094,.008),(1.64,.044,.05,.010),(1.65,.002,.004,.014)]
    for j,(z,rx,ry,cy) in enumerate(hair_sections):
        for i in range(n):
            a=math.tau*i/n
            zz=z
            # front half lower edge follows the fringe; sides retain bob length
            if math.sin(a)<-.30 and j<4:
                zz=max(z,1.538 + .018*math.cos(a))
            verts.append((rx*math.cos(a),cy+ry*math.sin(a),zz))
    for j in range(len(hair_sections)-1):
        for i in range(n): faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    mesh=bpy.data.meshes.new('BobEnvelope'); mesh.from_pydata(verts,[],faces); mesh.update()
    ob=bpy.data.objects.new(PREFIX+'Hair_LOD0',mesh); H.col('LOW').objects.link(ob); H.own(ob)
    for f in mesh.polygons:f.use_smooth=True
    finish(ob,HAIR,'head')
    for side,sign in [('L',1),('R',-1)]:
        oval('Ear.'+side,(sign*.094,.0,1.47),(.018,.015,.031),SKIN,'head')
        # Measured arm axis: shoulder px325/473,y205; elbow px300/498,y305; wrist px233/558,y420.
        shoulder=(sign*.123,0,1.30); elbow=(sign*.210,-.005,1.075); wrist=(sign*.312,-.012,.90)
        tube('Sleeve.'+side,[shoulder,(sign*.145,0,1.235),(sign*.180,-.003,1.16),elbow,
            (sign*.232,-.008,1.046)],[(.043,.051),(.043,.049),(.042,.044),(.040,.042),(.037,.040)],BLOUSE,'arm.'+side)
        tube('Cuff.'+side,[(sign*.221,-.007,1.071),(sign*.233,-.008,1.04)],[(.042,.045),(.04,.044)],BLOUSE,'arm.'+side)
        tube('Forearm.'+side,[(sign*.233,-.007,1.047),(sign*.267,-.01,.981),(sign*.300,-.014,.921),wrist],
            [.029,.026,.020,.017],SKIN,'forearm.'+side)
        tube('Palm.'+side,[wrist,(sign*.328,-.015,.87),(sign*.332,-.012,.841)],[(.017,.013),(.024,.014),(.020,.011)],SKIN,'hand.'+side,n=16)
        # Separate five fingers from the outset. Their exact depth/curvature is inferred.
        for f,(dx,length) in enumerate([(-.019,.045),(-.006,.068),(.007,.073),(.019,.064),(.029,.048)]):
            z=.87 if f==0 else .842
            x=sign*(.331+dx)
            tube('Finger%d.%s'%(f,side),[(x,-.012,z),(x+sign*.005,-.017,z-length*.5),
                (x+sign*.001,-.018,z-length),(x,-.017,z-length-.002)],
                [.007,.006,.005,.0015],SKIN,'hand.'+side,n=8)
        # Trouser leg behind the apron. Foot stance and hem height read from the front drawing.
        rings('Trousers.'+side,[(.177,.034,.038,sign*.068,0),(.22,.039,.043,sign*.069,0),
            (.30,.047,.047,sign*.068,.012),(.40,.059,.052,sign*.069,.018),(.50,.058,.057,sign*.069,.018),
            (.60,.060,.065,sign*.071,.012),(.76,.068,.07,sign*.068,.006),(.91,.070,.073,sign*.066,0)],PANTS,'leg.'+side)
        rings('TrouserCuff.'+side,[(.178,.041,.044,sign*.068,0),(.219,.044,.046,sign*.069,0),
            (.225,.041,.044,sign*.069,0)],PANTS,'shin.'+side)
        rings('Ankle.'+side,[(.065,.027,.028,sign*.069,0),(.105,.023,.026,sign*.069,0),
            (.185,.027,.027,sign*.068,0)],SKIN,'shin.'+side)
        rings('Shoe.'+side,[(.006,.042,.104,sign*.077,-.047),(.025,.045,.107,sign*.077,-.047),
            (.045,.044,.102,sign*.077,-.047),(.065,.035,.077,sign*.074,-.025),
            (.09,.028,.043,sign*.069,.004)],SHOE,'foot.'+side)
    # Full apron wrap: visible front and back drawings agree on a knee-length skirt.
    rings('ApronSkirt',[(.541,.174,.121,0,-.014),(.557,.194,.133,0,-.014),
        (.64,.191,.129,0,-.013),(.75,.18,.126,0,-.012),(.87,.161,.122,0,-.014),
        (.99,.129,.107,0,-.016),(1.07,.108,.091,0,-.019),(1.092,.088,.088,0,-.020)],APRON,'pelvis')
    # Bib is a fitted front patch, not a floating box.
    verts=[];faces=[]
    sections=[(1.087,.082,-.10),(1.15,.094,-.127),(1.22,.099,-.132),(1.279,.089,-.091)]
    for z,w,y in sections:
        for i in range(13):
            x=-w+2*w*i/12; verts.append((x,y+.018*(x/w)**2,z))
    for j in range(3):
        for i in range(12):faces.append((j*13+i,j*13+i+1,(j+1)*13+i+1,(j+1)*13+i))
    me=bpy.data.meshes.new('ApronBib'); me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new(PREFIX+'ApronBib_LOD0',me);H.col('LOW').objects.link(ob);H.own(ob)
    solid=ob.modifiers.new('Cloth thickness','SOLIDIFY');solid.thickness=.003
    finish(ob,APRON)
    rings('WaistTie',[(1.063,.092,.079,0,0),(1.093,.093,.079,0,0)],APRON,'pelvis')
    oval('BowBlockout',(0,-.128,1.065),(.074,.035,.027),APRON,'pelvis')
    H.save_master(str(ROOT/'CH_Nagisa_master.blend'))
    print('PRIMARY FORMS',len(PARTS))

if __name__=='__main__':build()
