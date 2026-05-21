# Detection Verification - Attack 01 BloodHound Enumeration

MITRE ATT&CK: `T1087.002` - Account Discovery: Domain Account.

## Verified Events

### Sysmon Event ID 1 - Process Create

Verified on `braavos`, where SharpHound executed.

Evidence from `logs/phase3-attack01-detection.log`:

| Host | Event | RecordId | Image | User | Command line |
|---|---:|---:|---|---|---|
| `BRAAVOS.sevenkingdoms.local` | Sysmon `1` | `4065` | `C:\attacks\SharpHound.exe` | `SEVENKINGDOMS\labadmin` | `SharpHound.exe -c All -d sevenkingdoms.local --OutputDirectory C:\attacks\bloodhound-sevenkingdoms` |
| `BRAAVOS.sevenkingdoms.local` | Sysmon `1` | `4256` | `C:\attacks\SharpHound.exe` | `SEVENKINGDOMS\labadmin` | `SharpHound.exe -c All -d north.sevenkingdoms.local --OutputDirectory C:\attacks\bloodhound-north` |

The Sysmon rule name was `Event ID 1 ProcessCreate AD attack tooling`, and the captured binary metadata identified `SharpHound` by file description, product, original filename, SHA256, and import hash.

### Security Event ID 4662 - Directory Service Access

Queried on `kingslanding` with:

```powershell
Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4662; StartTime = (Get-Date).AddHours(-2) }
```

Recent `4662` records were present on `kingslanding`, including RecordId `20490`, but they were not cleanly attributable to the SharpHound runs by subject or timestamp. The reliable direct detection for this execution is the Sysmon Event ID `1` process-create telemetry on `braavos`.

### Kingslanding Sysmon Expectation Check

No `kingslanding` Sysmon Event ID `1` record for `SharpHound.exe` was found. This is expected because SharpHound executed on `braavos`, not on the domain controller.

## Raw Evidence

Raw detection query output:

```text
logs/phase3-attack01-detection.log
```
