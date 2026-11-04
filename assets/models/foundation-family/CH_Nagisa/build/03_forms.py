"""Nagisa face/hair forms, from the supplied registered front/profile.

Run after 02_blockout.py.  This first forms batch intentionally leaves the
clothing/hands at blockout quality: it is not a completed Phase 03 gate.
Metres, +Z up, -Y forward. Hidden scalp/back and section curvature are inferred.
No imported character geometry or existing runtime model is changed.
"""
from pathlib import Path
import sys
import math
import json
import bpy
import bmesh
from mathutils import Vector, Matrix

sys.path.insert(0, str(Path(__file__).parent))
import mesh_helpers as H

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "CH_Nagisa_Foundation_"
H.OWNER_TAG = "phase:03_forms_face_hair"
PARTS = []
FACE_X = 2 * 1.65 / 975  # front chin x320 versus registered body axis x318
EYE_X = .0381            # front pupil separation45px /2, rounded <0.1px
EYE_Z = 1.494            # front eye-centre y106–107
EYE_Y = -.080            # inferred globe centre, fitted behind measured lids
EYE_RADII = (.0265, .013, .0225)  # stylised ellipsoid depth is inferred
EYE_W = .0237            # front inner→outer28px/2
EYE_H = .0175            # opening excludes the measured ~2px upper/lower lid rim
MOUTH_Z = 1.432          # y143 source seam; profile smile differs by2px
MOUTH_W = .0212          # front corners25px/2

Z_ROWS = [1.340, 1.354, 1.370, 1.382, 1.388, 1.392, 1.396,
          1.401, 1.407, 1.413, 1.419, 1.424, 1.428, 1.431,
          1.434, 1.437, 1.440, 1.444, 1.449, 1.454, 1.459,
          1.464, 1.469, 1.474, 1.479, 1.484, 1.489, 1.494,
          1.499, 1.504, 1.509, 1.514, 1.519, 1.525, 1.532,
          1.540, 1.550, 1.560, 1.570, 1.580, 1.590, 1.600,
          1.610, 1.620, 1.630]
# Rectangular grid boundaries are remapped to almond/oval loops, then bridged
# to the surrounding quad face grid. The actual holes are absent faces, not
# black decals on a closed head. Anatomical L is +X, front image-right.
OPENINGS = [
    {"kind": "eye", "side": "R", "i0": 8, "i1": 20, "j0": 22, "j1": 32,
     "cx": FACE_X-EYE_X, "cz": EYE_Z, "w": EYE_W, "h": EYE_H},
    {"kind": "eye", "side": "L", "i0": 28, "i1": 40, "j0": 22, "j1": 32,
     "cx": FACE_X+EYE_X, "cz": EYE_Z, "w": EYE_W, "h": EYE_H},
    {"kind": "mouth", "side": "", "i0": 18, "i1": 30, "j0": 12, "j1": 16,
     "cx": FACE_X, "cz": MOUTH_Z, "w": MOUTH_W, "h": .0012},
]


def interp(points, value):
    if value <= points[0][0]:
        return points[0][1]
    for (a, av), (b, bv) in zip(points, points[1:]):
        if value <= b:
            t = (value-a)/(b-a)
            return av+(bv-av)*t
    return points[-1][1]


def smooth(value):
    value = max(0., min(1., value))
    return value*value*(3-2*value)


def profile(points,value):
    """C1 monotone Hermite profile through measured/inferred stations.

    Linear depth stations made a broad horizontal cheek plane at lip height.
    Smooth regional surface fields avoid that anatomical construction error.
    """
    if value<=points[0][0]:
        return points[0][1]
    if value>=points[-1][0]:
        return points[-1][1]
    spans=[b[0]-a[0] for a,b in zip(points,points[1:])]
    slopes=[(b[1]-a[1])/h for a,b,h in zip(points,points[1:],spans)]
    derivatives=[slopes[0]]
    for index in range(1,len(points)-1):
        before,after=slopes[index-1],slopes[index]
        if before*after<=0:
            derivatives.append(0.)
        else:
            w1=2*spans[index]+spans[index-1]
            w2=spans[index]+2*spans[index-1]
            derivatives.append((w1+w2)/(w1/before+w2/after))
    derivatives.append(slopes[-1])
    for index,((a,av),(b,bv)) in enumerate(zip(points,points[1:])):
        if value<=b:
            u=(value-a)/(b-a);h=b-a
            return ((2*u**3-3*u**2+1)*av+(u**3-2*u**2+u)*h*derivatives[index]
                    +(-2*u**3+3*u**2)*bv+(u**3-u**2)*h*derivatives[index+1])
    raise RuntimeError("profile range")


