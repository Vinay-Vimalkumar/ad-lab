# Phase 3 Attack 01 - BloodHound Enumeration

## Summary

MITRE ATT&CK: `T1087.002` - Account Discovery: Domain Account.

Status: SharpHound enumeration completed successfully from `braavos` against both `sevenkingdoms.local` and `north.sevenkingdoms.local`.

Screenshots: skipped; command output, BloodHound collection zips, and event evidence were captured in logs/artifacts.

## Commands Run

On `braavos` as `SEVENKINGDOMS\labadmin`:

```powershell
cd C:\attacks
.\SharpHound.exe -c All -d sevenkingdoms.local --OutputDirectory C:\attacks\bloodhound-sevenkingdoms
.\SharpHound.exe -c All -d north.sevenkingdoms.local --OutputDirectory C:\attacks\bloodhound-north
```

## Tool Version

SharpHound reported:

```text
This version of SharpHound is compatible with the 4.3.1 Release of BloodHound
```

Sysmon captured file metadata:

```text
FileVersion: 1.1.1
Description: SharpHound
Product: SharpHound
Company: SpecterOps
OriginalFileName: SharpHound.exe
SHA256=CC19C785702EEA660A1DD7CBF9E4FEF80B41384E8BD6CE26B7229E0251F24272
```

## Targets Enumerated

| Domain | Domain controller discovered | Objects finished |
|---|---|---:|
| `sevenkingdoms.local` | `kingslanding.sevenkingdoms.local` | `138` |
| `north.sevenkingdoms.local` | `winterfell.north.sevenkingdoms.local` | `113` |

## Output Files

BloodHound zips and cache files were pulled back to this directory:

```text
attacks/artifacts/01-bloodhound/
```

Files collected:

```text
20260521045224_BloodHound.zip
20260521045313_BloodHound.zip
20260521045534_BloodHound.zip
20260521045633_BloodHound.zip
NDQyYjdhMjgtOGE4OS00OTU0LWFhNGMtNWY3NDJlYTA1Zjgw.bin
zip-contents.md
```

Zip contents are listed in:

```text
attacks/artifacts/01-bloodhound/zip-contents.md
```

Each BloodHound zip contains the expected collection JSON types: computers, users, groups, containers, domains, GPOs, and OUs.

## Detection Summary

`braavos` Sysmon Event ID `1` captured both SharpHound process executions, including full command lines and binary hashes.

`kingslanding` Security Event ID `4662` records were present in the two-hour query window, but the observed records were not cleanly attributable to SharpHound. No `kingslanding` Sysmon Event ID `1` record for `SharpHound.exe` was expected because the process ran on `braavos`.

Details are in:

```text
attacks/artifacts/01-bloodhound/detection-verified.md
```

## Raw Logs

| Log | Purpose |
|---|---|
| `logs/phase3-attack01-bloodhound.log` | Initial SharpHound execution and fetch to control node |
| `logs/phase3-attack01-capture.log` | Registered stdout/stderr capture for root and child domain runs |
| `logs/phase3-attack01-detection.log` | Sysmon/Security event detection queries |
