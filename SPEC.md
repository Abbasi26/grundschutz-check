# SPEC — GrundschutzCheck 0.1

Open-source tool that checks Windows 11 hardening against German BSI recommendations
(SiSyPHuS Win10/11 hardening guidance and IT-Grundschutz / machine-readable Grundschutz++
catalog in OSCAL). Produces an audit-ready evidence report.

## Shared project rules
- Code, comments and README in English. Short German summary at the end of the README.
- MIT license, copyright "Wasaf Abbasi". Include CONTRIBUTING.md, CHANGELOG.md and SECURITY.md.
- Write from scratch. No employer/customer code or data. No real tenant or host data.
- Before commit: no API keys, tokens, hostnames or personal paths.

## Scope v0.1
- PowerShell module (Windows PowerShell 5.1 and pwsh 7 on Windows). Read-only local checks:
  registry, security policy (secedit export), audit policy (auditpol), services, Defender.
- Check catalog as YAML/JSON. Each check: id, title, BSI reference, expected value, how to check,
  severity, remediation, plus GPO / Intune / registry fix snippets as text.
  About 40+ well-founded checks. Cite official BSI sources; never invent requirement ids.
  Mark uncertain mappings as `mapping: unverified`.
- Reports: self-contained HTML, Markdown, JSON/CSV with summary per BSI module and evidence
  (timestamp, hashed host fingerprint, tool version, catalog version).
- `-Demo` mode that renders a report from bundled fictional evidence without needing Windows.
- Ansible example for remote collection (optional helper).

## Gap vs prior art
HardeningKitty has BSI lists only for Windows 10 1809; no tool maps Windows 11 checks to
Grundschutz++. That gap is the point of this project.

## Acceptance
- Pester suite green.
- Python catalog builder `--check` and pytest catalog tests green.
- Demo run produces HTML/MD/JSON/CSV evidence report.