def mat(name, color, roughness=.8, metallic=0.):
    return H.material(PREFIX+name, (*color, 1), roughness=roughness, metallic=metallic)


def mesh(name, verts, faces, material, region, indices=None):
    used = sorted({index for face in faces for index in face})
    remap = {old: new for new, old in enumerate(used)}
    data = bpy.data.meshes.new(PREFIX+name+"_Mesh")
    data.from_pydata([verts[index] for index in used], [],
                     [[remap[index] for index in face] for face in faces])
    data.update()
    ob = bpy.data.objects.new(PREFIX+name+"_LOD0", data)
    H.col("LOW").objects.link(ob)
    H.own(ob)
    H.assign(ob, material)
    ob["region"] = region
    for face in data.polygons:
        face.use_smooth = True
    if indices:
        for old_name, selection in indices.items():
            group = ob.vertex_groups.new(name=old_name)
            group.add([remap[index] for index in selection if index in remap], 1, "REPLACE")
    PARTS.append(ob)
    return ob, remap


def radius(z):
    # Jaw width from front chin/jaw/cheek points; hidden skull/neck inferred.
    return profile([(1.34,.036),(1.37,.036),(1.382,.033),(1.388,.025),
                   (1.396,.022),(1.407,.045),(1.419,.062),(1.440,.074),
                   (1.46,.080),(1.49,.084),(1.53,.086),(1.57,.082),
                   (1.60,.069),(1.62,.038),(1.63,.009)], z)


def face_y(x, z):
    # Reference profile nose/lips/chin are fitted by a continuous depth field;
    # the nose is part of the cheek/jaw mesh rather than an attached sphere.
    base = profile([(1.34,-.057),(1.37,-.056),(1.388,-.063),(1.396,-.0846),
                   (1.413,-.090),(1.426,-.091),(1.438,-.091),
                   (1.450,-.091),(1.460,-.091),(1.480,-.094),
                   (1.500,-.096),(1.530,-.100),(1.56,-.091),
                   (1.59,-.070),(1.62,-.042),(1.63,-.016)], z)
    lateral = (x-FACE_X)/max(.015, radius(z))
    curve = .055*abs(lateral)**2.1 * smooth((z-1.38)/.05)
    nose = -.0265*math.exp(-((x-FACE_X)/.0095)**2-((z-1.460)/.016)**2)
    bridge = -.006*math.exp(-((x-FACE_X)/.0075)**2-((z-1.483)/.025)**2)
    wings = -.0035*math.exp(-((abs(x-FACE_X)-.008)/.005)**2-((z-1.453)/.005)**2)
    cheek = -.0060*math.exp(-((abs(x-FACE_X)-.051)/.023)**2-((z-1.458)/.027)**2)
    muzzle = -.0135*math.exp(-((x-FACE_X)/.028)**2-((z-MOUTH_Z)/.0135)**2)
    return base+curve+nose+bridge+wings+cheek+muzzle


def globe_front(x, z, cx):
    rx, ry, rz = EYE_RADII
    radial = 1-((x-cx)/rx)**2-((z-EYE_Z)/rz)**2
    return EYE_Y-ry*math.sqrt(max(.025, radial))


def opening_metric(i, j, opening):
    ci, cj = (opening["i0"]+opening["i1"])/2, (opening["j0"]+opening["j1"])/2
    u = (i-ci)/((opening["i1"]-opening["i0"])/2)
    v = (j-cj)/((opening["j1"]-opening["j0"])/2)
    return max(abs(u), abs(v)), u, v


