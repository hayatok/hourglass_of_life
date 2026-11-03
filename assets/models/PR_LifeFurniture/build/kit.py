"""Original furniture construction, canonical metres / Z up / -Y front.
Dimensions and hidden construction are inferred in asset-brief.md. Perspective concepts
guide form and color; they are not used as orthographic measurements.
"""
import sys,math,json,importlib.util,os
from pathlib import Path
import bpy,bmesh,numpy as np
from mathutils import Matrix
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'CH_Nagisa/build'))
import mesh_helpers as H
SKILL=Path(os.environ.get('BLENDER_ASSET_SKILL',str(Path.home()/'.codex/skills/blender-image-to-3d')))
NAMES=['Bench','Chair','RoundTable','Worktable','Bed','Footstool','Radio','TownModel','BreadPlate','Mug']
CURRENT=None
DETAIL=False

def material(name,color,rough=.8,metal=0):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    sh=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    sh.inputs['Base Color'].default_value=(*color,1);sh.inputs['Roughness'].default_value=rough
    sh.inputs['Metallic'].default_value=metal
    return m

def finish(ob,mat):
    ob.parent=CURRENT;ob.data.materials.append(mat)
    if ob.type=='MESH':
        for p in ob.data.polygons:p.use_smooth=True
    return H.own(ob)

def box(name,size,loc,mat,bevel=.01,rotation=(0,0,0)):
    ob=H.box(CURRENT.name+'_'+name,size,location=loc,rotation=rotation)
    if DETAIL and bevel:H.bevel(ob,bevel,2)
    return finish(ob,mat)

def cylinder(name,radius,height,loc,mat,axis='Z',segments=24):
    ob=H.cylinder(CURRENT.name+'_'+name,radius,height,location=loc,axis=axis,segments=segments)
    if DETAIL:H.bevel(ob,min(.007,height*.15),2)
    return finish(ob,mat)

def sphere(name,loc,scale,mat):
    return finish(H.sphere(CURRENT.name+'_'+name,1,location=loc,scale=scale,u=20,v=10),mat)

def bar(name,points,radius,mat):
    return finish(H.curve_tube(CURRENT.name+'_'+name,points,radius,resolution=3,bevel_res=2),mat)

def bench():
    for s in [-1,1]:
        x=s*.83
        for y in [-.23,.23]:
            box('Leg',(.065,.075,.43),(x,y,.215),TEAL,.012,rotation=(0,s*.06,0))
        box('SeatRail',(.08,.62,.07),(x,0,.40),TEAL)
        bar('BackPost',[(x,.23,.10),(x,.25,.67),(x,.30,1.02)],.034,TEAL)
        bar('Arm',[(x,-.27,.44),(x,-.29,.64),(x,.18,.66),(x,.29,.72)],.037,TEAL)
    for i in range(5):box('SeatSlat%02d'%i,(1.72,.103,.055),(0,-.244+i*.122,.4325),WOOD,.012)
    for i in range(3):
        z=.655+i*.145;box('BackSlat%02d'%i,(1.72,.058,.12),(0,.29,z),WOOD,.014)
        if DETAIL:
            for s in [-1,1]:cylinder('Bolt',.014,.006,(s*.76,.256,z),BRASS,'Y',12)

def chair():
    for x in [-.18,.18]:
        for y in [-.18,.18]:
            box('Leg',(.045,.045,.43),(x*1.12,y*1.12,.215),TEAL,.008,rotation=(y*.3,-x*.3,0))
    cylinder('Seat',.255,.055,(0,0,.4325),WOOD,segments=32)
    for x in [-.19,.19]:bar('BackUpright',[(x,.18,.42),(x,.20,.76),(x*.75,.22,1.01)],.023,TEAL)
    arc=[(.21*math.cos(a),.22,.81+.23*math.sin(a)) for a in np.linspace(0,math.pi,17)]
    bar('BackArch',arc,.024,TEAL)
    for x in [-.115,0,.115]:bar('Spindle',[(x,.205,.47),(x,.22,.81+.21*math.sqrt(1-(x/.21)**2))],.012,TEAL)
    for x in [-.2,.2]:bar('SideBrace',[(x,-.2,.20),(x,.2,.20)],.012,TEAL)

def round_table():
    cylinder('Top',.55,.065,(0,0,.7275),WOOD,segments=48)
    cylinder('Column',.045,.65,(0,0,.36),DARK)
    for i in range(4):
        a=i*math.pi/2;c=math.cos(a);s=math.sin(a)
        bar('Foot',[(0,0,.11),(.18*c,.18*s,.04),(.37*c,.37*s,.035)],.026,DARK)

