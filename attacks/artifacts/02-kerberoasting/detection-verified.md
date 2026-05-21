# Detection Verification - Attack 02 Kerberoasting

## Scope

- Host queried: `kingslanding`
- Log: Windows Security
- Event ID: `4769` Kerberos service ticket requested
- Query window: last 2 hours from `2026-05-21T04:49Z`
- Raw query log: `logs/phase3-attack02-detection.log`

## Confirmed Events

The root-domain Impacket Kerberoast generated Security Event ID `4769` events on `kingslanding` with RC4 ticket encryption (`TicketEncryptionType 0x17`):

| Time UTC | Account | Service | Client | TicketEncryptionType |
| --- | --- | --- | --- | --- |
| 2026-05-21T04:44:04.5346246Z | labadmin@SEVENKINGDOMS.LOCAL | svc_mssql | ::ffff:192.168.56.20 | 0x17 |
| 2026-05-21T04:44:04.5402262Z | labadmin@SEVENKINGDOMS.LOCAL | svc_web | ::ffff:192.168.56.20 | 0x17 |
| 2026-05-21T04:44:04.5457392Z | labadmin@SEVENKINGDOMS.LOCAL | svc_cifs | ::ffff:192.168.56.20 | 0x17 |

## Summary

Detection is verified for the root-domain Kerberoasting activity. The high-signal indicator is Event ID `4769` where service accounts were requested with `TicketEncryptionType 0x17`, consistent with RC4-HMAC TGS material used for Kerberoasting.

The child-domain `svc_ldap` roast targeted `winterfell` at `192.168.56.12`; this note records the requested `kingslanding` check.