def face_point(i, j):
    z = Z_ROWS[j]
    x = FACE_X+(i-24)/24*radius(z)
    options = [(opening_metric(i, j, opening), opening) for opening in OPENINGS]
    (q, u, v), opening = min(options, key=lambda item: item[0][0])
    if .9999 <= q < 1.75:
        theta = math.atan2(v, u)
        co, si = math.cos(theta), math.sin(theta)
        taper = abs(si)**(.35 if si>=0 else .65) if opening["kind"] == "eye" else 1.
        target_x = opening["cx"]+opening["w"]*co*q
        target_z = opening["cz"]+opening["h"]*si*q*taper
        if opening["kind"] == "eye":
            # Source outer corners rise very slightly; remains inside2px error.
            target_z += .0015*co*(1 if opening["side"] == "L" else -1)
        else:
            target_z += .0034*co*co  # source cornersy141/seam143:2px smile rise
        blend = smooth((1.75-q)/.75)
        x += (target_x-x)*blend
        z += (target_z-z)*blend
    y = face_y(x, z)
    if opening["kind"] == "eye" and .9999 <= q < 1.30:
        blend = smooth((1.30-q)/.30)
        fitted = globe_front(x, z, opening["cx"])-.0008
        y += (fitted-y)*blend
    # The globe's non-visible covered section is cut at the aperture below;
    # no inflated orbital dome is required to hide an intersecting white ball.
    return (x, y, z)


def rect_loop(opening):
    i0,i1,j0,j1 = (opening[key] for key in ("i0","i1","j0","j1"))
    return ([(i,j0) for i in range(i0,i1)] +
            [(i1,j) for j in range(j0,j1)] +
            [(i,j1) for i in range(i1,i0,-1)] +
            [(i0,j) for j in range(j1,j0,-1)])


def make_head(skin, lip, cavity):
    verts, faces, lookup = [], [], {}
    for j in range(len(Z_ROWS)):
        for i in range(49):
            lookup[i,j] = len(verts)
            verts.append(face_point(i,j))
    for j in range(len(Z_ROWS)-1):
        for i in range(48):
            if any(o["i0"] <= i < o["i1"] and o["j0"] <= j < o["j1"] for o in OPENINGS):
                continue
            faces.append([lookup[i,j],lookup[i+1,j],lookup[i+1,j+1],lookup[i,j+1]])
    # The back semicircle shares the face's side boundaries. This yields one
    # connected cheek/jaw/skull/neck skin shell, not overlapping head spheres.
    rings=[]
    for j,z in enumerate(Z_ROWS):
        ring=[lookup[i,j] for i in range(49)]
        ry=interp([(1.34,.030),(1.38,.038),(1.40,.052),(1.45,.083),
                   (1.50,.100),(1.55,.100),(1.59,.080),(1.63,.010)],z)
        for step in range(1,24):
            theta=math.pi*step/24
            edge_y=verts[lookup[48,j]][1]
            ring.append(len(verts))
            verts.append((FACE_X+radius(z)*math.cos(theta),
                          edge_y+(ry-edge_y)*math.sin(theta),z))
        rings.append(ring)
    for bottom,top in zip(rings,rings[1:]):
        for index in range(48,len(bottom)):
            nxt=(index+1)%len(bottom)
            faces.append([bottom[index],bottom[nxt],top[nxt],top[index]])
    faces += [list(reversed(rings[0])),rings[-1]]
    groups={"opening_"+o["kind"]+o["side"]:[lookup[p] for p in rect_loop(o)] for o in OPENINGS}
    ob,remap=mesh("SkinHeadNeck",verts,faces,skin,"head",groups)
    # Real mouth cavity behind the opening, with a recessed dark backing.
    mouth=OPENINGS[-1]
    boundary=[Vector(verts[lookup[p]]) for p in rect_loop(mouth)]
    inner=[Vector((p.x, p.y+.009, MOUTH_Z+(p.z-MOUTH_Z)*.8)) for p in boundary]
    cavity_faces=[]
    for k in range(len(boundary)):
        nxt=(k+1)%len(boundary)
        cavity_faces.append([k,nxt,nxt+len(boundary),k+len(boundary)])
    cavity_faces.append(list(range(len(boundary),len(boundary)*2)))
    mesh("MouthInterior",boundary+inner,cavity_faces,cavity,"head")
    # Blink closes the actual upper/lower boundary over the unscaled eyeball.
    basis=ob.shape_key_add(name="Basis")
    basis.value=0
    blink=ob.shape_key_add(name="Blink")
    # Blender5 initializes newly added keys at1; explicitly leave neutral open
    # eyes as the saved rest state instead of accidentally reviewing Blink.
    blink.value=0
    for (i,j),old in lookup.items():
        if old not in remap:
            continue
        for eye in OPENINGS[:2]:
            q,u,v=opening_metric(i,j,eye)
            if .9999<=q<1.8:
                point=blink.data[remap[old]].co
                blend=smooth((1.8-q)/.8)
                seam=EYE_Z+.0015*(point.x-eye["cx"])/EYE_W*(1 if eye["side"]=="L" else -1)
                point.z+=(seam-point.z)*blend
                point.y+=(globe_front(point.x,point.z,eye["cx"])-.0030-point.y)*blend
                radial=1-((point.x-eye["cx"])/EYE_RADII[0])**2-((point.z-EYE_Z)/EYE_RADII[2])**2
                if radial>0:
                    point.y=min(point.y,globe_front(point.x,point.z,eye["cx"])-.0030)
    subdiv=ob.modifiers.new("FaceSubdivisionForms", "SUBSURF")
    subdiv.levels=1;subdiv.render_levels=1
    # Thin lip geometry follows the opening instead of assigning a rectangular
    # pink region to coarse face-grid polygons.
    lip_verts=[];lip_faces=[]
    for k in range(64):
        a=math.tau*k/64;co=math.cos(a);si=math.sin(a)
        for margin in [0,.0012]:
            x=FACE_X+(MOUTH_W+margin)*co
            z=MOUTH_Z+(.0012+margin*.7)*si+.0034*co*co
            lip_verts.append((x,face_y(x,z)-.0008,z))
    for k in range(64):
        n=(k+1)%64
        lip_faces.append([2*k,2*n,2*n+1,2*k+1])
    mesh("LipMargin",lip_verts,lip_faces,lip,"head")
    return ob