def worktable():
    box('Top',(1.55,.84,.08),(0,0,.91),WOOD,.025)
    for x in [-.65,.65]:
        for y in [-.31,.31]:box('Leg',(.10,.10,.87),(x,y,.435),TIMBER,.01)
    for y in [-.31,.31]:box('Apron',(1.35,.07,.14),(0,y,.79),TIMBER)
    box('Shelf',(1.35,.63,.06),(0,0,.23),WOOD)
    if DETAIL:
        for x in [-.63,.63]:
            for y in [-.35,.35]:sphere('Bolt',(x,y,.81),(.013,.009,.013),BRASS)

def bed():
    for x in [-.41,.41]:
        for y in [-.85,.85]:box('Leg',(.09,.09,.34),(x,y,.17),TIMBER)
    box('Frame',(1.0,2.05,.18),(0,0,.31),TIMBER,.025)
    box('Mattress',(.94,1.98,.12),(0,0,.40),LINEN,.05)
    box('Pillow',(.67,.36,.12),(0,.72,.52),LINEN,.055)
    box('FoldedCover',(.96,.24,.075),(0,-.73,.495),SAGE,.028)
    box('Headboard',(1.0,.075,.55),(0,1.02,.55),WOOD,.025)
    if DETAIL:
        for x in [-.30,0,.30]:box('HeadboardPanel',(.26,.012,.30),(x,.975,.57),TIMBER,.015)

def footstool():
    box('LowerStep',(.48,.30,.12),(0,-.10,.06),TIMBER,.018)
    box('UpperStep',(.48,.23,.23),(0,.13,.115),WOOD,.018)

def radio():
    box('Shell',(.36,.13,.23),(0,0,.125),WOOD,.035)
    box('FrontPanel',(.318,.015,.18),(0,-.073,.125),LINEN,.016)
    box('Speaker',(.13,.012,.135),(-.075,-.084,.125),DARK,.014)
    box('Tuner',(.136,.013,.042),(.075,-.085,.175),SAGE,.004)
    for x in [.037,.112]:cylinder('Dial',.023,.017,(x,-.10,.09),BRASS,'Y',20)
    bar('Handle',[(-.13,0,.235),(-.12,0,.31),(.12,0,.31),(.13,0,.235)],.013,TIMBER)
    if DETAIL:
        for x in [-.12,-.095,-.07,-.045,-.02]:bar('Grille',[(x,-.093,.072),(x,-.093,.174)],.002,BRASS)
        box('TuningNeedle',(.003,.005,.025),(.061,-.095,.175),TERRA,.001)

def town_model():
    box('Plinth',(.55,.38,.035),(0,0,.018),WOOD,.02)
    box('Green',(.51,.34,.012),(0,0,.04),SAGE,.005)
    for i,(x,y,h) in enumerate([(-.16,.06,.12),(0,.07,.17),(.16,-.04,.11)]):
        box('House%d'%i,(.12,.12,h),(x,y,.05+h/2),LINEN,.003)
        # Simple original pitched roof, a clean six-vertex prism.
        verts=[(x-.077,y-.077,.05+h),(x+.077,y-.077,.05+h),(x,y-.077,.11+h),
               (x-.077,y+.077,.05+h),(x+.077,y+.077,.05+h),(x,y+.077,.11+h)]
        me=bpy.data.meshes.new('PitchedRoof');me.from_pydata(verts,[],[(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)])
        ob=bpy.data.objects.new(CURRENT.name+'_Roof%d'%i,me);H.col('LOW').objects.link(ob);finish(ob,ROOF if i==1 else TERRA)
    box('Path',(.035,.34,.014),(.07,0,.05),LINEN,.002)

def bread_plate():
    cylinder('Plate',.21,.018,(0,0,.012),LINEN,segments=40)
    for i,(x,y) in enumerate([(-.09,-.04),(.08,-.04),(0,.08)]):
        sphere('Bread%d'%i,(x,y,.069),(.075,.059,.049),CRUST)
        if DETAIL:
            for j in [-1,1]:bar('BreadScore',[(x-.043,y+j*.016,.098),(x,y+j*.016,.115),(x+.043,y+j*.016,.098)],.003,LINEN)

