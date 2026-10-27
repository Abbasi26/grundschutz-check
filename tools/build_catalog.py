#!/usr/bin/env python3
"""Build the GrundschutzCheck v0.1 catalog and the fictional demo evidence.

The JSON catalog is the artifact other tools (including a sibling project
named Quorum) should read. This script is the editable source for that JSON.

Do not invent requirement ids. Ids below were read from the BSI Hilfsmittel
for Windows clients 1.0 (20 February 2025), the IT-Grundschutz-Kompendium
Edition 2023 headings in that Hilfsmittel, or the Grundschutz++ resolved
catalog version 2026-09-24. Uncertain links use mapping "unverified".
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "catalog" / "windows11-client.json"
EVIDENCE_PATH = ROOT / "demo" / "evidence.json"

HILF = "bsi-hilfsmittel-windows-client-1.0"
KOMP_SRC = "it-grundschutz-kompendium-2023"
GSPP_SRC = "grundschutz-plus-plus-2026-09-24"

ABSENT = object()

VERIFIED_KOMP = {
    "SYS.2.1.A1",
    "SYS.2.1.A3",
    "SYS.2.1.A6",
    "SYS.2.1.A8",
    "SYS.2.1.A15",
    "SYS.2.1.A16",
    "SYS.2.1.A18",
    "SYS.2.1.A28",
    "SYS.2.1.A31",
    "SYS.2.2.3.A4",
    "SYS.2.2.3.A5",
    "SYS.2.2.3.A6",
    "SYS.2.2.3.A12",
    "SYS.2.2.3.A15",
    "SYS.2.2.3.A16",
    "SYS.2.2.3.A17",
    "SYS.2.2.3.A18",
    "SYS.2.2.3.A19",
    "SYS.2.2.3.A20",
    "SYS.2.2.3.A22",
    "SYS.2.2.3.A23",
    "SYS.2.2.3.A24",
    "SYS.2.2.3.A25",
    "SYS.3.1.A3",
}
UNVERIFIED_KOMP = {"DER.1.A5"}
VERIFIED_GSPP = {
    "KONF.2.4",
    "KONF.2.4.2",
    "KONF.2.9",
    "KONF.3.2",
    "KONF.3.8",
    "KONF.4.1.1",
    "KONF.4.3",
    "KONF.4.4",
    "KONF.7.1",
    "KONF.7.15",
    "KONF.7.16",
    "KONF.8.1.1",
    "BER.3.10",
    "BER.3.12",
    "BER.3.20",
    "BER.6.2",
    "DET.3.1.1",
    "DET.3.1.2",
}
UNVERIFIED_GSPP = {"BER.6.4", "BER.6.5"}

MODULE_TITLES = {
    "SYS.2.1": "Allgemeiner Client",
    "SYS.2.2.3": "Clients unter Windows",
    "SYS.3.1": "Laptops",
    "DET.3": "Detektion (Grundschutz++ practice DET.3, not a Kompendium Baustein)",
}

TITLES = {
    "SYS.2.1.A1": "Sichere Authentisierung von Benutzenden",
    "SYS.2.1.A3": "Aktivieren von Autoupdate-Mechanismen",
    "SYS.2.1.A6": "Einsatz von Schutzprogrammen gegen Schadsoftware",
    "SYS.2.1.A8": "Absicherung des Bootvorgangs",
    "SYS.2.1.A15": "Sichere Installation und Konfiguration von Clients",
    "SYS.2.1.A16": "Deaktivierung und Deinstallation nicht benötigter Komponenten und Kennungen",
    "SYS.2.1.A18": "Nutzung von verschlüsselten Kommunikationsverbindungen",
    "SYS.2.1.A28": "Verschlüsselung der Clients",
    "SYS.2.1.A31": "Einrichtung lokaler Paketfilter",
    "SYS.2.2.3.A4": "Telemetrie und Datenschutzeinstellungen unter Windows",
    "SYS.2.2.3.A5": "Schutz vor Schadsoftware unter Windows",
    "SYS.2.2.3.A6": "Integration von Online-Konten in das Betriebssystem",
    "SYS.2.2.3.A12": "Datei- und Freigabeberechtigungen unter Windows",
    "SYS.2.2.3.A15": "Einsatz der Synchronisationsmechanismen unter Windows",
    "SYS.2.2.3.A16": "Anbindung von Windows an den Microsoft-Store",
    "SYS.2.2.3.A17": "Keine Speicherung von Daten zur automatischen Anmeldung",
    "SYS.2.2.3.A18": "Einsatz der Windows-Remoteunterstützung",
    "SYS.2.2.3.A19": "Sicherheit beim Fernzugriff über RDP",
    "SYS.2.2.3.A20": "Einsatz der Benutzerkontensteuerung UAC für privilegierte Konten",
    "SYS.2.2.3.A22": "Verwendung der Windows PowerShell",
    "SYS.2.2.3.A23": "Erweiterter Schutz der Anmeldeinformationen unter Windows",
    "SYS.2.2.3.A24": "Aktivierung des Last-Access-Zeitstempels",
    "SYS.2.2.3.A25": "Umgang mit Fernzugriffsfunktionen der Connected User Experience and Telemetry",
    "SYS.3.1.A3": "Einsatz von Personal Firewalls",
    "DER.1.A5": "Einsatz von mitgelieferten Systemfunktionen zur Detektion",
    "KONF.2.4": "Deaktivierung nicht benötigter Systemfunktionen",
    "KONF.2.4.2": "Externe Cloud-Anbindungen",
    "KONF.2.9": "Abgesicherter und authentisierter Bootprozess",
    "KONF.3.2": "Speicherverschlüsselung",
    "KONF.3.8": "Einschränkung von Wechselmedien",
    "KONF.4.1.1": "Weiterleitung von Anmeldeinformationen",
    "KONF.4.3": "Authentifizierung von Fernwartungsfunktionen",
    "KONF.4.4": "Einschränkung von Fernwartungsfunktionen",
    "KONF.7.1": "Echtzeitscanner",
    "KONF.7.15": "Lokale Firewall",
    "KONF.7.16": "Anti-Exploit",
    "KONF.8.1.1": "Automatische Sicherheitsupdates",
    "BER.3.10": "Anmeldeversuchsgrenze am System",
    "BER.3.12": "Systemsperre bei Inaktivität",
    "BER.3.20": "Zwischenspeicherung von Zugangsdaten",
    "BER.6.2": "Blockieren von Passwort Recycling",
    "BER.6.4": "Kriterien für die Qualität von Passwörtern",
    "BER.6.5": "Anlassbezogene Passwortwechsel",
    "DET.3.1.1": "Authentifizierungen",
    "DET.3.1.2": "Ausgeführte Kommandozeilenbefehle",
}

DOMAIN_NOTE = (
    "secedit /export reads the local security database. On a domain member, account policy in that "
    "database does not govern domain accounts. Domain accounts follow the Default Domain Policy on a "
    "domain controller. v0.1 does not query a domain controller."
)
CARRY = (
    "The concrete value is carried over from the Windows 10 Hilfsmittel (from Windows 10 version 21H2). "
    "BSI has not published a Windows 11 settings matrix. SYS.2.2.3 Edition 2023 applies to Windows 10 and Windows 11."
)
NOT_APPLIED = " v0.1 does not apply this change."

POL = r"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
LSA = r"SYSTEM\CurrentControlSet\Control\Lsa"
TS = r"SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
FW = r"SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy"
SCHANNEL = r"SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
ASR_PATH = r"SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules"
ASR = [
    "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2",
    "56a863a9-875e-4185-98a7-b882c64b5ce5",
    "b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4",
    "d3e037e1-3eb8-44c8-a917-57927947596d",
    "5beb7efe-fd9a-4556-801d-275e5ffc04cc",
    "e6db77e5-3df2-4cf1-b95a-636979351e5b",
]
NTLM_BITS = 537395200  # 0x80000 NTLMv2 session security + 0x20000000 128-bit

REG_OV = {
    (r"SOFTWARE\Policies\Microsoft\Windows\DataCollection", "AllowTelemetry"): 1,
    (r"SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters", "RequireSecuritySignature"): 0,
    (LSA, "LmCompatibilityLevel"): 3,
    (SCHANNEL + r"\TLS 1.0\Client", "Enabled"): 1,
    (POL, "InactivityTimeoutSecs"): 0,
    (r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon", "CachedLogonsCount"): "10",
    (POL, "ConsentPromptBehaviorAdmin"): 5,
    (POL, "FilterAdministratorToken"): 0,
    (FW + r"\PublicProfile", "EnableFirewall"): 0,
    (r"SOFTWARE\Policies\Microsoft\Windows\WinRM\Client", "AllowUnencryptedTraffic"): 1,
    (ASR_PATH, ASR[0]): 0,
    (r"SOFTWARE\Policies\Microsoft\Windows\OneDrive", "DisableFileSyncNGSC"): ABSENT,
    (r"SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging", "EnableScriptBlockLogging"): ABSENT,
}
SEC_OV = {
    ("System Access", "MaximumPasswordAge"): "90",
    ("System Access", "MinimumPasswordLength"): "14",
}
SVC_OV = {
    "DiagTrack": {"start_type": "Automatic", "status": "Running"},
    "RemoteRegistry": {"start_type": "Manual", "status": "Stopped"},
}
DEF_OV = {"PUAProtection": 0}
FEAT_OV = {"MicrosoftWindowsPowerShellV2Root": "Enabled"}
BL_OV = "Off"
AUD_OV = {"Logon": "Success"}


def komp(req: str, note: str = "") -> dict:
    text = (
        "Requirement from the IT-Grundschutz-Kompendium, Edition 2023. The setting value is taken from "
        "the BSI Hilfsmittel for Windows clients, version 1.0 (20 February 2025)."
    )
    if note:
        text = text + " " + note
    return {
        "framework": "it-grundschutz-kompendium",
        "requirement_id": req,
        "title": TITLES[req],
        "mapping": "verified",
        "source_id": HILF,
        "note": text,
    }


def komp_unverified(req: str, note: str) -> dict:
    return {
        "framework": "it-grundschutz-kompendium",
        "requirement_id": req,
        "title": TITLES[req],
        "mapping": "unverified",
        "source_id": KOMP_SRC,
        "note": note,
    }


def gspp(req: str, mapping: str = "verified", note: str = "") -> dict:
    text = note or (
        "Control id and title from Anwenderkatalog Grundschutz++, resolved catalog "
        "version 2026-09-24T07:12:39.131983+00:00."
    )
    return {
        "framework": "grundschutz-plus-plus",
        "requirement_id": req,
        "title": TITLES[req],
        "mapping": mapping,
        "source_id": GSPP_SRC,
        "note": text,
    }


def reg(path: str, name: str, operator: str, expected, when_absent: str | None = None) -> dict:
    item = {
        "method": "registry",
        "hive": "HKLM",
        "path": path,
        "name": name,
        "operator": operator,
        "expected": expected,
    }
    if when_absent:
        item["when_absent"] = when_absent
    return item


def sec(key: str, operator: str, expected, section: str = "System Access") -> dict:
    return {
        "method": "secedit",
        "section": section,
        "key": key,
        "operator": operator,
        "expected": expected,
    }


def service(name: str, prop: str, operator: str, expected) -> dict:
    return {
        "method": "service",
        "name": name,
        "property": prop,
        "operator": operator,
        "expected": expected,
    }


def defender(prop: str, operator: str, expected) -> dict:
    return {"method": "defender", "property": prop, "operator": operator, "expected": expected}


def feature(name: str, operator: str, expected) -> dict:
    return {"method": "feature", "name": name, "operator": operator, "expected": expected}


# Subcategory GUIDs from MS-GPAC 2.2.1.2. These are Windows identifiers, not BSI ids.
AUDIT_SUBCATEGORY_GUIDS = {
    "Logon": "{0CCE9215-69AE-11D9-BED3-505054503030}",
    "Logoff": "{0CCE9216-69AE-11D9-BED3-505054503030}",
    "Account Lockout": "{0CCE9217-69AE-11D9-BED3-505054503030}",
    "Special Logon": "{0CCE921B-69AE-11D9-BED3-505054503030}",
    "Process Creation": "{0CCE922B-69AE-11D9-BED3-505054503030}",
    "User Account Management": "{0CCE9235-69AE-11D9-BED3-505054503030}",
    "Security Group Management": "{0CCE9237-69AE-11D9-BED3-505054503030}",
    "Credential Validation": "{0CCE923F-69AE-11D9-BED3-505054503030}",
}


def auditpol(subcategory: str, expected: str) -> dict:
    return {
        "method": "auditpol",
        "subcategory": subcategory,
        "subcategory_guid": AUDIT_SUBCATEGORY_GUIDS[subcategory],
        "operator": "equals",
        "expected": expected,
    }


def allof(children: list) -> dict:
    return {"method": "all_of", "evaluations": children}


def leaves(evaluation: dict) -> list:
    if evaluation["method"] in ("all_of", "any_of"):
        found = []
        for child in evaluation["evaluations"]:
            found.extend(leaves(child))
        return found
    return [evaluation]


def snippet_value(evaluation: dict):
    operator = evaluation["operator"]
    expected = evaluation["expected"]
    if operator == "in_range":
        return expected[1]
    if operator == "one_of":
        return expected[0]
    return expected


def registry_snippet(nodes: list) -> str:
    grouped: dict[str, list] = {}
    order: list[str] = []
    for node in nodes:
        path = node["path"]
        if path not in grouped:
            grouped[path] = []
            order.append(path)
        grouped[path].append(node)
    lines = ["Windows Registry Editor Version 5.00", ""]
    for path in order:
        lines.append("[HKEY_LOCAL_MACHINE\\" + path + "]")
        for node in grouped[path]:
            value = snippet_value(node)
            name = node["name"]
            if isinstance(value, str):
                lines.append(f'"{name}"="{value}"')
            else:
                lines.append(f'"{name}"=dword:{int(value) & 0xFFFFFFFF:08x}')
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def secedit_snippet(nodes: list) -> str:
    lines = [
        "; Security template fragment for secedit. This is not a Registry Editor file.",
        "; On a domain member, account policy here does not govern domain accounts.",
    ]
    current = None
    for node in nodes:
        if node["section"] != current:
            current = node["section"]
            lines.append("")
            lines.append("[" + current + "]")
        lines.append(f"{node['key']} = {snippet_value(node)}")
    lines.append("")
    return "\n".join(lines)


def remediation_registry(evaluation: dict, explicit: str | None) -> str:
    if explicit:
        return explicit
    nodes = leaves(evaluation)
    methods = {node["method"] for node in nodes}
    if methods == {"registry"}:
        text = registry_snippet(nodes)
        sz = [node["name"] for node in nodes if isinstance(snippet_value(node), str)]
        if sz:
            text += "\nString values above are REG_SZ.\n"
        return text
    if methods == {"secedit"}:
        return secedit_snippet(nodes)
    raise SystemExit("missing registry remediation text for a non-registry check")


def intune_text(gpo: str, oma: str | None) -> str:
    path = gpo.split("\n", 1)[0]
    if oma:
        return "Settings Catalog: " + path + "\nOMA-URI: " + oma
    return (
        "Settings Catalog mirrors this Group Policy path:\n"
        + path
        + "\nNo OMA-URI is cited because it was not confirmed for this setting."
    )


def ck(
    cid: str,
    title: str,
    severity: str,
    module: str,
    refs: list,
    rationale: str,
    evaluation: dict,
    gpo: str,
    conflict: str = "",
    applicability: str = "",
    summary: str = "",
    oma: str | None = None,
    registry_text: str | None = None,
) -> dict:
    verified = any(ref["mapping"] == "verified" for ref in refs)
    if not summary:
        summary = "Apply the Group Policy or the snippet below."
    return {
        "id": cid,
        "title": title,
        "severity": severity,
        "mapping": "verified" if verified else "unverified",
        "windows11_carryover": "unverified",
        "module": {"id": module},
        "references": refs,
        "rationale": rationale + " " + CARRY,
        "conflict_note": conflict,
        "applicability_note": applicability,
        "evaluation": evaluation,
        "remediation": {
            "summary": summary.rstrip() + NOT_APPLIED,
            "gpo": gpo,
            "intune": intune_text(gpo, oma),
            "registry": remediation_registry(evaluation, registry_text),
        },
    }


def service_text(name: str, start_word: str) -> str:
    mapping = {"Disabled": "disabled", "Manual": "demand", "Automatic": "auto"}
    return (
        "v0.1 does not change services. A local administrator can set the start type with:\n"
        f"sc.exe config {name} start= {mapping[start_word]}\n"
        "The space after start= is required by sc.exe.\n"
    )


def build_checks() -> list:
    checks = []
    checks.append(ck(
        "GS-W11-001",
        "Password history remembers 24 passwords",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A1"), gspp("BER.6.2", note="The control requires blocking reuse and does not fix a history depth. Depth 24 is the Hilfsmittel value.")],
        "The Hilfsmittel sets Enforce password history to 24 passwords remembered.",
        sec("PasswordHistorySize", "equals", 24),
        "Computer Configuration/Windows Settings/Security Settings/Account Policies/Password Policy\nEnforce password history: 24 passwords remembered",
        applicability=DOMAIN_NOTE,
    ))
    checks.append(ck(
        "GS-W11-002",
        "Minimum password length is at least 10 characters",
        "medium",
        "SYS.2.1",
        [
            komp("SYS.2.1.A1", "Option 2 in the Hilfsmittel is 10 to 12 characters. Option 1 (passphrase) is 20 to 25. The scored floor is 10 so both options pass."),
            gspp("BER.6.4", mapping="unverified", note="Guidance says a length under 14 is not recommended when no other measures exist. 10 is weaker than that sentence, so this citation is unverified."),
        ],
        "Password complexity is not scored on its own. The passphrase option wants complexity disabled, and the complex-password option wants it enabled.",
        sec("MinimumPasswordLength", "greater_or_equal", 10),
        "Computer Configuration/Windows Settings/Security Settings/Account Policies/Password Policy\nMinimum password length: at least 10 (Hilfsmittel option 2 is 10-12; option 1 is 20-25)",
        conflict="Grundschutz++ BER.6.4 says a length under 14 is not recommended when no other measures are in place. This check uses the Hilfsmittel floor of 10 so option 2 is not failed. The BER.6.4 citation is unverified.",
        applicability=DOMAIN_NOTE,
    ))
    checks.append(ck(
        "GS-W11-003",
        "Minimum password age is at least 1 day",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A1")],
        "The Hilfsmittel sets Minimum password age to 1 day so a user cannot cycle the history in one sitting.",
        sec("MinimumPasswordAge", "greater_or_equal", 1),
        "Computer Configuration/Windows Settings/Security Settings/Account Policies/Password Policy\nMinimum password age: 1 day",
        applicability=DOMAIN_NOTE,
    ))
    checks.append(ck(
        "GS-W11-004",
        "Maximum password age is 365 days",
        "low",
        "SYS.2.1",
        [
            komp("SYS.2.1.A1", "The Hilfsmittel recommends 365 days."),
            gspp("BER.6.5", mapping="unverified", note="BER.6.5 says a password change should happen only for a specific reason. A fixed maximum age conflicts with that statement."),
        ],
        "The scored value is the Hilfsmittel recommendation of 365 days under SYS.2.1.A1.",
        sec("MaximumPasswordAge", "equals", 365),
        "Computer Configuration/Windows Settings/Security Settings/Account Policies/Password Policy\nMaximum password age: 365 days",
        conflict="The Hilfsmittel for SYS.2.1.A1 recommends a maximum password age of 365 days. Grundschutz++ BER.6.5 (catalog 2026-09-24) says password changes should be made only when there is a specific reason. This check scores the Hilfsmittel value. The BER.6.5 citation is unverified. Severity is low because the documents disagree.",
        applicability=DOMAIN_NOTE,
    ))
    checks.append(ck(
        "GS-W11-005",
        "Account lockout is 10 attempts and 15 minutes",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A1"), gspp("BER.3.10", note="The control is parameterized and does not fix the number 10. The threshold and the 15 minute windows are the Hilfsmittel values.")],
        "The Hilfsmittel sets the lockout threshold to 10 invalid attempts, the duration to 15 minutes, and the reset counter to 15 minutes.",
        allof([
            sec("LockoutBadCount", "equals", 10),
            sec("LockoutDuration", "equals", 15),
            sec("ResetLockoutCount", "equals", 15),
        ]),
        "Computer Configuration/Windows Settings/Security Settings/Account Policies/Account Lockout Policy\nAccount lockout threshold: 10\nAccount lockout duration: 15 minutes\nReset account lockout counter after: 15 minutes",
        applicability=DOMAIN_NOTE,
    ))
    checks.append(ck(
        "GS-W11-006",
        "Guest account is disabled",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A16"), gspp("KONF.2.4", note="Guidance names unneeded identities as an example of a function to disable.")],
        "The Hilfsmittel disables the Guest account under SYS.2.1.A16.",
        sec("EnableGuestAccount", "equals", 0),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nAccounts: Guest account status: Disabled",
    ))
    checks.append(ck(
        "GS-W11-007",
        "Ctrl+Alt+Del is required for logon",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A1")],
        "The Hilfsmittel sets Interactive logon: Do not require CTRL+ALT+DEL to Disabled, which stores DisableCAD as 0.",
        reg(POL, "DisableCAD", "equals", 0),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nInteractive logon: Do not require CTRL+ALT+DEL: Disabled",
    ))
    checks.append(ck(
        "GS-W11-008",
        "Cached domain logons are 4 or fewer",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A1"), gspp("BER.3.20", note="Guidance names the Protected Users group as one Windows implementation. This check scores the Hilfsmittel cache limit. A pass does not show that accounts are members of Protected Users.")],
        "The Hilfsmittel says the number of previous logons to cache should be 4 or fewer. The registry value is a string and is compared numerically.",
        reg(r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon", "CachedLogonsCount", "less_or_equal", 4),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nInteractive logon: Number of previous logons to cache: 4 or fewer",
        registry_text=(
            "Windows Registry Editor Version 5.00\n\n"
            "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon]\n"
            '"CachedLogonsCount"="4"\n'
        ),
    ))
    checks.append(ck(
        "GS-W11-009",
        "Machine inactivity limit is 600 to 900 seconds",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A1", "The Hilfsmittel allows 600 to 900 seconds and explicitly excludes 0."), gspp("BER.3.12", note="The control is parameterized. Guidance gives 5 to 15 minutes as an example. The scored range is the Hilfsmittel value.")],
        "Interactive logon: Machine inactivity limit must be inside 600 to 900 seconds. Zero means the limit is off and fails this check.",
        reg(POL, "InactivityTimeoutSecs", "in_range", [600, 900]),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nInteractive logon: Machine inactivity limit: 600 to 900 seconds, not 0",
    ))
    checks.append(ck(
        "GS-W11-010",
        "Diagnostic data level is 0 (Security)",
        "high",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A4", "The Hilfsmittel lists 0 - Security for Enterprise, or 1 - Required where 0 is not effective."), gspp("KONF.2.4", note="Guidance names telemetry services as an example of a function to disable.")],
        "The Hilfsmittel recommends Allow Telemetry 0 - Security where that value is honored. This check expects 0 and does not weaken the expected value to 1.",
        reg(r"SOFTWARE\Policies\Microsoft\Windows\DataCollection", "AllowTelemetry", "equals", 0),
        "Computer Configuration/Administrative Templates/Windows Components/Data Collection and Preview Builds\nAllow Telemetry: Enabled, 0 - Security",
        applicability=(
            "Microsoft documents value 0 (Security) as applying to Windows 10 Enterprise, Education, and Server, and as treated as 1 on other devices. "
            "The Policy CSP applicability line lists Windows 10 version 1507 and later and does not name Windows 11. "
            "The UI name is now Allow Diagnostic Data. windows11_carryover stays unverified."
        ),
        oma="./Device/Vendor/MSFT/Policy/Config/System/AllowTelemetry",
    ))
    checks.append(ck(
        "GS-W11-011",
        "Device name is not sent in diagnostic data",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A4")],
        "The Hilfsmittel sets Allow device name to be sent in Windows diagnostic data to Disabled. The CSP default is that the device name is not sent, so a missing value passes.",
        reg(r"SOFTWARE\Policies\Microsoft\Windows\DataCollection", "AllowDeviceNameInDiagnosticData", "equals", 0, when_absent="pass"),
        "Computer Configuration/Administrative Templates/Windows Components/Data Collection and Preview Builds\nAllow device name to be sent in Windows diagnostic data: Disabled",
        oma="./Device/Vendor/MSFT/Policy/Config/System/AllowDeviceNameInDiagnosticData",
    ))
    checks.append(ck(
        "GS-W11-012",
        "Connected User Experiences and Telemetry service is disabled",
        "high",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A25"), gspp("KONF.2.4", note="Guidance names telemetry services as an example of a function to disable.")],
        "The Hilfsmittel sets the Connected User Experiences and Telemetry service (DiagTrack) to Disabled.",
        service("DiagTrack", "start_type", "equals", "Disabled"),
        "Computer Configuration/Windows Settings/Security Settings/System Services\nConnected User Experiences and Telemetry: Disabled\nThe Hilfsmittel notes that this policy path is not available in the client-side editor. Set the service start type to Disabled.",
        registry_text=service_text("DiagTrack", "Disabled"),
    ))
    checks.append(ck(
        "GS-W11-013",
        "Diagtrack-Listener autologger is stopped",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A25")],
        "The Hilfsmittel registry table sets Diagtrack-Listener Start to 0.",
        reg(r"SYSTEM\CurrentControlSet\Control\WMI\Autologger\Diagtrack-Listener", "Start", "equals", 0),
        "Performance Monitor / Data Collector Sets / Startup Event Trace Sessions / Diagtrack-Listener: Enabled cleared.\nThe Hilfsmittel also documents the registry value below.",
    ))
    checks.append(ck(
        "GS-W11-014",
        "Microsoft accounts cannot be added or used to sign in",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A6"), gspp("KONF.2.4.2", note="Guidance names sign-in to a cloud directory as a cloud connection to disable when it is not required.")],
        "The Hilfsmittel sets Accounts: Block Microsoft accounts to Users can't add or log on with Microsoft accounts, which is NoConnectedUser 3.",
        reg(POL, "NoConnectedUser", "equals", 3),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nAccounts: Block Microsoft accounts: Users can't add or log on with Microsoft accounts",
    ))
    checks.append(ck(
        "GS-W11-015",
        "Microsoft Defender real-time protection is on",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A6"), komp("SYS.2.2.3.A5", "The Hilfsmittel says SYS.2.2.3.A5 is met by implementing SYS.2.1.A6."), gspp("KONF.7.1", note="The control asks for an automatic malware check when a file is opened or installed. Real-time protection is that indicator. A pass does not prove signatures are current, so KONF.7.6 is not cited.")],
        "The Hilfsmittel sets Turn off real-time protection to Disabled for the office workplace that uses Microsoft Defender. Get-MpPreference DisableRealtimeMonitoring is false in that state. A third-party antivirus product may turn Defender off. This check expects Defender because that is the Hilfsmittel example.",
        defender("DisableRealtimeMonitoring", "equals", False),
        "Computer Configuration/Administrative Templates/Windows Components/Microsoft Defender Antivirus/Real-time Protection\nTurn off real-time protection: Disabled",
        registry_text=(
            "Windows Registry Editor Version 5.00\n\n"
            "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\Windows Defender\\Real-Time Protection]\n"
            '"DisableRealtimeMonitoring"=dword:00000000\n'
        ),
    ))
    checks.append(ck(
        "GS-W11-016",
        "Defender behavior monitoring and downloaded-file scanning are on",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A6"), gspp("KONF.7.1")],
        "The Hilfsmittel enables behavior monitoring and scanning of downloaded files and attachments. Both map to Get-MpPreference properties that are false when the protection is on.",
        allof([
            defender("DisableBehaviorMonitoring", "equals", False),
            defender("DisableIOAVProtection", "equals", False),
        ]),
        "Computer Configuration/Administrative Templates/Windows Components/Microsoft Defender Antivirus/Real-time Protection\nTurn on behavior monitoring: Enabled\nScan all downloaded files and attachments: Enabled",
        registry_text=(
            "Windows Registry Editor Version 5.00\n\n"
            "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\Windows Defender\\Real-Time Protection]\n"
            '"DisableBehaviorMonitoring"=dword:00000000\n'
            '"DisableIOAVProtection"=dword:00000000\n'
        ),
    ))
    checks.append(ck(
        "GS-W11-017",
        "Defender blocks potentially unwanted applications",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A6", "The Hilfsmittel sets Configure detection for potentially unwanted applications to Block.")],
        "PUAProtection 1 is Block. Audit mode (2) does not pass.",
        defender("PUAProtection", "equals", 1),
        "Computer Configuration/Administrative Templates/Windows Components/Microsoft Defender Antivirus\nConfigure detection for potentially unwanted applications: Enabled, Block",
        registry_text=(
            "Windows Registry Editor Version 5.00\n\n"
            "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\Windows Defender]\n"
            '"PUAProtection"=dword:00000001\n'
        ),
    ))
    checks.append(ck(
        "GS-W11-018",
        "Microsoft Defender Antivirus service is running",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A6"), komp("SYS.2.2.3.A5")],
        "WinDefend must be Automatic and Running for the Defender settings above to be in effect. A third-party product may stop this service.",
        allof([
            service("WinDefend", "start_type", "equals", "Automatic"),
            service("WinDefend", "status", "equals", "Running"),
        ]),
        "Services: Windows Defender Antivirus Service (WinDefend), start type Automatic, status Running.",
        registry_text=service_text("WinDefend", "Automatic") + "The service must also be running.\n",
    ))
    checks.append(ck(
        "GS-W11-019",
        "SMBv1 server is disabled",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A16"), gspp("KONF.2.4", note="Guidance names unused network protocols as an example. The Hilfsmittel names SMBv1 specifically.")],
        "The Hilfsmittel sets Configure SMB v1 server to Disabled. That writes LanmanServer SMB1 = 0. Do not set the client-driver policy itself to Disabled, because the Hilfsmittel says that deletes the start type.",
        reg(r"SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters", "SMB1", "equals", 0),
        "Computer Configuration/Administrative Templates/MS Security Guide\nConfigure SMB v1 server: Disabled",
    ))
    checks.append(ck(
        "GS-W11-020",
        "SMBv1 client driver is disabled",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A16"), gspp("KONF.2.4")],
        "The Hilfsmittel sets Configure SMB v1 client driver to Enable the policy and choose Disable driver. That is mrxsmb10 Start = 4.",
        reg(r"SYSTEM\CurrentControlSet\Services\mrxsmb10", "Start", "equals", 4),
        "Computer Configuration/Administrative Templates/MS Security Guide\nConfigure SMB v1 client driver: Enabled, Disable driver (recommended)",
    ))
    checks.append(ck(
        "GS-W11-021",
        "LLMNR multicast name resolution is off",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A16"), gspp("KONF.2.4")],
        "The Hilfsmittel sets Turn off multicast name resolution to Enabled. That writes EnableMulticast = 0. The Hilfsmittel says this covers LLMNR and not mDNS.",
        reg(r"SOFTWARE\Policies\Microsoft\Windows NT\DNSClient", "EnableMulticast", "equals", 0),
        "Computer Configuration/Administrative Templates/Network/DNS Client\nTurn off multicast name resolution: Enabled",
    ))
    checks.append(ck(
        "GS-W11-022",
        "Autorun commands and AutoPlay are disabled",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A16"), gspp("KONF.3.8", note="The control covers automatic mounting and opening of removable media. Autorun and AutoPlay are the Windows settings the Hilfsmittel names.")],
        "The Hilfsmittel sets the default AutoRun behavior to Do not execute any autorun commands (NoAutorun = 1) and Turn off Autoplay to All drives (NoDriveTypeAutoRun = 255).",
        allof([
            reg(r"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer", "NoAutorun", "equals", 1),
            reg(r"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer", "NoDriveTypeAutoRun", "equals", 255),
        ]),
        "Computer Configuration/Administrative Templates/Windows Components/AutoPlay Policies\nSet the default behavior for AutoRun: Enabled, Do not execute any autorun commands\nTurn off Autoplay: Enabled, All drives",
    ))
    checks.append(ck(
        "GS-W11-023",
        "IP source routing is disabled",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A16")],
        "The Hilfsmittel sets both MSS DisableIPSourceRouting policies to the highest protection, which is registry value 2. No Grundschutz++ id is attached because none of the confirmed controls names source routing.",
        allof([
            reg(r"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters", "DisableIPSourceRouting", "equals", 2),
            reg(r"SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters", "DisableIPSourceRouting", "equals", 2),
        ]),
        "Computer Configuration/Administrative Templates/MSS (Legacy)\nMSS: (DisableIPSourceRouting) IP source routing protection level: Highest protection\nMSS: (DisableIPSourceRouting IPv6): Highest protection",
    ))
    checks.append(ck(
        "GS-W11-024",
        "SMB client always requires packet signing",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A18")],
        "The Hilfsmittel enables Microsoft network client: Digitally sign communications (always). The weaker 'if server agrees' setting is not scored.",
        reg(r"SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters", "RequireSecuritySignature", "equals", 1),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nMicrosoft network client: Digitally sign communications (always): Enabled",
    ))
    checks.append(ck(
        "GS-W11-025",
        "SMB server always requires packet signing",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A18")],
        "The Hilfsmittel enables Microsoft network server: Digitally sign communications (always).",
        reg(r"SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters", "RequireSecuritySignature", "equals", 1),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nMicrosoft network server: Digitally sign communications (always): Enabled",
    ))
    checks.append(ck(
        "GS-W11-026",
        "LAN Manager authentication is NTLMv2 only",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A18"), gspp("KONF.2.4", note="Guidance explicitly names NTLMv1 as a protocol to disable when it is not required.")],
        "The Hilfsmittel sets LAN Manager authentication level to Send NTLMv2 response only. Refuse LM and NTLM, which is LmCompatibilityLevel 5.",
        reg(LSA, "LmCompatibilityLevel", "equals", 5),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nNetwork security: LAN Manager authentication level: Send NTLMv2 response only. Refuse LM & NTLM",
    ))
    checks.append(ck(
        "GS-W11-027",
        "NTLM sessions require NTLMv2 and 128-bit encryption",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A18")],
        "The Hilfsmittel requires NTLMv2 session security and 128-bit encryption for NTLM SSP clients and servers. The bitmask is 0x80000 plus 0x20000000, which is 537395200 (0x20080000). Extra bits may be set.",
        allof([
            reg(LSA, "NTLMMinClientSec", "bits_set", NTLM_BITS),
            reg(LSA, "NTLMMinServerSec", "bits_set", NTLM_BITS),
        ]),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nNetwork security: Minimum session security for NTLM SSP based clients: Require NTLMv2 session security, Require 128-bit encryption\nThe same two options for servers.",
    ))
    checks.append(ck(
        "GS-W11-028",
        "LDAP client signing is required",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A18")],
        "The Hilfsmittel sets LDAP client signing requirements to Require signing, which is LDAPClientIntegrity 2.",
        reg(r"SYSTEM\CurrentControlSet\Services\LDAP", "LDAPClientIntegrity", "equals", 2),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nNetwork security: LDAP client signing requirements: Require signing",
    ))
    checks.append(ck(
        "GS-W11-029",
        "TLS 1.0 and TLS 1.1 client protocols are disabled",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A18"), gspp("KONF.2.4", note="Guidance explicitly names TLS 1.1 as a weak algorithm to disable.")],
        "The Hilfsmittel SChannel table sets TLS 1.0 and TLS 1.1 client Enabled to 0 and DisabledByDefault to 1. Server protocols are in the same table and are not part of this check.",
        allof([
            reg(SCHANNEL + r"\TLS 1.0\Client", "Enabled", "equals", 0),
            reg(SCHANNEL + r"\TLS 1.0\Client", "DisabledByDefault", "equals", 1),
            reg(SCHANNEL + r"\TLS 1.1\Client", "Enabled", "equals", 0),
            reg(SCHANNEL + r"\TLS 1.1\Client", "DisabledByDefault", "equals", 1),
        ]),
        "Registry only. The Hilfsmittel says Microsoft does not ship an ADMX for these SChannel protocol values.\nTLS 1.0 Client and TLS 1.1 Client: Enabled 0, DisabledByDefault 1.",
    ))
    checks.append(ck(
        "GS-W11-030",
        "TLS 1.2 client protocol is enabled",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A18")],
        "The Hilfsmittel SChannel table sets TLS 1.2 client Enabled to 1 and DisabledByDefault to 0. Disabling TLS 1.0 must not disable TLS 1.2.",
        allof([
            reg(SCHANNEL + r"\TLS 1.2\Client", "Enabled", "equals", 1),
            reg(SCHANNEL + r"\TLS 1.2\Client", "DisabledByDefault", "equals", 0),
        ]),
        "Registry only. TLS 1.2 Client: Enabled 1, DisabledByDefault 0.",
    ))
    checks.append(ck(
        "GS-W11-031",
        "Anonymous enumeration of SAM accounts and shares is disabled",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A12")],
        "The Hilfsmittel enables Network access: Do not allow anonymous enumeration of SAM accounts and shares. The default allows it. RestrictAnonymous = 1.",
        reg(LSA, "RestrictAnonymous", "equals", 1),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nNetwork access: Do not allow anonymous enumeration of SAM accounts and shares: Enabled",
    ))
    checks.append(ck(
        "GS-W11-032",
        "Network credentials are not stored for later authentication",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A17"), gspp("BER.3.20", note="Guidance names Protected Users as one Windows implementation. This check scores the Hilfsmittel setting DisableDomainCreds.")],
        "The Hilfsmittel enables Network access: Do not allow storage of passwords and credentials for network authentication. That is DisableDomainCreds = 1.",
        reg(LSA, "DisableDomainCreds", "equals", 1),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nNetwork access: Do not allow storage of passwords and credentials for network authentication: Enabled",
    ))
    checks.append(ck(
        "GS-W11-033",
        "Remote Assistance invitations and offers are disabled",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A18"), gspp("KONF.4.4", note="Guidance names remote maintenance functions, including remote clipboard and drive mounting, as something to restrict. Remote Assistance is the Hilfsmittel function scored here.")],
        "The Hilfsmittel says to disable solicited and offered Remote Assistance when the function is not used. fAllowToGetHelp and fAllowUnsolicited are 0.",
        allof([
            reg(TS, "fAllowToGetHelp", "equals", 0),
            reg(TS, "fAllowUnsolicited", "equals", 0),
        ]),
        "Computer Configuration/Administrative Templates/System/Remote Assistance\nConfigure Solicited Remote Assistance: Disabled\nConfigure Offer Remote Assistance: Disabled",
    ))
    checks.append(ck(
        "GS-W11-034",
        "Remote Desktop requires Network Level Authentication",
        "high",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A19"), gspp("KONF.4.3", note="The control requires remote-maintenance authentication. NLA is the Hilfsmittel setting for RDP.")],
        "The Hilfsmittel enables Require user authentication for remote connections by using Network Level Authentication. UserAuthentication = 1. Whether RDP itself is enabled is conditional in the Hilfsmittel and is not a hard failure in v0.1.",
        reg(TS, "UserAuthentication", "equals", 1),
        "Computer Configuration/Administrative Templates/Windows Components/Remote Desktop Services/Remote Desktop Session Host/Security\nRequire user authentication for remote connections by using Network Level Authentication: Enabled",
    ))
    checks.append(ck(
        "GS-W11-035",
        "Remote Desktop uses TLS and high encryption",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A19")],
        "The Hilfsmittel sets the security layer to SSL (SecurityLayer = 2) and the encryption level to High (MinEncryptionLevel = 3).",
        allof([
            reg(TS, "SecurityLayer", "equals", 2),
            reg(TS, "MinEncryptionLevel", "equals", 3),
        ]),
        "Computer Configuration/Administrative Templates/Windows Components/Remote Desktop Services/Remote Desktop Session Host/Security\nRequire use of specific security layer for remote (RDP) connections: Enabled, SSL\nSet client connection encryption level: Enabled, High Level",
    ))
    checks.append(ck(
        "GS-W11-036",
        "Remote Desktop drive redirection is disabled",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A19"), gspp("KONF.4.4", note="Guidance names automatic connection of drives during remote maintenance.")],
        "The Hilfsmittel enables Do not allow drive redirection. fDisableCdm = 1.",
        reg(TS, "fDisableCdm", "equals", 1),
        "Computer Configuration/Administrative Templates/Windows Components/Remote Desktop Services/Remote Desktop Session Host/Device and Resource Redirection\nDo not allow drive redirection: Enabled",
    ))
    checks.append(ck(
        "GS-W11-037",
        "Remote Desktop client does not save passwords",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A19"), gspp("BER.3.20")],
        "The Hilfsmittel enables Do not allow passwords to be saved on the Remote Desktop Connection client. DisablePasswordSaving = 1.",
        reg(TS, "DisablePasswordSaving", "equals", 1),
        "Computer Configuration/Administrative Templates/Windows Components/Remote Desktop Services/Remote Desktop Connection Client\nDo not allow passwords to be saved: Enabled",
    ))
    checks.append(ck(
        "GS-W11-038",
        "User Account Control admin approval mode is on",
        "high",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A20")],
        "The Hilfsmittel enables Run all administrators in Admin Approval Mode. EnableLUA = 1. The default is already 1, so a missing value passes. Turning UAC off fails.",
        reg(POL, "EnableLUA", "equals", 1, when_absent="pass"),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nUser Account Control: Run all administrators in Admin Approval Mode: Enabled",
    ))
    checks.append(ck(
        "GS-W11-039",
        "UAC prompts for admin credentials on the secure desktop",
        "high",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A20")],
        "The Hilfsmittel sets the admin elevation prompt to Prompt for credentials on the secure desktop (ConsentPromptBehaviorAdmin = 1), enables Admin Approval Mode for the built-in Administrator (FilterAdministratorToken = 1), and switches to the secure desktop (PromptOnSecureDesktop = 1). The secure-desktop value defaults to 1, so a missing value passes. The other two default more loosely and fail when missing.",
        allof([
            reg(POL, "ConsentPromptBehaviorAdmin", "equals", 1),
            reg(POL, "FilterAdministratorToken", "equals", 1),
            reg(POL, "PromptOnSecureDesktop", "equals", 1, when_absent="pass"),
        ]),
        "Computer Configuration/Windows Settings/Security Settings/Local Policies/Security Options\nUser Account Control: Behavior of the elevation prompt for administrators in Admin Approval Mode: Prompt for credentials on the secure desktop\nUser Account Control: Admin Approval Mode for the Built-in Administrator account: Enabled\nUser Account Control: Switch to the secure desktop when prompting for elevation: Enabled",
    ))
    checks.append(ck(
        "GS-W11-040",
        "Network logons of local accounts stay filtered by UAC",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A20", "The Hilfsmittel sets Apply UAC restrictions to local accounts on network logons to Enabled when Legacy LAPS is not used.")],
        "Enabled writes LocalAccountTokenFilterPolicy = 0, a filtered token. Value 1 grants a full token and fails. A missing value is the secure default and passes.",
        reg(POL, "LocalAccountTokenFilterPolicy", "equals", 0, when_absent="pass"),
        "Computer Configuration/Administrative Templates/MS Security Guide\nApply UAC restrictions to local accounts on network logons: Enabled",
        applicability="The Hilfsmittel sets this policy to Disabled only while Legacy LAPS is still in use. v0.1 scores the recommendation for systems that do not use Legacy LAPS. Windows LAPS replaced Legacy LAPS for new systems from Windows 11 version 23H2.",
    ))
    checks.append(ck(
        "GS-W11-041",
        "PowerShell script block logging is enabled",
        "high",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A22"), gspp("DET.3.1.2", note="The control says to log executed command lines and names Windows PowerShell in the guidance. Script block logging is the Hilfsmittel setting for the script content.")],
        "The Hilfsmittel enables Turn on PowerShell Script Block Logging. The invocation start/stop option should stay off and is not scored.",
        reg(r"SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging", "EnableScriptBlockLogging", "equals", 1),
        "Computer Configuration/Administrative Templates/Windows Components/Windows PowerShell\nTurn on PowerShell Script Block Logging: Enabled\nLog script block invocation start / stop events: not selected",
    ))
    checks.append(ck(
        "GS-W11-042",
        "PowerShell module logging is enabled",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A22"), gspp("DET.3.1.2")],
        "The Hilfsmittel enables Turn on Module Logging. The module list value * is named in the remediation and is not a separate scored value, because only the enable flag is a single registry value with one expected state.",
        reg(r"SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging", "EnableModuleLogging", "equals", 1),
        "Computer Configuration/Administrative Templates/Windows Components/Windows PowerShell\nTurn on Module Logging: Enabled\nModule Names: *",
        registry_text=(
            "Windows Registry Editor Version 5.00\n\n"
            "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ModuleLogging]\n"
            '"EnableModuleLogging"=dword:00000001\n\n'
            "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ModuleLogging\\ModuleNames]\n"
            '"*"="*"\n'
        ),
    ))
    checks.append(ck(
        "GS-W11-043",
        "PowerShell transcription and invocation headers are enabled",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A22")],
        "The Hilfsmittel enables Turn on PowerShell Transcription and selects Include invocation headers. The output directory is environment-specific and is not scored. Script execution policy is not scored: the Hilfsmittel allows either Disabled or Allow only signed scripts.",
        allof([
            reg(r"SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription", "EnableTranscripting", "equals", 1),
            reg(r"SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription", "EnableInvocationHeader", "equals", 1),
        ]),
        "Computer Configuration/Administrative Templates/Windows Components/Windows PowerShell\nTurn on PowerShell Transcription: Enabled\nInclude invocation headers: selected\nChoose an output directory that users cannot modify.",
    ))
    checks.append(ck(
        "GS-W11-044",
        "Restricted Admin mode is not disabled",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A23"), gspp("KONF.4.1.1", note="The control says to disable forwarding of reusable credentials. The Hilfsmittel registry value keeps Restricted Admin available.")],
        "The Hilfsmittel table sets DisableRestrictedAdmin to 0. Value 0 means Restricted Admin is not disabled. A missing value fails because the Hilfsmittel says the value has to be set on the target system.",
        reg(LSA, "DisableRestrictedAdmin", "equals", 0),
        "Computer Configuration/Administrative Templates/System/Credentials Delegation\nThe Hilfsmittel documents this as a registry value on the RDP target:\nHKLM\\SYSTEM\\CurrentControlSet\\Control\\Lsa DisableRestrictedAdmin = 0",
    ))
    checks.append(ck(
        "GS-W11-045",
        "NTFS last-access timestamps are updated",
        "low",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A24")],
        "The Hilfsmittel tells the administrator to run fsutil behavior set DisableLastAccess 0, which always updates the timestamp. v0.1 scores only 0.",
        reg(r"SYSTEM\CurrentControlSet\Control\FileSystem", "NtfsDisableLastAccessUpdate", "equals", 0),
        "Command documented by the Hilfsmittel (not run by this tool):\nfsutil behavior set DisableLastAccess 0",
        applicability=(
            "On Windows 8 and later the values 2 and 3 are system-managed. The Hilfsmittel text describes 2 as updates enabled and 3 as updates disabled. "
            "Current Microsoft fsutil documentation describes 2 as updates disabled and 3 as updates enabled. "
            "Both descriptions agree that 0 always updates. Many Windows 10 and 11 systems default to 2."
        ),
        registry_text=(
            "The Hilfsmittel sets this with fsutil, which writes:\n"
            "HKLM\\SYSTEM\\CurrentControlSet\\Control\\FileSystem\n"
            "NtfsDisableLastAccessUpdate = 0\n"
        ),
    ))
    checks.append(ck(
        "GS-W11-046",
        "Windows Firewall is enabled for every profile",
        "high",
        "SYS.2.1",
        [
            komp("SYS.2.1.A31", "For normal protection the Hilfsmittel says the default firewall (inbound block, outbound allow) is enough, and that this is not an allow-list."),
            komp("SYS.3.1.A3", "The Hilfsmittel says the Windows firewall is the personal firewall. Laptops used outside the organisation should block outbound traffic even at normal protection. Outbound Block is not scored."),
            gspp("KONF.7.15", note="A pass means the three profiles are enabled. It does not mean an allow-list of connections exists. The control prefers an allow-list."),
        ],
        "EnableFirewall = 1 on Domain, Private (registry name StandardProfile), and Public. The private profile is stored as StandardProfile.",
        allof([
            reg(FW + r"\DomainProfile", "EnableFirewall", "equals", 1),
            reg(FW + r"\StandardProfile", "EnableFirewall", "equals", 1),
            reg(FW + r"\PublicProfile", "EnableFirewall", "equals", 1),
        ]),
        "Computer Configuration/Windows Settings/Security Settings/Windows Defender Firewall with Advanced Security\nDomain, Private, and Public profile: Firewall state On",
    ))
    checks.append(ck(
        "GS-W11-047",
        "Windows Firewall logs dropped packets",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A31", "The Hilfsmittel table sets Log dropped packets to Yes and the size limit to 16384 KB. The size is named in the remediation and is not scored.")],
        "Each profile must log dropped packets. LogFileSize 16384 KB is the Hilfsmittel size and is not a separate pass/fail, so a different size does not fail this check.",
        allof([
            reg(FW + r"\DomainProfile", "LogDroppedPackets", "equals", 1),
            reg(FW + r"\StandardProfile", "LogDroppedPackets", "equals", 1),
            reg(FW + r"\PublicProfile", "LogDroppedPackets", "equals", 1),
        ]),
        "Windows Defender Firewall with Advanced Security, each profile, Logging:\nLog dropped packets: Yes\nSize limit: 16384 KB (recommended, not scored)",
    ))
    checks.append(ck(
        "GS-W11-048",
        "Secure Boot is on",
        "high",
        "SYS.2.1",
        [
            komp("SYS.2.1.A8", "The Hilfsmittel says to check in the UEFI firmware that Secure Boot is enabled. This is not a Group Policy setting."),
            gspp("KONF.2.9", note="The catalog modal verb is KANN. SYS.2.1.A8 is the primary requirement. Guidance mentions UEFI Secure Boot."),
        ],
        "Confirm-SecureBootUEFI must return true. If the cmdlet throws, the result is error, not fail.",
        {"method": "secureboot", "expected": True},
        "UEFI firmware: Secure Boot enabled. There is no Group Policy that turns Secure Boot on.",
        registry_text="Secure Boot is a firmware setting. There is no registry value that turns it on.\n",
    ))
    checks.append(ck(
        "GS-W11-049",
        "BitLocker protects the operating-system volume",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A28"), gspp("KONF.3.2", note="Guidance names Windows BitLocker as an example of storage encryption.")],
        "The operating-system volume ProtectionStatus must be On. Other volumes are not scored.",
        {
            "method": "bitlocker",
            "volume_type": "OperatingSystem",
            "property": "protection_status",
            "operator": "equals",
            "expected": "On",
        },
        "Enable BitLocker on the operating-system volume. The Hilfsmittel discusses client encryption under SYS.2.1.A28. Recovery-key escrow is organisation-specific and is not scored.",
        registry_text=(
            "BitLocker is not enabled by a single registry value.\n"
            "manage-bde -status C:\n"
            "manage-bde -on C: -usedspaceonly\n"
            "v0.1 does not run manage-bde.\n"
        ),
    ))
    checks.append(ck(
        "GS-W11-050",
        "Automatic updates download and schedule the install",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A3"), gspp("KONF.8.1.1", note="The control says to install security updates automatically. AUOptions 4 is the Hilfsmittel option. A WSUS URL is environment-specific and is not scored.")],
        "The Hilfsmittel sets Configure Automatic Updates to option 4, auto download and schedule the install. AUOptions = 4.",
        reg(r"SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU", "AUOptions", "equals", 4),
        "Computer Configuration/Administrative Templates/Windows Components/Windows Update\nConfigure Automatic Updates: Enabled, 4 - Auto download and schedule the install",
    ))
    checks.append(ck(
        "GS-W11-051",
        "Users cannot pause Windows updates",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A3")],
        "The Hilfsmittel enables Remove access to the Pause updates feature. SetDisablePauseUXAccess = 1.",
        reg(r"SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "SetDisablePauseUXAccess", "equals", 1),
        "Computer Configuration/Administrative Templates/Windows Components/Windows Update\nRemove access to \"Pause updates\" feature: Enabled",
    ))
    checks.append(ck(
        "GS-W11-052",
        "OneDrive is not used for file storage",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A15"), gspp("KONF.2.4.2", note="Guidance names automatic synchronisation with a cloud as a connection to disable when it is not required.")],
        "The Hilfsmittel enables Prevent the usage of OneDrive for file storage. DisableFileSyncNGSC = 1.",
        reg(r"SOFTWARE\Policies\Microsoft\Windows\OneDrive", "DisableFileSyncNGSC", "equals", 1),
        "Computer Configuration/Administrative Templates/Windows Components/OneDrive\nPrevent the usage of OneDrive for file storage: Enabled",
    ))
    checks.append(ck(
        "GS-W11-053",
        "User activities are not uploaded",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A15"), gspp("KONF.2.4.2")],
        "The Hilfsmittel sets Allow upload of User Activities to Disabled. UploadUserActivities = 0. The default when the policy is absent is to allow upload, so a missing value fails.",
        reg(r"SOFTWARE\Policies\Microsoft\Windows\System", "UploadUserActivities", "equals", 0),
        "Computer Configuration/Administrative Templates/System/OS Policies\nAllow upload of User Activities: Disabled",
        oma="./Device/Vendor/MSFT/Policy/Config/Privacy/UploadUserActivities",
    ))
    checks.append(ck(
        "GS-W11-054",
        "Clipboard is not synced across devices",
        "medium",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A15"), gspp("KONF.2.4.2")],
        "The Hilfsmittel sets Allow Clipboard synchronization across devices to Disabled. AllowCrossDeviceClipboard = 0.",
        reg(r"SOFTWARE\Policies\Microsoft\Windows\System", "AllowCrossDeviceClipboard", "equals", 0),
        "Computer Configuration/Administrative Templates/System/OS Policies\nAllow Clipboard synchronization across devices: Disabled",
        oma="./Device/Vendor/MSFT/Policy/Config/Privacy/AllowCrossDeviceClipboard",
    ))
    checks.append(ck(
        "GS-W11-055",
        "Microsoft Store application is turned off",
        "low",
        "SYS.2.2.3",
        [komp("SYS.2.2.3.A16")],
        "The Hilfsmittel enables Turn off the Store application. RemoveWindowsStore = 1. The separate policy Disable all apps from Microsoft Store is not scored: the Hilfsmittel wording for that policy is ambiguous.",
        reg(r"SOFTWARE\Policies\Microsoft\WindowsStore", "RemoveWindowsStore", "equals", 1),
        "Computer Configuration/Administrative Templates/Windows Components/Store\nTurn off the Store application: Enabled",
    ))
    checks.append(ck(
        "GS-W11-056",
        "Only administrators install printer drivers",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A15", "The Hilfsmittel enables Limits print driver installation to Administrators.")],
        "RestrictDriverInstallationToAdministrators = 1. After the August 2021 updates, a missing value also means administrators only, so absence passes. Value 0 fails.",
        reg(r"SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint", "RestrictDriverInstallationToAdministrators", "equals", 1, when_absent="pass"),
        "Computer Configuration/Administrative Templates/MS Security Guide\nLimits print driver installation to Administrators: Enabled",
    ))
    checks.append(ck(
        "GS-W11-057",
        "Remote Registry service is disabled",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A16"), gspp("KONF.2.4")],
        "The Hilfsmittel sets Remote Registry to Disabled. The default start type is Manual, which fails this check.",
        service("RemoteRegistry", "start_type", "equals", "Disabled"),
        "Computer Configuration/Windows Settings/Security Settings/System Services\nRemote Registry: Disabled",
        registry_text=service_text("RemoteRegistry", "Disabled"),
    ))
    checks.append(ck(
        "GS-W11-058",
        "Windows PowerShell 2.0 engine is absent or disabled",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A16"), gspp("KONF.2.4")],
        "The Hilfsmittel clears the Windows PowerShell 2.0 feature. Disabled and NotFound both pass. A missing feature row is treated as NotFound. If the feature list itself cannot be read, the result is error.",
        feature("MicrosoftWindowsPowerShellV2Root", "one_of", ["Disabled", "NotFound"]),
        "Windows Features: Windows PowerShell 2.0, including Windows PowerShell 2.0 Engine: cleared.",
        registry_text=(
            "Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -NoRestart\n"
            "v0.1 does not run this command.\n"
        ),
    ))
    checks.append(ck(
        "GS-W11-059",
        "Six Attack Surface Reduction rules are set to block",
        "high",
        "SYS.2.1",
        [komp("SYS.2.1.A6", "The Hilfsmittel sets these six ASR rule GUIDs to 1 (Block). d1e49aac is 0, 1, or 2 and is not scored."), gspp("KONF.7.16", note="Guidance names Defender Exploit Guard as an example of an anti-exploit function.")],
        "Each scored rule value is 1. Audit (2) or off (0) fails. Rules that the Hilfsmittel leaves optional, including rules that need MAPS, are not scored. The Hilfsmittel gives no required MAPS value.",
        allof([reg(ASR_PATH, guid, "equals", 1) for guid in ASR]),
        "Computer Configuration/Administrative Templates/Windows Components/Microsoft Defender Antivirus/Microsoft Defender Exploit Guard/Attack Surface Reduction\nConfigure Attack Surface Reduction rules: Enabled\nEach listed GUID: 1 (Block)",
    ))
    checks.append(ck(
        "GS-W11-060",
        "Logon auditing records success and failure",
        "medium",
        "DET.3",
        [
            gspp("DET.3.1.1", note="The control requires authentication success and failure to be logged. It does not name a Windows audit subcategory. v0.1 maps that outcome to the advanced-audit subcategory Logon and queries its MS-GPAC GUID."),
            komp_unverified("DER.1.A5", "DER.1.A5 says to use built-in detection and points at the SiSyPHuS logging study. It does not name this subcategory, so the citation is unverified."),
        ],
        "auditpol subcategory Logon ({0CCE9215-69AE-11D9-BED3-505054503030}) must be Success and Failure. Collection queries that GUID. If the GUID query fails, the de-DE display name Anmelden is accepted. A subcategory that is still missing is error, not fail.",
        auditpol("Logon", "Success and Failure"),
        "Advanced Audit Policy: Logon/Logoff, Logon: Success and Failure.",
        registry_text=(
            "auditpol /set /subcategory:{0CCE9215-69AE-11D9-BED3-505054503030} /success:enable /failure:enable\n"
            "v0.1 does not run auditpol /set.\n"
        ),
    ))
    checks.append(ck(
        "GS-W11-061",
        "Credential Validation auditing records success and failure",
        "medium",
        "DET.3",
        [
            gspp("DET.3.1.1", note="The control requires authentication success and failure to be logged. Credential Validation is the advanced-audit subcategory for credential checks, queried by its MS-GPAC GUID. The control does not name it."),
            komp_unverified("DER.1.A5", "DER.1.A5 does not name this subcategory. The citation is unverified."),
        ],
        "auditpol subcategory Credential Validation ({0CCE923F-69AE-11D9-BED3-505054503030}) must be Success and Failure. Collection queries that GUID. If the GUID query fails, the de-DE display names Anmeldeinformationen überprüfen and Überprüfung der Anmeldeinformationen are accepted.",
        auditpol("Credential Validation", "Success and Failure"),
        "Advanced Audit Policy: Account Logon, Credential Validation: Success and Failure.",
        registry_text=(
            "auditpol /set /subcategory:{0CCE923F-69AE-11D9-BED3-505054503030} /success:enable /failure:enable\n"
            "v0.1 does not run auditpol /set.\n"
        ),
    ))
    checks.append(ck(
        "GS-W11-062",
        "WinRM client and service reject unencrypted traffic",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A18")],
        "The Hilfsmittel sets Allow unencrypted traffic to Disabled for the WinRM client and the WinRM service. A missing policy value passes because the client default is not to allow unencrypted traffic. Basic authentication and digest authentication are in the same Hilfsmittel table and are not scored here.",
        allof([
            reg(r"SOFTWARE\Policies\Microsoft\Windows\WinRM\Client", "AllowUnencryptedTraffic", "equals", 0, when_absent="pass"),
            reg(r"SOFTWARE\Policies\Microsoft\Windows\WinRM\Service", "AllowUnencryptedTraffic", "equals", 0, when_absent="pass"),
        ]),
        "Computer Configuration/Administrative Templates/Windows Components/Windows Remote Management (WinRM)/WinRM Client\nAllow unencrypted traffic: Disabled\nWinRM Service: Allow unencrypted traffic: Disabled",
    ))
    checks.append(ck(
        "GS-W11-063",
        "Windows Script Host is disabled",
        "medium",
        "SYS.2.1",
        [komp("SYS.2.1.A16", "The Hilfsmittel registry table sets Windows Script Host Settings Enabled to 0 when script execution is not required.")],
        "The Hilfsmittel documents HKLM\\SOFTWARE\\Microsoft\\Windows Script Host\\Settings Enabled = 0. A missing value leaves WSH enabled and fails.",
        reg(r"SOFTWARE\Microsoft\Windows Script Host\Settings", "Enabled", "equals", 0),
        "The Hilfsmittel documents this as a registry value. There is no separate ADMX path in that table.\nWindows Script Host: Enabled = 0 (do not run scripts).",
    ))
    return checks


def lint(catalog: dict) -> None:
    ids = []
    for check in catalog["checks"]:
        for node in leaves(check["evaluation"]):
            if node["method"] != "auditpol":
                continue
            name = node["subcategory"]
            expected_guid = AUDIT_SUBCATEGORY_GUIDS.get(name)
            if expected_guid is None or node.get("subcategory_guid") != expected_guid:
                raise SystemExit(check["id"] + " audit subcategory GUID does not match MS-GPAC for " + name)
        ids.append(check["id"])
        if check["windows11_carryover"] != "unverified":
            raise SystemExit(check["id"] + " must keep windows11_carryover unverified in v0.1")
        if check["module"]["id"] not in MODULE_TITLES:
            raise SystemExit("unknown module on " + check["id"])
        for ref in check["references"]:
            req = ref["requirement_id"]
            if ref["framework"] == "it-grundschutz-kompendium":
                allowed = VERIFIED_KOMP if ref["mapping"] == "verified" else UNVERIFIED_KOMP
            elif ref["framework"] == "grundschutz-plus-plus":
                allowed = VERIFIED_GSPP if ref["mapping"] == "verified" else UNVERIFIED_GSPP
            else:
                raise SystemExit("unknown framework on " + check["id"])
            if req not in allowed:
                raise SystemExit(f"{check['id']} uses {ref['mapping']} id {req} outside the allow list")
    if len(ids) < 40:
        raise SystemExit("expected at least 40 checks")
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate check id")


def passing_actual(node: dict):
    if node["method"] == "secureboot":
        return node["expected"]
    operator = node["operator"]
    expected = node["expected"]
    if operator == "in_range":
        return expected[1]
    if operator == "one_of":
        return expected[0]
    if node["method"] == "secedit":
        return str(expected)
    if node["method"] == "registry" and node["name"] == "CachedLogonsCount":
        return str(expected)
    return expected


def build_evidence(catalog: dict) -> dict:
    registry = []
    secedit = []
    services: dict[str, dict] = {}
    defender = {}
    features = {}
    secureboot = None
    bitlocker = {}
    audit_rows = []
    for check in catalog["checks"]:
        for node in leaves(check["evaluation"]):
            method = node["method"]
            if method == "registry":
                key = (node["path"], node["name"])
                actual = REG_OV.get(key, passing_actual(node))
                if actual is ABSENT:
                    continue
                registry.append({
                    "hive": "HKLM",
                    "path": node["path"],
                    "name": node["name"],
                    "value": actual,
                })
            elif method == "secedit":
                key = (node["section"], node["key"])
                secedit.append({
                    "section": node["section"],
                    "key": node["key"],
                    "value": SEC_OV.get(key, passing_actual(node)),
                })
            elif method == "service":
                row = services.setdefault(node["name"], {
                    "name": node["name"],
                    "start_type": "Manual",
                    "status": "Stopped",
                })
                row[node["property"]] = passing_actual(node)
                if node["name"] in SVC_OV:
                    row.update(SVC_OV[node["name"]])
            elif method == "defender":
                defender[node["property"]] = DEF_OV.get(node["property"], passing_actual(node))
            elif method == "feature":
                features[node["name"]] = FEAT_OV.get(node["name"], passing_actual(node))
            elif method == "secureboot":
                secureboot = passing_actual(node)
            elif method == "bitlocker":
                bitlocker[node["volume_type"]] = BL_OV
            elif method == "auditpol":
                audit_rows.append({
                    "subcategory": node["subcategory"],
                    "subcategory_guid": node["subcategory_guid"],
                    "setting": AUD_OV.get(node["subcategory"], passing_actual(node)),
                })
            else:
                raise SystemExit("no demo evidence for " + method)
    audit_rows.append({
        "subcategory": "Logoff",
        "subcategory_guid": AUDIT_SUBCATEGORY_GUIDS["Logoff"],
        "setting": "Success",
    })
    registry.sort(key=lambda row: (row["path"].lower(), row["name"].lower()))
    secedit.sort(key=lambda row: (row["section"].lower(), row["key"].lower()))
    return {
        "host": {
            "computer_name": "DEMO-WIN11-01",
            "domain": "DEMO.example",
            "os_caption": "Windows 11 Enterprise",
            "os_version": "10.0.26100",
            "os_build": "26100",
        },
        "notes": [
            "Fictional evidence for the offline demo. No real computer was measured.",
            "Values that are not overridden match the catalog expectation so those checks pass.",
        ],
        "registry": registry,
        "secedit": secedit,
        "services": sorted(services.values(), key=lambda row: row["name"].lower()),
        "defender": defender,
        "features": [{"name": name, "state": state} for name, state in sorted(features.items())],
        "secureboot": secureboot,
        "bitlocker": [
            {"mount": "C:", "volume_type": volume_type, "protection_status": status}
            for volume_type, status in bitlocker.items()
        ],
        "auditpol": audit_rows,
    }


def build_catalog() -> dict:
    checks = build_checks()
    seen = []
    modules = []
    for check in checks:
        module_id = check["module"]["id"]
        if module_id not in seen:
            seen.append(module_id)
            modules.append({"id": module_id, "title": MODULE_TITLES[module_id]})
    catalog = {
        "schema_version": "0.1.0",
        "catalog": {
            "id": "grundschutzcheck.windows11.client",
            "title": "Windows 11 client checks for BSI IT-Grundschutz and Grundschutz++",
            "version": "0.1.0",
            "released": "2026-10-21",
            "description": (
                "Read-only checks for a Windows 11 client. Requirement ids are copied from published BSI documents. "
                "Every windows11_carryover value is unverified because the setting values come from the Windows 10 Hilfsmittel."
            ),
            "target": "Windows 11 client",
            "applicability_note": (
                "Concrete values are carried over from Hilfsmittel zur Umsetzung der Anforderungen des "
                "IT-Grundschutz-Kompendiums fuer Windows-Clients, version 1.0, 20 February 2025, written for "
                "Windows 10 version 21H2 and later. BSI has not published a Windows 11 settings matrix. "
                "SYS.2.2.3 in the IT-Grundschutz-Kompendium Edition 2023 applies to Windows 10 and Windows 11. "
                "SiSyPHuS hardening checklists published by BSI address Windows 10 LTSC 2019 (1809). "
                "There is no published BSI Windows 11 SiSyPHuS matrix, so v0.1 does not score one."
            ),
            "sources": [
                {
                    "id": HILF,
                    "title": "Hilfsmittel zur Umsetzung der Anforderungen des IT-Grundschutz-Kompendiums fuer Windows-Clients",
                    "version": "1.0",
                    "released": "2025-02-20",
                    "url": "https://www.bsi.bund.de/SharedDocs/Downloads/DE/BSI/Grundschutz/Hilfsmittel/Hilfsmittel_IT_Grundschutz_Windows_Client.html",
                },
                {
                    "id": KOMP_SRC,
                    "title": "IT-Grundschutz-Kompendium Edition 2023",
                    "version": "2023",
                    "url": "https://www.bsi.bund.de/DE/Themen/Unternehmen-und-Organisationen/Standards-und-Zertifizierung/IT-Grundschutz/IT-Grundschutz-Kompendium/it-grundschutz-kompendium_node.html",
                },
                {
                    "id": GSPP_SRC,
                    "title": "Anwenderkatalog Grundschutz++",
                    "version": "2026-09-24T07:12:39.131983+00:00",
                    "url": "https://github.com/BSI-Bund/Stand-der-Technik-Bibliothek/blob/main/control_layer/Grundschutz%2B%2B/Grundschutz%2B%2B-resolved_catalog.json",
                },
            ],
        },
        "modules": modules,
        "checks": checks,
    }
    lint(catalog)
    return catalog


def dump(document: dict) -> str:
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build or check the GrundschutzCheck catalog.")
    parser.add_argument("--write", action="store_true", help="Write catalog/windows11-client.json and demo/evidence.json")
    parser.add_argument("--check", action="store_true", help="Exit 1 if the committed JSON differs from the builder")
    args = parser.parse_args(argv)
    if not args.write and not args.check:
        args.write = True
    catalog = build_catalog()
    evidence = build_evidence(catalog)
    catalog_text = dump(catalog)
    evidence_text = dump(evidence)
    if args.check:
        current_catalog = CATALOG_PATH.read_text(encoding="utf-8") if CATALOG_PATH.exists() else ""
        current_evidence = EVIDENCE_PATH.read_text(encoding="utf-8") if EVIDENCE_PATH.exists() else ""
        if current_catalog != catalog_text or current_evidence != evidence_text:
            print("catalog or demo evidence is out of date. Run: python3 tools/build_catalog.py --write", file=sys.stderr)
            return 1
        print(f"catalog ok ({len(catalog['checks'])} checks)")
        return 0
    CATALOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    EVIDENCE_PATH.parent.mkdir(parents=True, exist_ok=True)
    CATALOG_PATH.write_text(catalog_text, encoding="utf-8")
    EVIDENCE_PATH.write_text(evidence_text, encoding="utf-8")
    print(f"wrote {CATALOG_PATH} ({len(catalog['checks'])} checks)")
    print(f"wrote {EVIDENCE_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