def sphere(name, centre, radii, material):
    ob=H.sphere(PREFIX+name+"_LOD0",1,location=centre,scale=radii,u=32,v=20)
    H.assign(ob,material);ob["region"]="head";PARTS.append(ob)
    for poly in ob.data.polygons:
        poly.use_smooth=True
    return ob


def make_eyes(white, iris, iris_rim, pupil, highlight, lash, head):
    bpy.context.view_layer.update()
    evaluated=head.evaluated_get(bpy.context.evaluated_depsgraph_get())
    for eye in OPENINGS[:2]:
        cx=eye["cx"];side=eye["side"]
        # Retain the real ellipsoid's visible front section inside the fixed
        # almond opening. Its covered sides/back are not exported as a white
        # sphere protruding through the orbital skin. This coverage cut is
        # identical in open/Blink states; closure must come from the real lids.
        vs=[(cx,globe_front(cx,EYE_Z,cx),EYE_Z)];fs=[]
        for rstep in range(1,9):
            r=rstep/8
            for k in range(64):
                a=math.tau*k/64;co=math.cos(a);si=math.sin(a)
                x=cx+EYE_W*co*r
                taper=abs(si)**(.35 if si>=0 else .65)
                z=EYE_Z+EYE_H*si*taper*r+.0015*co*r*(1 if side=="L" else -1)
                vs.append((x,globe_front(x,z,cx),z))
        for k in range(64):
            fs.append([0,1+k,1+(k+1)%64])
        for ring in range(7):
            for k in range(64):
                a=1+ring*64+k;b=1+ring*64+(k+1)%64
                fs.append([a,b,b+64,a+64])
        mesh("EyeGlobeFront."+side,vs,fs,white,"head")
        # All iris vertices lie on the actual ellipsoid surface plus0.15mm.
        # This is curved geometry, not a front billboard/painted eye marker.
        for name,rx,rz,offset,material in [
            ("IrisRim",.0114,.0179,.00014,iris_rim),
            ("Iris",.0106,.0172,.00025,iris),
            ("Pupil",.0045,.0088,.00040,pupil),
        ]:
            vs=[(cx,globe_front(cx,EYE_Z,cx)-offset,EYE_Z)]
            fs=[]
            for rstep in range(1,5):
                for step in range(40):
                    a=math.tau*step/40
                    x=cx+rx*(rstep/4)*math.cos(a)
                    z=EYE_Z+rz*(rstep/4)*math.sin(a)
                    vs.append((x,globe_front(x,z,cx)-offset,z))
            for k in range(40):
                fs.append([0,1+k,1+(k+1)%40])
            for ring in range(3):
                for k in range(40):
                    a=1+ring*40+k;b=1+ring*40+(k+1)%40
                    fs.append([a,b,b+40,a+40])
            mesh(name+"."+side,vs,fs,material,"head")
        sphere("EyeCatchlight."+side,(cx-.0035,globe_front(cx-.0035,EYE_Z+.006,cx)-.0006,EYE_Z+.006),
               (.0027,.00045,.0032),highlight)
        # Upper lashes follow the same real lid opening; lower lid stays skin.
        vs=[]
        for k in range(25):
            a=math.pi*k/24
            sign=1 if side=="L" else -1
            wing=max(0,math.cos(a)*sign)**10
            x=cx+EYE_W*math.cos(a)+sign*.0025*wing
            z=EYE_Z+EYE_H*math.sin(a)*abs(math.sin(a))**.35
            z+=.0015*math.cos(a)*sign+.0010*wing
            width=.0010+.0020*math.sin(a)
            for dz in [0,width]:
                zz=z+dz
                hit,position,normal,_=evaluated.ray_cast(Vector((x,-.5,zz)),Vector((0,1,0)))
                yy=position.y if hit else globe_front(x,zz,cx)-.0008
                vs.append((x,yy-.0004,zz))
        lash_ob,_=mesh("UpperLash."+side,vs,[[2*k,2*k+1,2*k+3,2*k+2] for k in range(24)],lash,"head")
        lash_ob.shape_key_add(name="Basis").value=0
        lash_blink=lash_ob.shape_key_add(name="Blink");lash_blink.value=0
        head.data.shape_keys.key_blocks["Blink"].value=1
        bpy.context.view_layer.update()
        closed=head.evaluated_get(bpy.context.evaluated_depsgraph_get())
        for k in range(25):
            a=math.pi*k/24;co=math.cos(a);si=math.sin(a)
            sign=1 if side=="L" else -1
            wing=max(0,co*sign)**10
            x=cx+EYE_W*co+sign*.0025*wing
            seam=EYE_Z+.0015*co*(1 if side=="L" else -1)-.0010*si
            seam+=.0010*wing
            width=.0010+.0020*si
            for edge in range(2):
                zz=seam+width*(edge-.5)
                hit,position,normal,_=closed.ray_cast(Vector((x,-.5,zz)),Vector((0,1,0)))
                yy=position.y if hit else globe_front(x,zz,cx)-.0030
                lash_blink.data[2*k+edge].co=(x,yy-.0004,zz)
        head.data.shape_keys.key_blocks["Blink"].value=0
        bpy.context.view_layer.update()
        evaluated=head.evaluated_get(bpy.context.evaluated_depsgraph_get())