def mug():
    profile=[(.045,0),(.049,.008),(.057,.11),(.054,.115),(.049,.11),(.042,.014)]
    ob=H.profile_spin(CURRENT.name+'_Cup',profile,steps=32);finish(ob,SAGE)
    bar('Handle',[(.051,0,.09),(.098,0,.105),(.108,0,.04),(.052,0,.025)],.009,SAGE)

BUILDERS=[bench,chair,round_table,worktable,bed,footstool,radio,town_model,bread_plate,mug]

def initialize():
    spec=importlib.util.spec_from_file_location('init_prop',SKILL/'scripts/init_master.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    a=module.parse(['--out',str(ROOT/'PR_LifeFurniture_calibration.blend'),'--name','PR_LifeFurniture',
        '--height','1.05','--ref-extra',str(ROOT/'ref/props.png'),str(ROOT/'ref/rooms.png'),
        '--cell','2','--cam-elev','35','--cam-az','30','--cam-dist','5','--cam-lens','50'])
    module.main(a)

def build(detail):
    global CURRENT,DETAIL,TEAL,WOOD,TIMBER,DARK,BRASS,LINEN,SAGE,TERRA,ROOF,CRUST
    DETAIL=detail;H.open_master(str(ROOT/'PR_LifeFurniture_calibration.blend'))
    H.OWNER_TAG='phase:03_furniture' if detail else 'phase:02_furniture'
    TEAL=material('Painted teal',(.043,.19,.20));WOOD=material('Warm timber',(.48,.24,.075),.72)
    TIMBER=material('Timber edge',(.23,.09,.026),.8);DARK=material('Graphite',(.035,.04,.043),.68)
    BRASS=material('Brass',(.55,.33,.075),.38,.7);LINEN=material('Ivory',(.78,.70,.56),.88)
    SAGE=material('Sage',(.20,.29,.13),.84);TERRA=material('Terracotta',(.40,.105,.045),.82)
    ROOF=material('Roof blue',(.065,.12,.21),.84);CRUST=material('Bread crust',(.67,.29,.055),.95)
    for i,(name,builder) in enumerate(zip(NAMES,BUILDERS)):
        CURRENT=bpy.data.objects.new('PR_'+name,None);H.col('LOW').objects.link(CURRENT);H.own(CURRENT)
        builder();CURRENT.location=((i%5)*2.5,math.floor(i/5)*3.2,0)
    H.save_master(str(ROOT/('PR_LifeFurniture_forms.blend' if detail else 'PR_LifeFurniture_blockout.blend')))
    H.save_master(str(ROOT/'PR_LifeFurniture_master.blend'))

def srgb(v):return v*12.92 if v<=.0031308 else 1.055*v**(1/2.4)-.055

