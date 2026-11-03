"""Small lossless GLB texture/buffer helpers shared by resident deliveries."""
import json,struct,copy,hashlib
def read(path):
 raw=path.read_bytes();n,k=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+n]);o=20+n;length,kind=struct.unpack_from('<II',raw,o);return doc,raw[o+8:o+8+length]
def write(path,doc,binary):
 js=json.dumps(doc,separators=(',',':')).encode();js+=b' '*((-len(js))%4);binary+=b'\0'*((-len(binary))%4);path.write_bytes(struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(binary))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(binary),0x004e4942)+binary)
def view_bytes(doc,binary,index):
 view=doc['bufferViews'][index];start=view.get('byteOffset',0);return binary[start:start+view['byteLength']]
def compact(doc,binary):
 used={im['bufferView'] for im in doc.get('images',[]) if 'bufferView' in im}
 for a in doc.get('accessors',[]):
  if 'bufferView' in a:used.add(a['bufferView'])
  for part in a.get('sparse',{}).values():
   if isinstance(part,dict) and 'bufferView' in part:used.add(part['bufferView'])
 mapping={old:new for new,old in enumerate(sorted(used))};out=bytearray();views=[]
 for old in sorted(used):
  view=copy.deepcopy(doc['bufferViews'][old]);data=view_bytes(doc,binary,old);out.extend(b'\0'*((-len(out))%4));view['byteOffset']=len(out);view['buffer']=0;out.extend(data);views.append(view)
 for im in doc.get('images',[]):
  if 'bufferView' in im:im['bufferView']=mapping[im['bufferView']]
 for a in doc.get('accessors',[]):
  if 'bufferView' in a:a['bufferView']=mapping[a['bufferView']]
  for part in a.get('sparse',{}).values():
   if isinstance(part,dict) and 'bufferView' in part:part['bufferView']=mapping[part['bufferView']]
 doc['bufferViews']=views;doc['buffers']=[{'byteLength':len(out)}];return bytes(out)
def source_images(raw):
 doc,binary=read(raw);return [{'name':im.get('name',f'image-{i}'),'mime_type':im['mimeType'],'sha256':hashlib.sha256(view_bytes(doc,binary,im['bufferView'])).hexdigest(),'pixel_policy':'original encoded bytes retained in LOD0, no re-encode'} for i,im in enumerate(doc['images'])]
def preserve_source_textures(path,raw):
 doc,binary=read(path);source,sbinary=read(raw);binary=bytearray(binary)
 for key in ['images','materials','textures','samplers']:doc[key]=copy.deepcopy(source.get(key,[]))
 for i,im in enumerate(doc['images']):
  data=view_bytes(source,sbinary,source['images'][i]['bufferView']);binary.extend(b'\0'*((-len(binary))%4));offset=len(binary);binary.extend(data);im['bufferView']=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(data)})
 for mesh in doc['meshes']:
  for primitive in mesh['primitives']:primitive['material']=0
 doc['extensionsUsed']=list(dict.fromkeys(doc.get('extensionsUsed',[])+source.get('extensionsUsed',[])));write(path,doc,compact(doc,bytes(binary)))
def geometry_only_material(path):
 doc,binary=read(path)
 for key in ['images','textures','samplers']:doc.pop(key,None)
 doc['materials']=[{'name':'GeometryOnly_RuntimeActorOverride','pbrMetallicRoughness':{'baseColorFactor':[1,1,1,1],'metallicFactor':0,'roughnessFactor':1}}]
 write(path,doc,compact(doc,binary))
