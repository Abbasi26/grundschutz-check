# Security

GrundschutzCheck 0.1 reads a Windows client and writes a report on that machine. It does not phone home. It does not apply the remediation text in the catalog.

## Reporting a vulnerability

Report a vulnerability privately to the maintainer, Wasaf Abbasi. Do not attach a report produced from a real system. A real report can contain configuration details. Describe the problem, the version, and a fictional or redacted reproduction.

## What a report contains

The published report stores a SHA-256 of the host identity and the operating-system caption, version, and build. It does not store the computer name or domain. It does store the observed values of the settings in the catalog. Treat a real JSON, HTML, Markdown, or CSV report as sensitive operational data. Do not commit one.

## Hardening of the tool itself

There is no supported switch that changes the system in v0.1. If you add one later, it needs an explicit switch and a preview of the writes. The Ansible example only copies the tool, runs the check, and fetches the JSON.
