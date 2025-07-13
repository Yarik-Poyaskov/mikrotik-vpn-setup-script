# ================================================================
# MikroTik OpenVPN Setup Script
# Только настройка OpenVPN серверов
# Версия: 1.0
# Совместимость: RouterOS 7.x
# ================================================================

# First run the cleanup
/system script
add name=cleanup-ovpn-servers policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive source="\r\
\n:put \"=== OVPN Server Cleanup ===\"; \r\
\n:local existingOVPNServers [/interface ovpn-server server find]; \r\
\n:put (\"Found \" . [:len \$existingOVPNServers] . \" OVPN servers\"); \r\
\n:if ([:len \$existingOVPNServers] > 0) do={ \r\
\n    :put \"Listing existing OVPN servers:\"; \r\
\n    :foreach serverId in=\$existingOVPNServers do={ \r\
\n        :local serverInfo [/interface ovpn-server server get \$serverId]; \r\
\n        :local serverName [:tostr (\$serverInfo->\"name\")]; \r\
\n        :put (\"  - Server ID: \" . \$serverId . \", Name: \" . \$serverName); \r\
\n    }; \r\
\n    :put \"Attempting to remove servers...\"; \r\
\n    :do { \r\
\n        /interface ovpn-server server remove \$existingOVPNServers; \r\
\n        :put \"Successfully removed all OVPN servers!\"; \r\
\n    } on-error={ \r\
\n        :put \"Failed to remove servers via find method, trying brute force...\"; \r\
\n        :for i from=10 to=0 step=-1 do={ \r\
\n            :do { \r\
\n                /interface ovpn-server server remove \$i; \r\
\n                :put (\"Removed server at index: \" . \$i); \r\
\n            } on-error={ \r\
\n            }; \r\
\n        }; \r\
\n    }; \r\
\n} else={ \r\
\n    :put \"No OVPN servers found.\"; \r\
\n}; \r\
\n:local remainingServers [/interface ovpn-server server find]; \r\
\n:put (\"Remaining servers after cleanup: \" . [:len \$remainingServers]); \r\
\n:put \"=== OVPN Cleanup completed ===\";"

