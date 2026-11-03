"""Copy the frozen candidates into a standalone, non-game Godot project."""
from pathlib import Path
import shutil,json,hashlib
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];PROBE=Path('/tmp/hourglass-haru-texture-r2')
PROBE.mkdir(exist_ok=True);(PROBE/'output').mkdir(exist_ok=True)
files=['game/scripts/jrpg_resident_model.gd','game/assets/models/resident_toon.gdshader']
for file in files:
    target=PROBE/file;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(REPO/file,target)
for variant,source in [('r1',REPO/'game/assets/models/haru'),('r2',REPO/'builds/haru-cute-pilot/r2')]:
    destination=PROBE/'models'/variant;destination.mkdir(parents=True,exist_ok=True)
    for file in ['CH_Haru.glb','CH_Haru_LOD1.glb','CH_Haru_LOD2.glb']:shutil.copyfile(source/file,destination/file)
shutil.copyfile(ROOT/'build/11_check_texture_memory.gd',PROBE/'check.gd')
(PROBE/'project.godot').write_text('''config_version=5
[application]
config/name="Haru r2 texture-memory probe"
[display]
window/size/viewport_width=640
window/size/viewport_height=640
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
anti_aliasing/quality/msaa_3d=2
textures/vram_compression/import_etc2_astc=true
''')
hashes={file:hashlib.sha256((REPO/file).read_bytes()).hexdigest() for file in files}
(ROOT/'review/r2/probe-source-snapshot.json').write_text(json.dumps({'project':str(PROBE),'source_files_sha256':hashes,'no_game_save_or_simulation':True},indent=2)+'\n')
print(PROBE)