def station_curve(points,t):
    # Interpolate measured/inferred silhouette stations, rather than using
    # them as Bezier handles (which would shrink the bob's outer envelope).
    segment=min(len(points)-2,int(t*(len(points)-1)))
    u=t*(len(points)-1)-segment
    p0=Vector(points[max(0,segment-1)])
    p1=Vector(points[segment]);p2=Vector(points[segment+1])
    p3=Vector(points[min(len(points)-1,segment+2)])
    m1=(p2-p0)*.35;m2=(p3-p1)*.35
    return (2*u**3-3*u**2+1)*p1+(u**3-2*u**2+u)*m1+(-2*u**3+3*u**2)*p2+(u**3-u**2)*m2


def ribbon(name,points,widths,material,thickness=.006,steps=22,cross=12):
    # Closed lenticular section, not a planar card. Its wide tangent is derived
    # from the scalp's outward normal so the strand overlaps the underlayer.
    verts=[];faces=[]
    for k in range(steps+1):
        t=k/steps
        centre=station_curve(points,t)
        tangent=(station_curve(points,min(1,t+.002))-station_curve(points,max(0,t-.002))).normalized()
        outward=Vector((centre.x-FACE_X,centre.y-.005,(centre.z-1.49)*.65)).normalized()
        axis=tangent.cross(outward).normalized()
        normal=axis.cross(tangent).normalized()
        if normal.dot(outward)<0:
            normal=-normal
        width=interp(widths,t)
        depth=thickness*max(.18,math.sin(math.pi*(.05+.9*t))**.5)
        for n in range(cross):
            a=math.tau*n/cross
            verts.append(centre+axis*(width*.5*math.cos(a))+normal*(depth*.5*math.sin(a)))
    for k in range(steps):
        for n in range(cross):
            nxt=(n+1)%cross
            faces.append([k*cross+n,(k+1)*cross+n,(k+1)*cross+nxt,k*cross+nxt])
    faces += [list(range(cross)),list(reversed(range(steps*cross,(steps+1)*cross)))]
    return mesh(name,verts,faces,material,"head")[0]


