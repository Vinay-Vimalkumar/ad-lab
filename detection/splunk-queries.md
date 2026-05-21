# Splunk Queries

These SPL searches mirror the Microsoft Sentinel logic in `detection/kql-queries.md`.
Field aliases vary by Splunk Windows TA version, so searches include common raw field names.

## 01 BloodHound Enumeration

```spl
index=* sourcetype="WinEventLog:Security" EventCode=4662 ObjectServer="DS" (AccessMask="*0x100*" OR AccessMask="*0x10*") NOT SubjectUserName="*$"
| bin _time span=10m
| stats dc(ObjectName) as distinct_objects values(ObjectName) as sample_objects values(Computer) as source_hosts by _time SubjectUserName
| where distinct_objects > 200
| rename SubjectUserName as actor
```

```spl
index=* sourcetype="XmlWinEventLog:Microsoft-Windows-Sysmon/Operational" EventCode=3 (DestinationPort=389 OR DestinationPort=636 OR DestinationPort=3268 OR DestinationPort=3269)
| bin _time span=5m
| stats count as ldap_connections dc(DestinationPort) as distinct_dest_ports by _time Computer Image
| where ldap_connections > 50
```

## 02 Kerberoasting

```spl
index=* sourcetype="WinEventLog:Security" EventCode=4769 (TicketEncryptionType="0x17" OR Ticket_Encryption_Type="0x17") NOT (ServiceName="*$" OR Service_Name="*$" OR ServiceName="krbtgt" OR Service_Name="krbtgt") NOT TargetUserName="*$"
| bin _time span=1h
| eval requestor=lower(TargetUserName), service=coalesce(ServiceName, Service_Name), src_ip=coalesce(IpAddress, ClientAddress)
| stats dc(service) as distinct_spns values(service) as spns count as tickets values(src_ip) as source_ips by _time requestor
| where distinct_spns >= 3
```

## 03 AS-REP Roasting

```spl
index=* sourcetype="WinEventLog:Security" EventCode=4768 (PreAuthType=0 OR Pre_Authentication_Type=0 OR PreAuthenticationType=0) (TicketEncryptionType="0x17" OR TicketEncryptionType="0x18" OR Ticket_Encryption_Type="0x17" OR Ticket_Encryption_Type="0x18") NOT TargetUserName="*$"
| bin _time span=30m
| eval account=lower(TargetUserName), client_ip=coalesce(IpAddress, ClientAddress)
| stats count as tgt_requests dc(account) as distinct_accounts values(account) as accounts by _time client_ip
| where distinct_accounts >= 1
```

## 04 NTLM Relay

```spl
index=* sourcetype="WinEventLog:Security" EventCode=4624 LogonType=3 AuthenticationPackageName="NTLM" NOT TargetUserName="*$" NOT TargetUserName IN ("ANONYMOUS LOGON","SYSTEM","LOCAL SERVICE","NETWORK SERVICE")
| eval src_ip=coalesce(IpAddress, WorkstationName)
| search src_ip!="-" src_ip!="127.0.0.1" src_ip!="::1"
| bin _time span=10m
| stats dc(Computer) as distinct_targets values(Computer) as targets count as logons values(TargetUserName) as accounts by _time src_ip
| where distinct_targets >= 2 OR logons >= 10
```

## 05 Pass-the-Hash

```spl
index=* sourcetype="WinEventLog:Security" EventCode=4624 (LogonType=3 OR LogonType=9) AuthenticationPackageName="NTLM" (LogonProcessName="*NtLmSsp*" OR LogonProcessName="*seclogo*") NOT TargetUserName="*$" NOT TargetUserName IN ("ANONYMOUS LOGON","SYSTEM","LOCAL SERVICE","NETWORK SERVICE")
| bin _time span=15m
| eval account=lower(TargetUserName), src_ip=coalesce(IpAddress, WorkstationName)
| stats dc(Computer) as distinct_targets values(Computer) as targets count as logons values(src_ip) as src_ips by _time account
| where distinct_targets >= 2
```

