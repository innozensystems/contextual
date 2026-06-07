"""
Ensure proxy tests import `app` from the correct directory.
Prevents shadowing by other `app` packages on PYTHONPATH.
"""

import sys
from pathlib import Path

# Add contextual/proxy/ to the front of sys.path so `import app` resolves
# to contextual/proxy/app/ and not some other app package elsewhere.
_PROXY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_PROXY_ROOT))
