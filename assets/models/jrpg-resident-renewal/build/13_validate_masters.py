"""Run the skill topology/UV/weight validator on the explicit delivery masters."""
from pathlib import Path
import sys,importlib.util,json
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];SPECS=json.loads((ROOT/'build/specs.json').read_text())
path=Path(__file__).resolve().parent/'vendor/validate.py';spec=importlib.util.spec_from_file_location('asset_validate',path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
ids=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(SPECS);failed=[]
for ident in ids:
 name=SPECS[ident]['name'];args=module.parse(['--blend',str(REPO/f'builds/jrpg-resident-renewal/{ident}/CH_{name}_Delivery.blend'),'--collections','LOW,RIG_DEF','--out',str(ROOT/ident/'review/delivery-validate.json'),'--budget-tris','30000','--require-uv','--max-influences','4'])
 try:module.main(args)
 except SystemExit as error:
  if error.code:failed.append(ident)
if failed:raise RuntimeError('Delivery validation failed: '+str(failed))
