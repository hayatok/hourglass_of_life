"""One continuous Nagisa bob surface, combed over the measured primary volume.

The old free curve/ribbon layout is intentionally not used. This is authored
geometry, not a finished groom acceptance. Reference-image ambiguity, hidden
scalp and cross-section depth remain inferred until rendered comparison.
"""
import math
from mathutils import Vector

# z, half-width, front depth, back depth, centreY. The approved r2 primary
# volumes in02_blockout.py are the dimensional guide; about2mm is reserved for
# the connected clump relief instead of letting strands float above that guide.
GUIDE=[
    (1.385,.100,.088,.098,.012),
    (1.405,.116,.104,.118,.003),
    (1.445,.132,.111,.136,-.005),
    (1.500,.132,.113,.140,-.010),
    (1.550,.120,.111,.130,-.010),
    (1.590,.098,.103,.111,-.008),
    (1.610,.085,.084,.092,-.004),
    (1.637,.049,.052,.053,-.004),
    (1.650,.002,.003,.003,-.004),
]

# A connected lower edge creates actual gaps BETWEEN bangs and the ear, not
# black holes between disconnected raised strands. Front tips/notches follow
# the front sheet; hidden back edge is inferred from the supplied bob mass.
LOWER=[
    (0,1.510),(.16,1.485),(.36,1.430),(.65,1.397),
    (1.10,1.391),(1.57,1.385),(2.15,1.396),(2.55,1.415),
    (2.92,1.475),(math.pi,1.510),(3.37,1.520),(3.60,1.447),
    (3.82,1.505),(4.15,1.530),(4.40,1.510),(4.67,1.482),
    (4.90,1.558),(5.15,1.570),(5.40,1.530),(5.64,1.448),
    (5.86,1.510),(6.05,1.535),(math.tau,1.510),
]


def build(H,make_mesh,profile,hair_material):
    def base(u,v):
        u=u%math.tau
        lower=profile(LOWER,u)
        z=lower+(1.650-lower)*v
        rx,front,back,cy=[profile([(row[0],row[index]) for row in GUIDE],z) for index in range(1,5)]
        # Combed paths sweep diagonally from the off-centre front part. Both
        # silhouette boundary and crown remain fixed to the actual guide.
        frontness=max(0,-math.sin(u))
        twist=(.10+.22*frontness)*math.sin(math.pi*v)
        angle=u+twist
        depth=front if math.sin(angle)<0 else back
        return Vector((rx*math.cos(angle),cy+depth*math.sin(angle),z))

    def point(u,v):
        p=base(u,v)
        du=base(u+.0005,v)-base(u-.0005,v)
        dv=base(u,min(.9999,v+.0005))-base(u,max(0,v-.0005))
        normal=du.cross(dv).normalized()
        # Connected shallow clump relief follows the combed flow. Nonuniform
        # phase gives varied broad bundles without a repeated row of petals.
        phase=11*u+.75*math.sin(2*u)+.28*math.sin(5*u)+.80*math.sin(math.pi*v)
        ridge=(.5+.5*math.cos(phase))**3
        crown_fade=min(1,max(0,(1-v)/.10))
        height=(.0030*ridge-.0012)*crown_fade
        # An actual shallow part in the upper-front surface, never an open gap.
        part=math.exp(-((p.x-.025)/.004)**2-((p.y+.020)/.060)**2)
        part*=max(0,min(1,(p.z-1.595)/.030))
        return p+normal*(height-.0018*part)

    columns,rows=96,26
    guide=[];verts=[];faces=[]
    for row in range(rows):
        v=row/rows
        for col in range(columns):
            u=math.tau*col/columns
            guide.append(base(u,v));verts.append(point(u,v))
    top=len(verts)
    guide.append(Vector((0,-.004,1.650)));verts.append(guide[-1].copy())
    for row in range(rows-1):
        for col in range(columns):
            nxt=(col+1)%columns
            faces.append([row*columns+col,row*columns+nxt,(row+1)*columns+nxt,(row+1)*columns+col])
    for col in range(columns):
        nxt=(col+1)%columns
        faces.append([(rows-1)*columns+col,(rows-1)*columns+nxt,top])

    guide_ob,_=make_mesh("HairVolumeGuide",guide,faces,hair_material,"hair_guide")
    for collection in list(guide_ob.users_collection):
        collection.objects.unlink(guide_ob)
    H.col("HIGH").objects.link(guide_ob)
    guide_ob.hide_render=True;guide_ob.hide_set(True)
    guide_ob["source"]="approved_r2_primary_volume_with_inferred_front_hairline"
    groom,_=make_mesh("HairCohesiveBob",verts,faces,hair_material,"head")
    H.solidify(groom,.004,offset=-1)
    groom["construction"]="one connected combed surface over dimensional volume guide; no floating ribbons"
    groom["render_acceptance"]="pending coloured front/profile/threequarter/fullbody"
    return groom,guide_ob