def make_brows(material):
    # Anatomical side follows published source landmark convention.
    for side,sign in [("L",1),("R",-1)]:
        xs=[FACE_X+sign*.025,FACE_X+sign*.042,FACE_X+sign*.061]
        zs=[1.527,1.532,1.525]
        points=[(x,face_y(x,z)-.0012,z) for x,z in zip(xs,zs)]
        ribbon("Brow."+side,points,[(0,.0023),(.4,.0048),(1,.0006)],material,.0014,steps=16,cross=6)


def make_ears(skin, inner):
    # A real oblique3D helix/concha, not a front-facing oval that disappears in
    # profile. Front/profile inner-ear landmarks fix centre; hidden back inferred.
    for side,sign in [("L",1),("R",-1)]:
        centre=Vector((FACE_X+sign*.078,-.017,1.468))
        angle=math.radians(50)
        tangent=Vector((sign*math.cos(angle),math.sin(angle),0))
        normal=Vector((sign*math.sin(angle),-math.cos(angle),0))
        verts=[];faces=[]
        sections=[(.015,.026,0),(.012,.023,.002),(.009,.019,-.004),(.004,.010,-.006)]
        for ring,(rx,rz,depth) in enumerate(sections):
            for n in range(24):
                a=math.tau*n/24
                verts.append(centre+tangent*(rx*math.cos(a))+Vector((0,0,rz*math.sin(a)))+normal*depth)
        for ring in range(3):
            for n in range(24):
                nxt=(n+1)%24
                faces.append([ring*24+n,ring*24+nxt,(ring+1)*24+nxt,(ring+1)*24+n])
        faces.append(list(range(72,96)))
        for n in range(24):
            a=math.tau*n/24
            verts.append(centre+tangent*(.015*math.cos(a))+Vector((0,0,.026*math.sin(a)))-normal*.006)
        for n in range(24):
            nxt=(n+1)%24
            faces.append([n,96+n,96+nxt,nxt])
        faces.append(list(reversed(range(96,120))))
        if sign<0:
            faces=[list(reversed(face)) for face in faces]
        ob,_=mesh("Ear."+side,verts,faces,skin,"head")
        ob.data.materials.append(inner)
        for poly in list(ob.data.polygons)[24:73]:
            poly.material_index=1


def make_hair(hair, warm, dark, gold):
    # All major hair is one connected volume-guided surface. The former free
    # ribbons/scalp shells are removed rather than hidden under more strips.
    import hair_volume
    groom,guide=hair_volume.build(H,mesh,profile,hair)
    bpy.context.view_layer.update()
    evaluated=groom.evaluated_get(bpy.context.evaluated_depsgraph_get())
    points=[]
    # Front source clip centreline (363,80),(368,75),(373,69), measured on
    # review/hairclip-reference-grid.png. Depth comes from the actual groom.
    for source_x,source_y in [(363,80),(368,75),(373,69)]:
        x=(source_x-318)*1.65/975
        z=(989-source_y)*1.65/975
        hit,position,normal,_=evaluated.ray_cast(Vector((x,-.5,z)),Vector((0,1,0)))
        if not hit:
            raise RuntimeError("Reference hair clip is outside the actual cohesive hair surface")
        points.append(position+normal*.0015)
    ribbon("HairClip",points,[(0,.011),(1,.011)],gold,.0025,steps=8,cross=8)


