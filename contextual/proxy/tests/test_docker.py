"""Smoke test for the proxy Docker image.

This test builds the Docker image and verifies the container starts and
responds to /health. Requires Docker daemon to be running.

Usage:
    pytest tests/test_docker.py -v
"""

import subprocess
import time
import urllib.request

import pytest

IMAGE_NAME = "contextual-proxy:test"
CONTAINER_NAME = "contextual-proxy-smoke"


def _docker_available() -> bool:
    try:
        return subprocess.run(["docker", "--version"], capture_output=True).returncode == 0
    except FileNotFoundError:
        return False


@pytest.mark.skipif(not _docker_available(), reason="Docker not available")
def test_docker_image_builds():
    """Build the Docker image from the proxy Dockerfile."""
    import pathlib

    proxy_dir = pathlib.Path(__file__).resolve().parent.parent
    result = subprocess.run(
        ["docker", "build", "-t", IMAGE_NAME, "."],
        cwd=str(proxy_dir),
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Docker build failed:\n{result.stderr}"


@pytest.mark.skipif(not _docker_available(), reason="Docker not available")
def test_docker_container_starts_and_responds():
    """Run container, wait for startup, hit /health, then stop."""
    # Clean up any stale container
    subprocess.run(
        ["docker", "rm", "-f", CONTAINER_NAME],
        capture_output=True,
    )

    # Start container with dummy env vars
    result = subprocess.run(
        [
            "docker",
            "run",
            "-d",
            "--name",
            CONTAINER_NAME,
            "-p",
            "18000:8000",
            "-e",
            "MAPBOX_TOKEN=dummy-token-for-test",
            "-e",
            "REDIS_URL=redis://localhost:6379/0",
            IMAGE_NAME,
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Docker run failed:\n{result.stderr}"

    try:
        # Poll /health up to 10 seconds
        url = "http://localhost:18000/health"
        for _ in range(20):
            try:
                with urllib.request.urlopen(url, timeout=0.5) as resp:
                    assert resp.status == 200
                    body = resp.read()
                    assert b'"status":"ok"' in body
                    break
            except Exception:
                time.sleep(0.5)
        else:
            pytest.fail("Container did not respond to /health within 10 seconds")
    finally:
        subprocess.run(
            ["docker", "rm", "-f", CONTAINER_NAME],
            capture_output=True,
        )
        # Also remove test image to keep local clean
        subprocess.run(
            ["docker", "rmi", IMAGE_NAME],
            capture_output=True,
        )
