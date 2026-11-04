"""Bake the authored flat material roles to a portable original palette atlas.
UV overlap inside a solid-color swatch is intentional; no lighting is stored in the atlas.
"""
import bpy,sys,math,json
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).parent))
import mesh_helpers as H
ROOT=Path(__file__).resolve().parents[1]

def linear_to_srgb(value):return 12.92*value if value<=.0031308 else 1.055*value**(1/2.4)-.055
def image_file(name,arr,non_color=False):
    path=ROOT/'textures'/f'{name}.png';path.parent.mkdir(exist_ok=True)
    image=bpy.data.images.new(name,width=arr.shape[1],height=arr.shape[0],alpha=True)
    image.colorspace_settings.name='Non-Color'
    image.pixels.foreach_set(arr.astype(np.float32).ravel());image.filepath_raw=str(path);image.file_format='PNG';image.save()
    bpy.data.images.remove(image)
    image=bpy.data.images.load(str(path),check_existing=False)
    image.colorspace_settings.name='Non-Color' if non_color else 'sRGB'
    return image

def build():
    H.open_master(str(ROOT/'CH_Nagisa_topology.blend'))
    meshes=[o for o in bpy.data.collections['LOW'].objects if o.type=='MESH']
    materials={m.name:m for ob in meshes for m in ob.data.materials if m}
    palette=[]
    for name,m in sorted(materials.items()):
        sh=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        palette.append({'name':name,'linear_color':list(sh.inputs['Base Color'].default_value),
                        'roughness':sh.inputs['Roughness'].default_value,'metallic':sh.inputs['Metallic'].default_value})
    index={p['name']:i for i,p in enumerate(palette)}
    color=np.ones((1024,1024,4),np.float32);orm=np.ones_like(color)
    normal=np.ones_like(color);normal[:,:,:3]=(.5,.5,1)
    for i,p in enumerate(palette):
        x=i%8*128;y=i//8*128
        color[y:y+128,x:x+128,:3]=[linear_to_srgb(c) for c in p['linear_color'][:3]]
        orm[y:y+128,x:x+128,:3]=(1,p['roughness'],p['metallic'])
    base=image_file('CH_Nagisa_BaseColor',color)
    surface=image_file('CH_Nagisa_ORM',orm,True)
    normals=image_file('CH_Nagisa_Normal',normal,True)
    newmats={}
    for role in ['Body','Face']:
        m=bpy.data.materials.new('CH_Nagisa_'+role);nodes=m.node_tree.nodes;links=m.node_tree.links
        shader=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
        tex=nodes.new('ShaderNodeTexImage');tex.image=base;tex.interpolation='Closest'
        links.new(tex.outputs['Color'],shader.inputs['Base Color'])
        texture=nodes.new('ShaderNodeTexImage');texture.image=surface;texture.interpolation='Closest'
        split=nodes.new('ShaderNodeSeparateColor');links.new(texture.outputs['Color'],split.inputs[0])
        links.new(split.outputs['Green'],shader.inputs['Roughness']);links.new(split.outputs['Blue'],shader.inputs['Metallic'])
        norm=nodes.new('ShaderNodeTexImage');norm.image=normals
        converter=nodes.new('ShaderNodeNormalMap');links.new(norm.outputs['Color'],converter.inputs['Color'])
        links.new(converter.outputs['Normal'],shader.inputs['Normal'])
        if role=='Face':
            # Eye, brow and lip surfaces retain their color without throwing shadows on the cheek.
            links.new(tex.outputs['Color'],shader.inputs['Emission Color']);shader.inputs['Emission Strength'].default_value=.25
        newmats[role]=m
    for ob in meshes:
        old=list(ob.data.materials)
        for layer in list(ob.data.uv_layers):ob.data.uv_layers.remove(layer)
        uv=ob.data.uv_layers.new(name='PaletteUV');uv.active_render=True
        ob.data.uv_layers.active_index=0
        for poly in ob.data.polygons:
            slot=index[old[poly.material_index].name]
            u=(slot%8+.5)/8;v=(slot//8+.5)/8
            for k,loop in enumerate(poly.loop_indices):
                # An interior triangle has finite UV area, with >50 px padding to the next swatch.
                uv.data[loop].uv=(u+[-.012,.012,0][k%3],v+[-.012,-.012,.012][k%3])
            poly.material_index=0
        ob.data.materials.clear();ob.data.materials.append(newmats['Face' if ob.get('mesh_role')=='face' else 'Body'])
    manifest={'base_color':'sRGB','ORM':'Non-Color: R=AO(1), G=roughness, B=metallic',
        'normal':'Non-Color, tangent OpenGL +Y, neutral because forms are modelled',
        'size':[1024,1024],'palette':palette,'uv_policy':'Intentional shared solid-color swatches; >50 px padding; no directional lighting baked.',
        'material_groups':2,'inferred':'Material response is authored, not measured from a physical garment.'}
    (ROOT/'textures/texture-contract.json').write_text(json.dumps(manifest,indent=2))
    H.save_master(str(ROOT/'CH_Nagisa_materials.blend'))
    print('PALETTE ATLAS',len(palette),'roles, 2 materials')

if __name__=='__main__':build()
