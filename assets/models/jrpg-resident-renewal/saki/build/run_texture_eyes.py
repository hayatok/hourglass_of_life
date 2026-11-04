#!/usr/bin/env python3
"""Reproduce raw eye calibration/GPU views for saki/tomo/yui without core edits."""
from pathlib import Path
import hashlib,importlib.util,json,os,re,shutil,subprocess,tempfile,sys
ROOT=Path(__file__).resolve().parents[5]
CAST=ROOT/'assets/models/jrpg-resident-renewal'
BUILD=CAST/'saki/build'
GODOT=os.environ.get('GODOT_BIN','/Applications/Godot.app/Contents/MacOS/Godot')
SHADER=ROOT/'game/assets/models/haru/haru_texture_eyes.gdshader'

def run(rid):
 spec=importlib.util.spec_from_file_location('eye_calibration',BUILD/'calibrate_texture_eyes.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);module.calibrate(rid)
 folder=CAST/rid;out=folder/'review/texture-eyes';raw=next((folder/'raw').glob('*.glb'));project=Path(tempfile.mkdtemp(prefix=f'hourglass-{rid}-eyes-'));probe=project/'probe';probe.mkdir()
 selected_shader=SHADER
 files={raw:'raw.glb',selected_shader:'texture_eyes.gdshader',BUILD/'check_texture_eyes.gd':'check.gd',out/'face-layout-candidate.json':'layout.json',out/'ray-calibration.json':'calibration.json'}
 sources=[]
 for source,name in files.items():
  shutil.copyfile(source,probe/name);sources.append({'file':str(source.relative_to(ROOT)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'stage':name})
 (project/'project.godot').write_text('''config_version=5
[application]
config/name="Resident raw texture eyes"
config/features=PackedStringArray("4.7", "GL Compatibility")
[display]
window/size/viewport_width=800
window/size/viewport_height=800
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
anti_aliasing/quality/msaa_3d=2
''')
 (out/'source-fixture.json').write_text(json.dumps({'project':str(project),'sources':sources,'note':'The existing uniform-driven shader is reused unchanged; all landmark/layout values are independently calibrated.'},indent=2)+'\n')
 for command,log in [([GODOT,'--headless','--editor','--import','--path',str(project)],'editor-import.log'),([GODOT,'--path',str(project),'--script','res://probe/check.gd','--',f'--output={out}',f'--resident={rid}'],'gpu-check.log')]:
  result=subprocess.run(command,cwd=project,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=90);(out/log).write_text(result.stdout)
  if result.returncode or re.search(r'(?m)^(?:SCRIPT ERROR|ERROR):',result.stdout):raise RuntimeError(f'Godot failed for {rid}: {out/log}')
 for source in sources:source['sha256_after']=hashlib.sha256((ROOT/source['file']).read_bytes()).hexdigest()
 fixture=json.loads((out/'source-fixture.json').read_text());fixture['sources']=sources;fixture['fingerprint_policy']='Identification/provenance only; not assertions or pass/fail gates.';(out/'source-fixture.json').write_text(json.dumps(fixture,indent=2)+'\n')
 checks=json.loads((out/'checks.json').read_text());assert checks['passed']
 layout=checks['layout'].copy();layout['source_basecolor_pixel_sha256']=checks['provenance']['runtime_atlas_pixel_sha256'];layout['fingerprint_policy']='Identifiers only; not tests or pass/fail gates.';layout['candidate_controls']=['Blink','TiredEyes'];layout['production_status']='Raw GPU calibration candidate; rig/LOD/actor integration pending.'
 (folder/'build/face-layout-candidate.json').write_text(json.dumps(layout,indent=2)+'\n')
 baseline=out/'accepted-image-hashes.json'
 if baseline.exists():
  expected=json.loads(baseline.read_text());actual={name:hashlib.sha256((out/name).read_bytes()).hexdigest() for name in expected}
  (out/'image-regression.json').write_text(json.dumps({'purpose':'Render-file fingerprints for identification only, not a regression test or acceptance gate.','accepted_sha256':expected,'current_sha256':actual},indent=2)+'\n')
 print(rid,checks['checks'],'checks',out)
if __name__=='__main__':
 for rid in sys.argv[1:] or ['saki','tomo','yui']:run(rid)
