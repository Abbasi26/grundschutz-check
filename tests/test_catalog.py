"""Offline checks for the generated GrundschutzCheck catalog."""

import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "catalog" / "windows11-client.json"

VERIFIED_KOMPENDIUM = {
    "SYS.2.1.A1", "SYS.2.1.A3", "SYS.2.1.A6", "SYS.2.1.A8", "SYS.2.1.A15", "SYS.2.1.A16",
    "SYS.2.1.A18", "SYS.2.1.A28", "SYS.2.1.A31", "SYS.2.2.3.A4", "SYS.2.2.3.A5", "SYS.2.2.3.A6",
    "SYS.2.2.3.A12", "SYS.2.2.3.A15", "SYS.2.2.3.A16", "SYS.2.2.3.A17", "SYS.2.2.3.A18",
    "SYS.2.2.3.A19", "SYS.2.2.3.A20", "SYS.2.2.3.A22", "SYS.2.2.3.A23", "SYS.2.2.3.A24",
    "SYS.2.2.3.A25", "SYS.3.1.A3",
}
UNVERIFIED_KOMPENDIUM = {"DER.1.A5"}
VERIFIED_GSPP = {
    "KONF.2.4", "KONF.2.4.2", "KONF.2.9", "KONF.3.2", "KONF.3.8", "KONF.4.1.1", "KONF.4.3",
    "KONF.4.4", "KONF.7.1", "KONF.7.15", "KONF.7.16", "KONF.8.1.1", "BER.3.10", "BER.3.12",
    "BER.3.20", "BER.6.2", "DET.3.1.1", "DET.3.1.2",
}
UNVERIFIED_GSPP = {"BER.6.4", "BER.6.5"}


def test_builder_matches_committed_json():
    subprocess.check_call([sys.executable, str(ROOT / "tools" / "build_catalog.py"), "--check"], cwd=ROOT)


def test_requirement_ids_stay_inside_the_allow_list():
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    assert catalog["schema_version"] == "0.1.0"
    assert len(catalog["checks"]) >= 40
    for check in catalog["checks"]:
        assert check["windows11_carryover"] == "unverified"
        for ref in check["references"]:
            requirement_id = ref["requirement_id"]
            if ref["framework"] == "it-grundschutz-kompendium":
                allowed = VERIFIED_KOMPENDIUM if ref["mapping"] == "verified" else UNVERIFIED_KOMPENDIUM
            else:
                assert ref["framework"] == "grundschutz-plus-plus"
                allowed = VERIFIED_GSPP if ref["mapping"] == "verified" else UNVERIFIED_GSPP
            assert requirement_id in allowed


def test_schema_file_is_json():
    schema = json.loads((ROOT / "catalog" / "schema" / "check-catalog-0.1.schema.json").read_text(encoding="utf-8"))
    assert schema["properties"]["schema_version"]["const"] == "0.1.0"


def test_catalog_validates_against_schema():
    jsonschema = pytest.importorskip("jsonschema")
    schema = json.loads((ROOT / "catalog" / "schema" / "check-catalog-0.1.schema.json").read_text(encoding="utf-8"))
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    jsonschema.validate(catalog, schema)
