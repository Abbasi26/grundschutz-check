#!/usr/bin/env python3
"""Create the small OSCAL fixture from a downloaded Grundschutz++ catalog."""

import argparse
import json
from pathlib import Path


def selected_controls(controls, ids):
    result = []
    for control in controls:
        copied = dict(control)
        children = selected_controls(control.get("controls", []), ids)
        if control["id"] in ids or children:
            if "controls" in copied:
                copied["controls"] = children
            result.append(copied)
    return result


def selected_groups(groups, ids):
    result = []
    for group in groups:
        copied = dict(group)
        controls = selected_controls(group.get("controls", []), ids)
        children = selected_groups(group.get("groups", []), ids)
        if controls or children:
            if "controls" in copied:
                copied["controls"] = controls
            if "groups" in copied:
                copied["groups"] = children
            result.append(copied)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("catalog", type=Path)
    parser.add_argument("--output", type=Path, default=Path("tests/fixtures/gspp/catalog.json"))
    parser.add_argument("--check-catalog", type=Path, default=Path("catalog/windows11-client.json"))
    args = parser.parse_args()

    source = json.loads(args.catalog.read_text(encoding="utf-8"))["catalog"]
    checks = json.loads(args.check_catalog.read_text(encoding="utf-8"))["checks"]
    ids = {
        reference["requirement_id"]
        for check in checks
        for reference in check["references"]
        if reference["framework"] == "grundschutz-plus-plus"
    }
    metadata = source["metadata"]
    excerpt = {
        "catalog": {
            "uuid": source["uuid"],
            "metadata": {
                key: metadata[key]
                for key in ("title", "version", "last-modified", "oscal-version")
            },
            "groups": selected_groups(source["groups"], ids),
        }
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(excerpt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