```spl
index=* sourcetype="XmlWinEventLog:Microsoft-Windows-Sysmon/Operational" EventCode=10 TargetImage="*\\lsass.exe" (GrantedAccess="0x1010" OR GrantedAccess="0x1410" OR GrantedAccess="0x1438" OR GrantedAccess="0x143a" OR GrantedAccess="0x1fffff")
| table _time Computer SourceImage TargetImage GrantedAccess
```

## 06 DCSync

```spl
index=* sourcetype="WinEventLog:Security" EventCode=4662 (Properties="*1131f6aa-9c07-11d1-f79f-00c04fc2dcd2*" OR Properties="*1131f6ad-9c07-11d1-f79f-00c04fc2dcd2*") NOT SubjectUserName="*$" NOT SubjectUserName="MSOL_*" NOT SubjectUserName="AAD_*"
| bin _time span=30m
| eval actor=lower(SubjectUserName)
| stats count as repl_requests values(Properties) as guids_seen values(Computer) as source_hosts by _time actor
```

## 07 Golden Ticket

```spl
index=* sourcetype="WinEventLog:Security" EventCode=4769 NOT ServiceName="krbtgt" NOT TargetUserName="*$"
| eval account=lower(TargetUserName), service=coalesce(ServiceName, Service_Name), src_ip=coalesce(IpAddress, ClientAddress)
| search service!="krbtgt"
| bin _time span=1h
| stats count as tgs_requests values(service) as services values(TicketEncryptionType) as enc_types values(src_ip) as source_ips by _time account
| where mvfind(services, "cifs|ldap|host")>=0 OR mvfind(enc_types, "0x17")>=0
```

## 08 Silver Ticket

```spl
index=* sourcetype="WinEventLog:Security" EventCode=4624 LogonType=3 AuthenticationPackageName="Kerberos" NOT TargetUserName="*$" NOT TargetUserName IN ("ANONYMOUS LOGON","SYSTEM","LOCAL SERVICE","NETWORK SERVICE")
| bin _time span=1h
| eval account=lower(TargetUserName), src_ip=coalesce(IpAddress, WorkstationName)
| stats count as logons values(Computer) as hosts values(src_ip) as src_ips by _time account
```

## 09 Unconstrained Delegation Abuse

```spl
index=* sourcetype="WinEventLog:Security" EventCode=4624 LogonType=3 AuthenticationPackageName="Kerberos" TargetUserName="*$" (Computer="*castelblack*" OR Computer="*meereen*" OR Computer="*WEB01*" OR Computer="*APP01*")
| bin _time span=10m
| stats count as logons values(TargetUserName) as machine_accounts values(IpAddress) as src_ips by _time Computer
```

```spl
index=* sourcetype="XmlWinEventLog:Microsoft-Windows-Sysmon/Operational" EventCode=3 (DestinationPort=139 OR DestinationPort=445)
| bin _time span=5m
| stats count as smb_connections by _time Computer DestinationIp DestinationPort
| where smb_connections >= 1
```

## 10 Cross-Forest Trust Abuse

```spl
index=* sourcetype="WinEventLog:Security" (EventCode=4768 OR EventCode=4769 OR EventCode=4624) (TargetDomainName="NORTH" OR TargetDomainName="SEVENKINGDOMS" OR TargetDomainName="north.sevenkingdoms.local" OR TargetDomainName="sevenkingdoms.local")
| eval account=lower(TargetUserName), realm=upper(TargetDomainName), service=coalesce(ServiceName, "")
| bin _time span=1h
| stats count as events values(EventCode) as event_ids values(service) as services values(TicketEncryptionType) as enc_types values(Computer) as target_hosts values(IpAddress) as source_ips by _time account realm
| where mvfind(services, "krbtgt|cifs|ldap|host")>=0 OR mvfind(enc_types, "0x17")>=0
```
