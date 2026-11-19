"""Re-check the STIG ids in tools/build_catalog.py against a downloaded DISA XCCDF file.

The STIG itself is not part of this repository. Download the Windows 11 STIG ZIP from
https://www.cyber.mil/stigs/downloads/ and pass the extracted *-xccdf.xml file.
The script only reads the file. It compares version, release, group id, rule id,
STIG id and rule title for every entry in STIG_RULES.
"""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_catalog

NS = {"x": "http://checklists.nist.gov/xccdf/1.1"}
EXPECTED_VERSION = "V2R11"


def read_benchmark(path: Path) -> tuple[str, dict]:
    root = ET.parse(path).getroot()
    version = (root.findtext("x:version", default="", namespaces=NS) or "").strip()
    release_info = root.findtext("x:plain-text[@id='release-info']", default="", namespaces=NS) or ""
    match = re.search(r"Release:\s*(\d+)", release_info)
    label = f"V{version}R{match.group(1)}" if version and match else ""
    rules = {}
    for group in root.findall("x:Group", NS):
        rule = group.find("x:Rule", NS)
        if rule is None:
            continue
        stig_id = (rule.findtext("x:version", default="", namespaces=NS) or "").strip()
        rules[stig_id] = (
            group.get("id", ""),
            rule.get("id", ""),
            (rule.findtext("x:title", default="", namespaces=NS) or "").strip(),
        )
    return label, rules


def compare(label: str, rules: dict) -> list[str]:
    problems = []
    if label != EXPECTED_VERSION:
        problems.append(f"benchmark is {label or 'unknown'}, catalog cites {EXPECTED_VERSION}")
    for stig_id, expected in sorted(build_catalog.STIG_RULES.items()):
        actual = rules.get(stig_id)
        if actual is None:
            problems.append(f"{stig_id} is not in the benchmark")
        elif actual != expected:
            problems.append(f"{stig_id} differs: benchmark {actual}, catalog {expected}")
    return problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("xccdf", type=Path, help="Path to U_MS_Windows_11_STIG_*_Manual-xccdf.xml")
    args = parser.parse_args(argv)
    label, rules = read_benchmark(args.xccdf)
    problems = compare(label, rules)
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        return 1
    print(f"{len(build_catalog.STIG_RULES)} STIG references match {label}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
