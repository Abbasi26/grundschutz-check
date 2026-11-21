"""Offline checks for the generated GrundschutzCheck catalog."""

import json
import subprocess
import sys
from pathlib import Path

import jsonschema
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
# DISA Windows 11 STIG V2R11, checked one by one against the published XCCDF.
VERIFIED_STIG = {
    "GS-W11-001": {("WN11-AC-000020", "V-253300", "SV-253300r1256653_rule")},
    "GS-W11-006": {("WN11-SO-000010", "V-253433", "SV-253433r958504_rule")},
    "GS-W11-023": {
        ("WN11-CC-000020", "V-253353", "SV-253353r1268251_rule"),
        ("WN11-CC-000025", "V-253354", "SV-253354r1268251_rule"),
    },
    "GS-W11-024": {("WN11-SO-000100", "V-253449", "SV-253449r958908_rule")},
    "GS-W11-025": {("WN11-SO-000120", "V-253451", "SV-253451r958908_rule")},
    "GS-W11-041": {("WN11-CC-000326", "V-253414", "SV-253414r958422_rule")},
    "GS-W11-060": {
        ("WN11-AU-000070", "V-253316", "SV-253316r991581_rule"),
        ("WN11-AU-000075", "V-253317", "SV-253317r991581_rule"),
    },
    "GS-W11-061": {
        ("WN11-AU-000005", "V-253306", "SV-253306r991570_rule"),
        ("WN11-AU-000010", "V-253307", "SV-253307r991570_rule"),
    },
}
STIG_SOURCE = "disa-stig-windows-11-v2r11"


def test_builder_matches_committed_json():
    subprocess.check_call([sys.executable, str(ROOT / "tools" / "build_catalog.py"), "--check"], cwd=ROOT)


def test_requirement_ids_stay_inside_the_allow_list():
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    assert catalog["schema_version"] == "0.1.0"
    assert len(catalog["checks"]) == 63
    for check in catalog["checks"]:
        assert check["windows11_carryover"] == "unverified"
        for ref in check["references"]:
            requirement_id = ref["requirement_id"]
            if ref["framework"] == "it-grundschutz-kompendium":
                allowed = VERIFIED_KOMPENDIUM if ref["mapping"] == "verified" else UNVERIFIED_KOMPENDIUM
            elif ref["framework"] == "disa-stig":
                continue
            else:
                assert ref["framework"] == "grundschutz-plus-plus"
                allowed = VERIFIED_GSPP if ref["mapping"] == "verified" else UNVERIFIED_GSPP
            assert requirement_id in allowed


def test_stig_references_match_the_checked_subset():
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    sources = {source["id"]: source for source in catalog["catalog"]["sources"]}
    assert sources[STIG_SOURCE]["version"] == "V2R11"
    assert sources[STIG_SOURCE]["released"] == "2026-09-30"
    found = {}
    for check in catalog["checks"]:
        refs = [ref for ref in check["references"] if ref["framework"] == "disa-stig"]
        if not refs:
            continue
        assert check["references"][0]["framework"] != "disa-stig"
        for ref in refs:
            assert ref["mapping"] == "verified"
            assert ref["source_id"] == STIG_SOURCE
            assert ref["note"]
        found[check["id"]] = {(ref["requirement_id"], ref["group_id"], ref["rule_id"]) for ref in refs}
    assert found == VERIFIED_STIG
    assert 5 <= len(found) <= 10


def test_schema_file_is_json():
    schema = json.loads((ROOT / "catalog" / "schema" / "check-catalog-0.1.schema.json").read_text(encoding="utf-8"))
    assert schema["properties"]["schema_version"]["const"] == "0.1.0"


def test_catalog_limits_are_informational_only():
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    limits = catalog["catalog"]["limits"]
    assert [limit["id"] for limit in limits] == [
        "smartscreen",
        "maps",
        "password-complexity",
        "store-wording",
        "firewall-profile-status",
        "defender-signatures",
        "third-party-antivirus",
        "domain-accounts",
    ]
    assert len({limit["id"] for limit in limits}) == 8
    for limit in limits:
        assert set(limit) == {"id", "title", "note"}
        assert all(limit[field].strip() for field in ("id", "title", "note"))
        assert "requirement_id" not in limit


def test_catalog_validates_against_schema():
    schema = json.loads((ROOT / "catalog" / "schema" / "check-catalog-0.1.schema.json").read_text(encoding="utf-8"))
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    jsonschema.validate(catalog, schema)

    catalog["catalog"]["limits"][0]["requirement_id"] = "NOT-ALLOWED"
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(catalog, schema)
