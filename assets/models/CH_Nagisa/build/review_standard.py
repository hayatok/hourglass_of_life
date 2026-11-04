"""Skill review renderer with the Standard view transform chosen by this art direction."""
import importlib.util
from pathlib import Path
import os, sys
skill=Path(os.environ.get('BLENDER_ASSET_SKILL',str(Path.home()/'.codex/skills/blender-image-to-3d')))
spec=importlib.util.spec_from_file_location('asset_review',skill/'scripts/review_render.py')
review=importlib.util.module_from_spec(spec);spec.loader.exec_module(review)
setup=review.setup_engine
def setup_standard(scene,*args):
    setup(scene,*args)
    scene.view_settings.view_transform='Standard'
review.setup_engine=setup_standard
review.main(review.parse(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []))
