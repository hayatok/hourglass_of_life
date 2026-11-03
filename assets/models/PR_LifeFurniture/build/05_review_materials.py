"""Review the actual palette-mapped export copies, without changing the master."""
from pathlib import Path
import importlib.util, os

ROOT = Path(__file__).resolve().parents[1]
SKILL = Path(os.environ.get('BLENDER_ASSET_SKILL', str(Path.home()/'.codex/skills/blender-image-to-3d')))
spec = importlib.util.spec_from_file_location('review_furniture', SKILL/'scripts/review_render.py')
review = importlib.util.module_from_spec(spec); spec.loader.exec_module(review)

for name in ['Bench','Chair','RoundTable','Worktable','Bed','Footstool','Radio','TownModel','BreadPlate','Mug']:
    review.main(review.parse([
        '--blend', str(ROOT/'PR_LifeFurniture_delivery.blend'),
        '--out', str(ROOT/'review/05_materials'/name),
        '--only', 'PR_'+name+'_LOD0', '--views', 'threequarter',
        '--ref-cam', '-30', '25', '50', '--mode', 'material',
        '--res', '384', '--gameplay-px', '128', '--samples', '16',
        '--turntable', '12' if name=='Bench' else '0'
    ]))

review.main(review.parse([
    '--blend', str(ROOT/'PR_LifeFurniture_delivery.blend'),
    '--out', str(ROOT/'review/04_topology'),
    '--only', 'PR_Bench_LOD0', '--views', 'front,threequarter',
    '--mode', 'wire', '--res', '640', '--gameplay-px', '128'
]))
print('Furniture material and topology renders: COMPLETE')
