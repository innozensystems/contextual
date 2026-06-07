"""
Ensure proxy tests import `app` from the correct directory.
Prevents shadowing by other `app` packages on PYTHONPATH.
Hides .env so Settings() loads with empty defaults for tests.
"""

import sys
from pathlib import Path

# Hide .env file before pydantic-settings reads it.
_proxy_root = Path(__file__).resolve().parent.parent
_env_path = _proxy_root / ".env"
_env_backup = _proxy_root / ".env.testbak"

if _env_path.exists():
    _env_path.rename(_env_backup)

# Add contextual/proxy/ to the front of sys.path so `import app` resolves
# to contextual/proxy/app/ and not some other app package elsewhere.
sys.path.insert(0, str(_proxy_root))

import pytest  # noqa: E402

from app.main import settings  # noqa: E402


@pytest.fixture(autouse=True)
def reset_settings_between_tests():
    """Reset mutable settings to safe defaults after each test."""
    original_mapbox = settings.mapbox_token
    original_key = settings.proxy_api_key
    settings.mapbox_token = ""
    settings.proxy_api_key = ""
    yield
    settings.mapbox_token = original_mapbox
    settings.proxy_api_key = original_key


def pytest_sessionfinish(session, exitstatus):
    """Restore .env file after all tests complete."""
    if _env_backup.exists():
        _env_backup.rename(_env_path)
