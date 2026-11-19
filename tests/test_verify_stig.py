"""Offline tests for tools/verify_stig.py with an ids-only XCCDF fixture."""

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "verify_stig.py"
FIXTURE = ROOT / "tests" / "fixtures" / "stig-windows11-subset-xccdf.xml"


def run(path: Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(TOOL), str(path)], check=False, capture_output=True, text=True, cwd=ROOT)


def scratch(name: str, text: str) -> Path:
    folder = ROOT / ".tmp" / "test-verify-stig"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / name
    path.write_text(text, encoding="utf-8")
    return path


def test_fixture_matches_catalog_ids():
    result = run(FIXTURE)
    assert result.returncode == 0, result.stderr
    assert "match V2R11" in result.stdout


def test_changed_rule_revision_is_reported():
    text = FIXTURE.read_text(encoding="utf-8").replace("SV-253449r958908_rule", "SV-253449r999999_rule")
    result = run(scratch("changed.xml", text))
    assert result.returncode == 1
    assert "WN11-SO-000100 differs" in result.stderr


def test_other_release_is_reported():
    text = FIXTURE.read_text(encoding="utf-8").replace("Release: 11", "Release: 12")
    result = run(scratch("release.xml", text))
    assert result.returncode == 1
    assert "benchmark is V2R12" in result.stderr


def test_missing_rule_is_reported():
    lines = [line for line in FIXTURE.read_text(encoding="utf-8").splitlines() if "WN11-CC-000326" not in line]
    result = run(scratch("missing.xml", "\n".join(lines) + "\n"))
    assert result.returncode == 1
    assert "WN11-CC-000326 is not in the benchmark" in result.stderr


def teardown_module():
    shutil.rmtree(ROOT / ".tmp" / "test-verify-stig", ignore_errors=True)