def hide_blockout_replacements():
    replaced=[]
    tokens=["Head_","Nose_","Ear.","EyeMass.","BobBackSides_","BobCrown_","Neck_"]
    for ob in bpy.data.objects:
        if ob.get("owner")=="phase:02_blockout_foundation" and any(token in ob.name for token in tokens):
            ob.hide_render=True
            ob.hide_set(True)
            ob["superseded_by"]="phase:03_forms_face_hair"
            replaced.append(ob.name)
    return replaced


def mouth_entry(head):
    """Measure the actual evaluated lip opening; no generic head-Y offset.

    This first candidate has no armature yet. The exported socket will become
    a DEF-head child in the rig phase; later lip morphs require derived anchor
    deltas rather than assuming that an Empty follows vertex deformation.
    """
    bpy.context.view_layer.update()
    evaluated=head.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data=evaluated.to_mesh()
    bm=bmesh.new();bm.from_mesh(data)
    boundary={edge for edge in bm.edges if edge.is_boundary}
    loops=[]
    while boundary:
        first=next(iter(boundary));current=first.verts[0];start=current
        points=[];previous=None
        while True:
            points.append(head.matrix_world@current.co)
            options=[edge for edge in current.link_edges if edge in boundary and edge is not previous]
            if not options:
                raise RuntimeError("Lip/eye boundary is not a closed contour")
            edge=options[0];boundary.remove(edge)
            current=edge.other_vert(current);previous=edge
            if current is start:
                break
        loops.append(points)
    mouth=min(loops,key=lambda points:abs(sum(p.z for p in points)/len(points)-MOUTH_Z))
    average=sum(mouth,Vector())/len(mouth)
    if abs(average.z-MOUTH_Z)>.01:
        raise RuntimeError("Could not identify the actual lip-opening contour")
    normal=sum(((a-average).cross(b-average) for a,b in zip(mouth,mouth[1:]+mouth[:1])),Vector()).normalized()
    if normal.dot(Vector((0,-1,0)))<0:
        normal=-normal
    area=0.;centroid=Vector()
    origin=mouth[0]
    for a,b in zip(mouth[1:-1],mouth[2:]):
        weight=(a-origin).cross(b-origin).dot(normal)/2
        centroid+=(origin+a+b)/3*weight;area+=weight
    if abs(area)<1e-9:
        raise RuntimeError("Actual lip opening has no measurable area")
    centroid/=area
    inward=-normal
    up=Vector((0,0,1));up=(up-inward*up.dot(inward)).normalized()
    right=up.cross(inward).normalized();up=inward.cross(right).normalized()
    matrix=Matrix((right,up,inward)).transposed().to_4x4();matrix.translation=centroid
    marker=bpy.data.objects.new("SOCKET_MouthEntry",None)
    H.col("SOCKETS").objects.link(marker);H.own(marker)
    marker.matrix_world=matrix;marker.empty_display_type="ARROWS";marker.empty_display_size=.035
    marker["source"]="actual_evaluated_lip_opening_area_centroid_and_contour_normal"
    marker["axes"]="local +Z inward, local +Y bowl up"
    marker["bind_bone"]="DEF-head"
    marker["bind_status"]="pending_rig_phase_not_runtime_connected"
    marker["morph_follow"]="Blink does not move mouth; future lip morphs require measured anchor deltas"
    report={"name":marker.name,"source":marker["source"],"opening_vertices":len(mouth),
            "opening_area_m2":abs(area),"blender_position_m":list(centroid),
            "blender_inward_normal":list(inward),"blender_bowl_up":list(up),
            "godot_position_after_export_m":[centroid.x,centroid.z,-centroid.y],
            "axes":"local +Z into mouth, local +Y bowl up; exporter converts world basis",
            "bind_bone":"DEF-head","bind_status":marker["bind_status"],
            "morph_follow":marker["morph_follow"],"runtime_exported":False}
    bm.free();evaluated.to_mesh_clear()
    return report


