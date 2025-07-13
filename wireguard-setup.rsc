# ================================================================
# MikroTik WireGuard Setup Script
# Только настройка WireGuard сервера
# Версия: 1.0
# Совместимость: RouterOS 7.x
# ================================================================

/system script
add name=setup-wireguard-complete policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive source="\r\
\n:put \"=== Starting WireGuard setup ===\"; \r\
\n:local iface \"ether1\"; \r\
\n\r\
\n# Get system identity first\r\
\n:local systemName [/system identity get name]; \r\
\n:local peerName (\"etalon-\" . \$systemName); \r\
\n:put \"System identity: \$systemName\"; \r\
\n:put \"WireGuard peer name: \$peerName\"; \r\
\n\r\
\n# Get IP address\r\
\n:local ip [/ip address get [/ip address find interface=\$iface] address]; \r\
\n:if ([:len \$ip] = 0) do={ \r\
\n    :put \"ERROR: No IP address found on interface \$iface\"; \r\
\n    :error \"IP not found\"; \r\
\n} \r\
\n\r\
\n# Extract IP components\r\
\n:local ipWithoutMask [:pick \$ip 0 [:find \$ip \"/\"]]; \r\
\n:local firstDot [:find \$ipWithoutMask \".\"]; \r\
\n:local secondDot [:find \$ipWithoutMask \".\" (\$firstDot + 1)]; \r\
\n:local thirdDot [:find \$ipWithoutMask \".\" (\$secondDot + 1)]; \r\
\n:local thirdOctet [:tonum [:pick \$ipWithoutMask (\$secondDot + 1) \$thirdDot]]; \r\
\n:put \"Original IP: \$ipWithoutMask\"; \r\
\n:put \"Third octet: \$thirdOctet\"; \r\
\n\r\
\n# Calculate WireGuard third octet\r\
\n:local wgThirdOctet; \r\
\n:if ((\$thirdOctet + 1) <= 254) do={ \r\
\n    :set wgThirdOctet (\$thirdOctet + 1); \r\
\n    :put \"Using third octet + 1: \$wgThirdOctet\"; \r\
\n} else={ \r\
\n    :set wgThirdOctet (\$thirdOctet - 1); \r\
\n    :put \"Third octet + 1 exceeds 254, using third octet - 1: \$wgThirdOctet\"; \r\
\n}; \r\
\n\r\
\n# Build WireGuard addresses\r\
\n:local wgServerAddress (\"10.0.\" . \$wgThirdOctet . \".1/24\"); \r\
\n:local wgClientAddress (\"10.0.\" . \$wgThirdOctet . \".2/32\"); \r\
\n:local wgClientDNS (\"10.0.\" . \$wgThirdOctet . \".1\"); \r\
\n:local wgNetwork (\"10.0.\" . \$wgThirdOctet . \".0\"); \r\
\n:put \"WireGuard server address: \$wgServerAddress\"; \r\
\n:put \"WireGuard client address: \$wgClientAddress\"; \r\
\n:put \"WireGuard client DNS: \$wgClientDNS\"; \r\
\n:put \"WireGuard network: \$wgNetwork\"; \r\
\n:put \"Client endpoint: \$ipWithoutMask\"; \r\
\n\r\
\n# Remove existing WireGuard interfaces\r\
\n:local existingWG [/interface wireguard find where name=\"wireguard1\"]; \r\
\n:if ([:len \$existingWG] > 0) do={ \r\
\n    :put \"Removing existing wireguard1 interface...\"; \r\
\n    /interface wireguard remove \$existingWG; \r\
\n}; \r\
\n\r\
\n# Create WireGuard interface\r\
\n:put \"Creating WireGuard interface...\"; \r\
\n/interface wireguard add listen-port=58800 mtu=1420 name=wireguard1; \r\
\n:put \"WireGuard interface created: wireguard1 on port 58800\"; \r\
\n\r\
\n# Remove existing peers with dynamic name\r\
\n:local existingPeers [/interface wireguard peers find where name=\$peerName]; \r\
\n:if ([:len \$existingPeers] > 0) do={ \r\
\n    :put \"Removing existing WireGuard peer: \$peerName\"; \r\
\n    /interface wireguard peers remove \$existingPeers; \r\
\n}; \r\
\n\r\
\n# Create WireGuard peer with dynamic name\r\
\n:put \"Creating WireGuard peer: \$peerName\"; \r\
\n/interface wireguard peers add allowed-address=\$wgClientAddress client-address=\$wgClientAddress client-dns=\$wgClientDNS client-endpoint=\$ipWithoutMask client-keepalive=20s interface=wireguard1 name=\$peerName private-key=\"yBH6FuWCJN8UoLgiOXq+6RfVfMp8FjsontXG4Kd2X1U=\" public-key=\"E15TxSMx23KpWcU8EY5g3Qw8IdQ7NITYakimF2L1Z3k=\"; \r\
\n:put \"WireGuard peer created: \$peerName\"; \r\
\n\r\
\n# Remove existing IP address on wireguard1\r\
\n:local existingIP [/ip address find where interface=\"wireguard1\"]; \r\
\n:if ([:len \$existingIP] > 0) do={ \r\
\n    :put \"Removing existing IP address from wireguard1...\"; \r\
\n    /ip address remove \$existingIP; \r\
\n}; \r\
\n\r\
\n# Add IP address to WireGuard interface\r\
\n:put \"Adding IP address to WireGuard interface...\"; \r\
\n/ip address add address=\$wgServerAddress interface=wireguard1 network=\$wgNetwork; \r\
\n:put \"IP address added: \$wgServerAddress\"; \r\
\n\r\
\n# Add WireGuard firewall rule\r\
\n:local wgPort 58800; \r\
\n:local existingWGRules [/ip firewall filter find where comment=\"WireGuard\" and dst-port=\$wgPort]; \r\
\n:if ([:len \$existingWGRules] = 0) do={ \r\
\n    :local allRules [/ip firewall filter find where chain=input]; \r\
\n    :if ([:len \$allRules] >= 4) do={ \r\
\n        :local insertId [:pick \$allRules 4]; \r\
\n        /ip firewall filter add chain=input action=accept dst-port=\$wgPort protocol=udp comment=\"WireGuard\" place-before=\$insertId; \r\
\n        :put \"Added WireGuard firewall rule: UDP port \$wgPort\"; \r\
\n    } else={ \r\
\n        /ip firewall filter add chain=input action=accept dst-port=\$wgPort protocol=udp comment=\"WireGuard\"; \r\
\n        :put \"Added WireGuard firewall rule at end: UDP port \$wgPort\"; \r\
\n    }; \r\
\n} else={ \r\
\n    :put \"WireGuard firewall rule already exists\"; \r\
\n}; \r\
\n\r\
\n:put \"=== WireGuard setup completed! ===\"; \r\
\n:put \"Interface: wireguard1 (port 58800)\"; \r\
\n:put \"Server address: \$wgServerAddress\"; \r\
\n:put \"Client address: \$wgClientAddress\"; \r\
\n:put \"Client DNS: \$wgClientDNS\"; \r\
\n:put \"Client endpoint: \$ipWithoutMask:58800\"; \r\
\n:put \"Peer name: \$peerName\";"

/system script run setup-wireguard-complete