def export():
    H.open_master(str(ROOT/'PR_LifeFurniture_forms.blend'))
    mats=sorted({m.name:m for ob in H.col('LOW').objects if ob.type in ['MESH','CURVE'] for m in ob.data.materials}.values(),key=lambda m:m.name)
    palette=[];arrays=[np.ones((256,256,4),np.float32) for _ in range(3)];arrays[2][:,:,:3]=(.5,.5,1)
    for i,m in enumerate(mats):
        sh=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');color=list(sh.inputs['Base Color'].default_value)
        rough=sh.inputs['Roughness'].default_value;metal=sh.inputs['Metallic'].default_value
        palette.append({'name':m.name,'linear_color':color,'roughness':rough,'metallic':metal})
        x=i%8*32;y=i//8*32;arrays[0][y:y+32,x:x+32,:3]=[srgb(c) for c in color[:3]]
        arrays[1][y:y+32,x:x+32,:3]=(1,rough,metal)
    material=bpy.data.materials.new('PR_LifeFurniture_Palette');nodes=material.node_tree.nodes;links=material.node_tree.links
    sh=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');textures=[]
    for kind,arr in zip(['BaseColor','ORM','Normal'],arrays):
        path=ROOT/'textures'/('PR_LifeFurniture_'+kind+'.png')
        im=bpy.data.images.new(kind,width=256,height=256,alpha=True);im.colorspace_settings.name='Non-Color'
        im.pixels.foreach_set(arr.ravel());im.filepath_raw=str(path);im.file_format='PNG';im.save();bpy.data.images.remove(im)
        im=bpy.data.images.load(str(path),check_existing=False);im.colorspace_settings.name='sRGB' if kind=='BaseColor' else 'Non-Color'
        tex=nodes.new('ShaderNodeTexImage');tex.image=im;tex.interpolation='Closest';textures.append(tex)
    links.new(textures[0].outputs['Color'],sh.inputs['Base Color'])
    split=nodes.new('ShaderNodeSeparateColor');links.new(textures[1].outputs['Color'],split.inputs[0])
    links.new(split.outputs['Green'],sh.inputs['Roughness']);links.new(split.outputs['Blue'],sh.inputs['Metallic'])
    normal=nodes.new('ShaderNodeNormalMap');links.new(textures[2].outputs['Color'],normal.inputs['Color']);links.new(normal.outputs[0],sh.inputs['Normal'])
    indices={m.name:i for i,m in enumerate(mats)};manifest={'units':'metres','blender_up':'Z','blender_front':'-Y','engine_up':'Y','engine_front':'+Z',
        'source':'original perspective concepts and inferred construction; final art acceptance pending','models':{},'texture_contract':{'size':[256,256],
        'BaseColor':'sRGB','ORM':'Non-Color R=AO(1), G=roughness, B=metallic','Normal':'Non-Color OpenGL +Y neutral','palette':palette}}
    for name in NAMES:
        source=bpy.data.objects['PR_'+name];copies=[]
        for ob in source.children:
            copy=ob.copy();copy.data=ob.data.copy();H.col('EXPORT').objects.link(copy);copy.parent=None;copy.matrix_world=ob.matrix_local
            bpy.ops.object.select_all(action='DESELECT');copy.select_set(True);bpy.context.view_layer.objects.active=copy
            if copy.type=='CURVE':bpy.ops.object.convert(target='MESH')
            H.apply_all_modifiers(copy);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
            old=list(copy.data.materials);bm=bmesh.new();bm.from_mesh(copy.data)
            bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(copy.data);bm.free()
            uv=copy.data.uv_layers.new(name='PaletteUV');uv.active_render=True
            for poly in copy.data.polygons:
                slot=indices[old[poly.material_index].name];u=(slot%8+.5)/8;v=(slot//8+.5)/8
                for k,loop in enumerate(poly.loop_indices):uv.data[loop].uv=(u+[-.012,.012,0][k%3],v+[-.012,-.012,.012][k%3])
                poly.material_index=0
            copy.data.materials.clear();copy.data.materials.append(material);copies.append(copy)
        bpy.ops.object.select_all(action='DESELECT')
        for ob in copies:ob.select_set(True)
        bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();joined=bpy.context.object;joined.name='PR_'+name+'_LOD0'
        tris=len(joined.data.polygons)
        if tris>12000:raise RuntimeError(name+' exceeds prop triangle budget '+str(tris))
        file=ROOT/'exports'/('PR_'+name+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
        manifest['models'][name]={'file':file.name,'triangles':tris,'dimensions_m':list(joined.dimensions),'materials':1,'embedded_images':3}
        joined.hide_render=True;joined.hide_set(True)
    (ROOT/'exports/asset-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    H.save_master(str(ROOT/'PR_LifeFurniture_delivery.blend'))
    print('FURNITURE EXPORT',[(k,v['triangles']) for k,v in manifest['models'].items()])

def roundtrip():
    import struct
    manifest=json.loads((ROOT/'exports/asset-manifest.json').read_text());report={'models':{},'failures':[]}
    for name,data in manifest['models'].items():
        file=ROOT/'exports'/data['file'];raw=file.read_bytes();n=struct.unpack_from('<I',raw,12)[0];gltf=json.loads(raw[20:20+n])
        bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(file))
        meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
        if tris!=data['triangles']:report['failures'].append(name+' triangle mismatch')
        if len(gltf.get('images',[]))!=3 or any('uri' in x for x in gltf.get('images',[])+gltf.get('buffers',[])):
            report['failures'].append(name+' missing embedded images or external dependency')
        # glTF importer restores Z-up inside Blender; compare actual reimported dimensions.
        points=[o.matrix_world@__import__('mathutils').Vector(v) for o in meshes for v in o.bound_box]
        dims=[max(v[i] for v in points)-min(v[i] for v in points) for i in range(3)]
        if max(abs(a-b) for a,b in zip(dims,data['dimensions_m']))>.001:report['failures'].append(name+' dimensions differ')
        report['models'][name]={'triangles':tris,'dimensions_m':dims,'embedded_images':len(gltf.get('images',[]))}
    (ROOT/'review/roundtrip.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    if report['failures']:raise RuntimeError('Furniture roundtrip failed')