# Then run the main setup
/system script
add name=setup-ovpn-main policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive source="\r\
\n:put \"=== Starting OVPN setup ===\"; \r\
\n:local iface \"ether1\"; \r\
\n:local keyPassword \"11111111\"; \r\
\n:local ip [/ip address get [/ip address find interface=\$iface] address]; \r\
\n:if ([:len \$ip] = 0) do={ \r\
\n    :put \"ERROR: No IP address found on interface \$iface\"; \r\
\n    :error \"IP not found\"; \r\
\n} \r\
\n:local cn [:pick \$ip 0 [:find \$ip \"/\"]]; \r\
\n:put \"Generating certificates for CN=\$cn\"; \r\
\n\r\
\n# Remove existing certificates\r\
\n:foreach cert in={\"CA\";\"server\";\"client\"} do={ \r\
\n    :if ([:len [/certificate find where name=\$cert]] > 0) do={ \r\
\n        :put \"Removing existing certificate: \$cert\"; \r\
\n        /certificate remove [find where name=\$cert]; \r\
\n        :delay 1s; \r\
\n    } \r\
\n} \r\
\n\r\
\n:put \"Creating CA certificate...\"; \r\
\n/certificate add name=\"CA\" country=\"UA\" state=\"KYIV\" locality=\"Kyiv\" organization=\"Traffic-Leader\" unit=\"UK\" common-name=\$cn key-size=2048 days-valid=3600 trusted=yes key-usage=key-cert-sign,crl-sign; \r\
\n:delay 2s; \r\
\n/certificate sign CA; \r\
\n:delay 4s; \r\
\n\r\
\n:put \"Creating server certificate...\"; \r\
\n/certificate add name=\"server\" country=\"UA\" state=\"KYIV\" locality=\"Kyiv\" organization=\"Traffic-Leader\" unit=\"UK\" common-name=\$cn key-size=2048 days-valid=3600 trusted=yes key-usage=key-encipherment,tls-server; \r\
\n:put \"Creating client certificate...\"; \r\
\n/certificate add name=\"client\" country=\"UA\" state=\"KYIV\" organization=\"Traffic-Leader\" unit=\"UK\" common-name=\$cn key-size=2048 days-valid=3600 trusted=yes key-usage=tls-client; \r\
\n:delay 2s; \r\
\n\r\
\n:put \"Signing server certificate...\"; \r\
\n/certificate sign server ca=CA; \r\
\n:delay 4s; \r\
\n:put \"Signing client certificate...\"; \r\
\n/certificate sign client ca=CA; \r\
\n:delay 4s; \r\
\n\r\
\n/certificate set [find name=\"server\"] trusted=yes; \r\
\n/certificate set [find name=\"client\"] trusted=yes; \r\
\n\r\
\n:put \"Exporting certificates...\"; \r\
\n:local caExportName (\"CA-\" . \$cn); \r\
\n/certificate export-certificate CA export-passphrase=\$keyPassword file-name=\$caExportName; \r\
\n:local serverExportName (\"server-\" . \$cn); \r\
\n/certificate export-certificate server export-passphrase=\$keyPassword file-name=\$serverExportName; \r\
\n:local clientExportName (\"client-\" . \$cn); \r\
\n/certificate export-certificate client export-passphrase=\$keyPassword file-name=\$clientExportName; \r\
\n:put \"Certificates created and exported with CN=\$cn\"; \r\
\n\r\
\n# Firewall rules\r\
\n:put \"=== Setting up firewall rules ===\"; \r\
\n:local existingOVPNRules [/ip firewall filter find where comment=\"OVPN\"]; \r\
\n:if ([:len \$existingOVPNRules] > 0) do={ \r\
\n    :put \"Found existing OVPN rules:\"; \r\
\n    :foreach ruleId in=\$existingOVPNRules do={ \r\
\n        :local ruleInfo [/ip firewall filter get \$ruleId]; \r\
\n        :put (\"  - Port: \" . [:tostr (\$ruleInfo->\"dst-port\")] . \", Protocol: \" . [:tostr (\$ruleInfo->\"protocol\")] . \", Action: \" . [:tostr (\$ruleInfo->\"action\")]); \r\
\n    }; \r\
\n    :put \"Removing old OVPN rules...\"; \r\
\n    /ip firewall filter remove \$existingOVPNRules; \r\
\n    :put \"Old OVPN rules removed.\"; \r\
\n} else={ \r\
\n    :put \"No existing OVPN rules found.\"; \r\
\n}; \r\
\n\r\
\n:local rules {{\"80\"; \"tcp\"}; {\"80\"; \"udp\"}; {\"1194\"; \"udp\"}; {\"1194\"; \"tcp\"}}; \r\
\n:put \"Adding new OVPN firewall rules...\"; \r\
\n:foreach rule in=\$rules do={ \r\
\n    :local port [:pick \$rule 0]; \r\
\n    :local proto [:pick \$rule 1]; \r\
\n    :local allRules [/ip firewall filter find where chain=input]; \r\
\n    :if ([:len \$allRules] >= 4) do={ \r\
\n        :local insertId [:pick \$allRules 4]; \r\
\n        /ip firewall filter add chain=input action=accept dst-port=\$port protocol=\$proto comment=\"OVPN\" place-before=\$insertId; \r\
\n        :put (\"Added: port=\" . \$port . \", protocol=\" . \$proto . \" (inserted at position 5)\"); \r\
\n    } else={ \r\
\n        /ip firewall filter add chain=input action=accept dst-port=\$port protocol=\$proto comment=\"OVPN\"; \r\
\n        :put (\"Added at end: port=\" . \$port . \", protocol=\" . \$proto); \r\
\n    }; \r\
\n}; \r\
\n\r\
\n# IP Pool and PPP Profile\r\
\n:put \"=== Setting up IP pool and PPP profile ===\"; \r\
\n:local ipWithoutMask [:pick \$ip 0 [:find \$ip \"/\"]]; \r\
\n:local firstDot [:find \$ipWithoutMask \".\"]; \r\
\n:local secondDot [:find \$ipWithoutMask \".\" (\$firstDot + 1)]; \r\
\n:local thirdDot [:find \$ipWithoutMask \".\" (\$secondDot + 1)]; \r\
\n:local thirdOctet [:pick \$ipWithoutMask (\$secondDot + 1) \$thirdDot]; \r\
\n:put \"Extracted third octet: \$thirdOctet\"; \r\
\n\r\
\n:local poolRanges (\"10.0.\" . \$thirdOctet . \".10-10.0.\" . \$thirdOctet . \".200\"); \r\
\n:local localAddress (\"10.0.\" . \$thirdOctet . \".1\"); \r\
\n:put \"Pool ranges: \$poolRanges\"; \r\
\n:put \"Local address: \$localAddress\"; \r\
\n\r\
\n:if ([:len [/ip pool find where name=\"OVPN\"]] > 0) do={ \r\
\n    :put \"Removing existing OVPN pool...\"; \r\
\n    /ip pool remove [find where name=\"OVPN\"]; \r\
\n}; \r\
\n:put \"Creating OVPN IP pool...\"; \r\
\n/ip pool add name=OVPN ranges=\$poolRanges; \r\
\n:put \"OVPN pool created with ranges: \$poolRanges\"; \r\
\n\r\
\n:if ([:len [/ppp profile find where name=\"OVPN\"]] > 0) do={ \r\
\n    :put \"Removing existing OVPN PPP profile...\"; \r\
\n    /ppp profile remove [find where name=\"OVPN\"]; \r\
\n}; \r\
\n:put \"Creating OVPN PPP profile...\"; \r\
\n/ppp profile add name=OVPN local-address=\$localAddress remote-address=OVPN only-one=yes; \r\
\n:put \"OVPN PPP profile created with local-address: \$localAddress\"; \r\
\n\r\
\n# === CREATE OVPN SERVERS ===\r\
\n:put \"=== Creating OVPN servers ===\"; \r\
\n\r\
\n:put \"Creating OVPN server 1 (TCP 1194)...\"; \r\
\n/interface ovpn-server server add auth=sha256,sha512 certificate=server cipher=aes128-cbc,aes128-gcm default-profile=OVPN disabled=no name=ovpn-server1 require-client-certificate=yes tls-version=only-1.2; \r\
\n:put \"OVPN server 1 created: TCP port 1194\"; \r\
\n\r\
\n:put \"Creating OVPN server 2 (UDP 1194)...\"; \r\
\n/interface ovpn-server server add auth=sha256,sha512 certificate=server cipher=aes128-cbc,aes128-gcm default-profile=OVPN disabled=no name=ovpn-server2 protocol=udp require-client-certificate=yes tls-version=only-1.2; \r\
\n:put \"OVPN server 2 created: UDP port 1194\"; \r\
\n\r\
\n:put \"Creating OVPN server 3 (UDP 80)...\"; \r\
\n/interface ovpn-server server add auth=sha256,sha512 certificate=server cipher=aes128-cbc,aes128-gcm default-profile=OVPN disabled=no name=ovpn-server3 port=80 protocol=udp require-client-certificate=yes tls-version=only-1.2; \r\
\n:put \"OVPN server 3 created: UDP port 80\"; \r\
\n\r\
\n:put \"Creating OVPN server 4 (TCP 80)...\"; \r\
\n/interface ovpn-server server add auth=sha256,sha512 certificate=server cipher=aes128-cbc,aes128-gcm default-profile=OVPN disabled=no name=ovpn-server4 port=80 require-client-certificate=yes tls-version=only-1.2; \r\
\n:put \"OVPN server 4 created: TCP port 80\"; \r\
\n\r\
\n:put \"=== OpenVPN setup completed successfully! ===\"; \r\
\n:put \"Created 4 new OVPN servers:\"; \r\
\n:put \"  - ovpn-server1: TCP port 1194\"; \r\
\n:put \"  - ovpn-server2: UDP port 1194\"; \r\
\n:put \"  - ovpn-server3: UDP port 80\"; \r\
\n:put \"  - ovpn-server4: TCP port 80\"; \r\
\n:put \"Certificates exported with password: 12345678\";"

# Run both scripts
/system script run cleanup-ovpn-servers
/system script run setup-ovpn-main