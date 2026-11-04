from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).parent))
from kit import initialize,build
initialize()
build(False)
