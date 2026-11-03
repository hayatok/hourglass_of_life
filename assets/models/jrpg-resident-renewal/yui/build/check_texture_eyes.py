#!/usr/bin/env python3
"""Run the shared raw-eye GPU check for yui; all results stay in this asset folder."""
from pathlib import Path
import importlib.util
path=Path(__file__).resolve().parents[2]/'saki/build/run_texture_eyes.py'
spec=importlib.util.spec_from_file_location('resident_eye_check',path)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if __name__=='__main__':module.run('yui')