def build():
    H.open_master(str(ROOT/"CH_Nagisa_master.blend"))
    H.clear_owned()
    replaced=hide_blockout_replacements()
    # Warm peach albedo from the reference's skin role, shared with exposed
    # blockout arms for a coherent coloured whole-body review. Not baked light.
    skin=mat("SkinForms",(.92,.64,.43),.76)
    mat("Skin",(.92,.64,.43),.78)
    lip=mat("LipForms",(.78,.49,.39),.78)
    cavity=mat("MouthCavity",(.12,.025,.022),.9)
    white=mat("EyeWhite",(.92,.87,.73),.40)
    iris=mat("IrisAmber",(.25,.102,.024),.42)
    # Original authored iris gradient; bake this into the eventual unique UV
    # atlas. It is not an imported face texture or a substitute for lid shape.
    nodes=iris.node_tree.nodes;links=iris.node_tree.links
    for node in list(nodes):
        if node.type not in {"BSDF_PRINCIPLED","OUTPUT_MATERIAL"}:
            nodes.remove(node)
    coord=nodes.new("ShaderNodeTexCoord")
    separate=nodes.new("ShaderNodeSeparateXYZ")
    ramp=nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position=0
    ramp.color_ramp.elements[0].color=(.48,.225,.052,1)
    ramp.color_ramp.elements[1].position=1
    ramp.color_ramp.elements[1].color=(.038,.012,.006,1)
    middle=ramp.color_ramp.elements.new(.45);middle.color=(.25,.095,.018,1)
    links.new(coord.outputs["Generated"],separate.inputs[0])
    links.new(separate.outputs["Z"],ramp.inputs[0])
    links.new(ramp.outputs["Color"],nodes.get("Principled BSDF").inputs["Base Color"])
    iris_rim=mat("IrisLimbalRim",(.055,.020,.008),.56)
    pupil=mat("Pupil",(.025,.012,.009),.42)
    highlight=mat("EyeHighlight",(1.,.98,.86),.22)
    brow=mat("BrowForms",(.095,.038,.018),.78)
    lash=mat("LashForms",(.025,.012,.008),.78)
    hair=mat("ChestnutForms",(.20,.078,.029),.55)
    warm=mat("ChestnutWarm",(.235,.100,.040),.58)
    dark=mat("ChestnutUnderlayer",(.13,.043,.018),.62)
    gold=mat("HairClipGold",(.61,.35,.085),.38,.65)
    head=make_head(skin,lip,cavity)
    make_eyes(white,iris,iris_rim,pupil,highlight,lash,head)
    make_brows(brow)
    make_ears(skin,lip)
    make_hair(hair,warm,dark,gold)
    socket=mouth_entry(head)
    bpy.context.scene["forms_batch"]="face_hair_first_draft_not_accepted"
    H.save_master(str(ROOT/"CH_Nagisa_master.blend"))
    summary={"phase":"03_forms_face_hair_first_draft", "accepted":False,
             "superseded_blockout":replaced,"parts":[ob.name for ob in PARTS],
             "reference":"ref/face-landmarks.json", "heads":6.5,"height_m":1.65,
             "mouth_entry":socket,
             "authored":"connected cheek/nose/jaw/neck, real eye/mouth openings, fitted lids, curved iris geometry, cavity, blink and closed clumps",
             "inferred":"hidden skull/ear back, globe depth, face cross-section, clump thickness and hidden scalp",
             "pending":["256px face front/profile/three-quarter clay and material", "normals and opening topology inspection", "full silhouette and gameplay comparison", "hands/clothes forms remain blockout", "rig/weights/morph export not run"]}
    (ROOT/"review/forms-face-hair-build.json").write_text(json.dumps(summary,indent=2)+"\n")
    print("FORMS FACE/HAIR",len(PARTS),"parts; render acceptance pending")


if __name__=="__main__":
    build()
