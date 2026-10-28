# Check catalog 0.1

`catalog/windows11-client.json` is the catalog GrundschutzCheck runs. A sibling tool such as Quorum can read the same file. The JSON Schema is `catalog/schema/check-catalog-0.1.schema.json`. Quorum should read the JSON, not `tools/build_catalog.py`.

The schema version is `0.1.0`. The catalog version is independent and is `0.1.0` for this Windows 11 client profile.

## Rules for every consumer

- Keep `mapping` and `windows11_carryover` on every check, and `mapping` on every reference. Do not drop them when you copy a check.
- Do not invent requirement ids. A Kompendium id has the shape `SYS.2.2.3.A4`. A Grundschutz++ id has the shape `KONF.2.4` or `DET.3.1.1`. If you cannot point at the published sentence, set `mapping` to `unverified` or leave the check out.
- `mapping` means the link from that requirement to this setting was checked against the cited document. It does not mean the Windows 11 value was published by BSI.
- `windows11_carryover` means whether BSI has published this exact value for Windows 11. In catalog 0.1.0 every check is `unverified`, because the values come from the Windows 10 Hilfsmittel (version 1.0, 20 February 2025, from Windows 10 21H2). SYS.2.2.3 Edition 2023 applies to Windows 10 and Windows 11, and that is not the same thing as a Windows 11 settings matrix.
- You may ignore an `evaluation.method` you cannot run. Report that row as `not_applicable` or omit it. Do not turn a skipped method into `pass`.
- Remediation strings are text. Running them is a different product decision and needs its own preview. v0.1 never runs them.
- The Grundschutz++ catalog is CC-BY-SA. This repository stores ids and short titles only, and links the [resolved catalog](https://github.com/BSI-Bund/Stand-der-Technik-Bibliothek/blob/main/control_layer/Grundschutz%2B%2B/Grundschutz%2B%2B-resolved_catalog.json). Do not vendor that file here.

## Catalog document

| Field | Meaning |
| --- | --- |
| `schema_version` | `0.1.0` for this document shape. |
| `catalog` | Id, title, version, release date, description, target, applicability note, and `sources`. |
| `catalog.sources[].id` | Stable source id cited by `references[].source_id`. |
| `modules` | Display names for summary tables. A check points at `module.id`. |
| `checks` | One object per check. |

`module.id` is usually a Kompendium module such as `SYS.2.1` or `SYS.2.2.3`. Audit checks use `DET.3`, which is a Grundschutz++ practice prefix. `DET.3` is not a Kompendium Baustein id. The module title says so.

## Check

| Field | Meaning |
| --- | --- |
| `id` | Stable id matching `^[A-Z0-9][A-Z0-9._-]{2,80}$`. v0.1 uses `GS-W11-001` and so on. |
| `title` | Short English title. |
| `severity` | `critical`, `high`, `medium`, `low`, or `informational`. |
| `mapping` | `verified` only when at least one reference is `verified`. |
| `windows11_carryover` | `verified` or `unverified`. v0.1 is always `unverified`. |
| `module.id` | Key into `modules`. |
| `references` | One or more citations. `references[0]` is the primary reference shown in the summary column. |
| `rationale` | Why the expected value was chosen, including what a pass does not prove. |
| `conflict_note` | Set when two cited documents disagree. Empty when they do not. |
| `applicability_note` | Scope limits, such as domain account policy or a Windows edition. |
| `evaluation` | How to decide pass or fail. See below. |
| `remediation.summary` | What a person would change. v0.1 does not apply it. |
| `remediation.gpo` | Group Policy path and recommended option, as text. |
| `remediation.intune` | Settings Catalog path. An OMA-URI is included only when it was confirmed. Otherwise the text says no OMA-URI is cited. |
| `remediation.registry` | A `.reg` fragment, a security-template fragment, or another text snippet. It is not executed. |

### Reference

| Field | Meaning |
| --- | --- |
| `framework` | `it-grundschutz-kompendium` or `grundschutz-plus-plus`. |
| `requirement_id` | Published id. Never invented. |
| `title` | Official short title. German titles are kept as published. |
| `mapping` | `verified` or `unverified` for this citation, which can differ from the check. |
| `source_id` | Id in `catalog.sources`. |
| `note` | What was and was not confirmed. A verified reference can still say that a number comes from the Hilfsmittel while the Grundschutz++ control is parameterized. |

Known unverified citations in v0.1:

- `BER.6.4` on minimum length, because guidance says a length under 14 is not recommended when no other measures exist, and the scored floor is 10.
- `BER.6.5` on maximum password age, because the Hilfsmittel scores 365 days and BER.6.5 says changes should be event-driven only.
- `DER.1.A5` on the two audit checks, because that requirement does not name the Windows subcategory. The primary citation is `DET.3.1.1`.

## Evaluation

The same evaluator runs on a live collection, on `-Demo`, and in tests. It reads an evidence object. It does not read the network.

Methods: `registry`, `secedit`, `service`, `defender`, `feature`, `secureboot`, `bitlocker`, `auditpol`, `all_of`, `any_of`. Nesting stops at 4 levels.

Operators: `equals`, `not_equals`, `greater_or_equal`, `less_or_equal`, `in_range` (inclusive pair), `one_of`, `bits_set`. `secureboot` compares `expected` to `evidence.secureboot` and has no operator.

`when_absent` is `fail` (default), `pass`, or `not_applicable`. A missing collection is `error`. A missing value inside a collected collection uses `when_absent`. An audit subcategory that is not in the captured list is `error`. Audit checks match the subcategory GUID first (MS-GPAC), then the English name, then a de-DE display name. A miss is `error`, not `fail`. A missing feature row is the actual state `NotFound`. A missing BitLocker volume type is `error`.

`all_of`: any `fail` wins, then any `error`, then all `not_applicable`, otherwise `pass`. `any_of`: any `pass` wins, then any `fail`, then any `error`, otherwise `not_applicable`.

Numeric strings compare as integers. Booleans accept `true`, `false`, `0`, and `1`. String equality is case-insensitive.

### Evidence shape

| Field | Rows |
| --- | --- |
| `host` | `computer_name`, `domain`, `os_caption`, `os_version`, `os_build`. The report stores a SHA-256 of the canonical string and does not store the computer name or domain. |
| `registry` | `hive`, `path`, `name`, `value`. `path` has no hive prefix and no value name. |
| `secedit` | `section`, `key`, `value` as strings. |
| `services` | `name`, `start_type`, `status`. `Auto` from WMI is stored as `Automatic`. |
| `defender` | Properties copied from `Get-MpPreference`, such as `DisableRealtimeMonitoring`. |
| `features` | `name`, `state`. |
| `secureboot` | Boolean. |
| `bitlocker` | `volume_type`, `protection_status`. |
| `auditpol` | `subcategory`, `subcategory_guid`, `setting`. `subcategory_guid` on a check is the MS-GPAC GUID. Collected `subcategory` is the canonical English name when that GUID or a known de-DE alias matches. Settings are normalized to English. |
| `notes` | Strings copied into the report. Do not put a real host name here. |

A property named `registry_error`, `secedit_error`, `service_error`, `defender_error`, `feature_error`, `secureboot_error`, `bitlocker_error`, or `auditpol_error` turns that method into `error`.

## Result document

`grundschutzcheck-report.json` is the result document. Fields are snake_case.

| Field | Meaning |
| --- | --- |
| `tool.name`, `tool.version` | `GrundschutzCheck` and `0.2.0`. |
| `catalog.id`, `catalog.version`, `catalog.schema_version` | Catalog that was evaluated. |
| `evidence.generated_at` | UTC timestamp `yyyy-MM-ddTHH:mm:ssZ`. |
| `evidence.mode` | `demo` or `local`. |
| `evidence.host_fingerprint_sha256` | Lowercase hex SHA-256 of the v1 canonical host string (LF endings): `computer_name`, `domain`, `os_caption`, `os_version`, `os_build`. |
| `evidence.platform` | OS caption, version, and build. No computer name. |
| `evidence.audit_policy` | Every collected subcategory, including ones that are not scored. |
| `evidence.notes` | Collector notes. Demo mode prepends a fictional-data note. |
| `summary` | `pass`, `fail`, `error`, `not_applicable`, `total`, plus `modules` and `grundschutz_plus_plus`. |
| `summary.grundschutz_plus_plus` | Counts by the prefix before the first dot (`KONF`, `BER`, `DET`). Unverified citations are included. |
| `results[]` | One row per check: status, severity, both mapping fields, module, primary requirement, all references, expected, actual, message, rationale, notes, and remediation. |

Status is `pass`, `fail`, `error`, or `not_applicable`. A pass is an indicator for that setting. It is not a certificate that the whole BSI requirement is met. The rationale says so when the setting is only part of the requirement (firewall enabled, Defender real-time protection).

The script exit code is 2 when any result is `error`, 1 when any result is `fail`, and 0 otherwise. `-Demo` exits 1 because the fictional host fails checks on purpose.
