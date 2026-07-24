---
slug: powerdns
title: PowerDNS
tags: [dns]
logo: /assets/logos/powerdns.webp
by: tremor021
repo: https://github.com/PowerDNS/pdns
site: https://www.powerdns.com/
port: 80
cpu: 1
ram: 1024
disk: 4
maintainer: tremor021
---
The PowerDNS Authoritative Server is a versatile nameserver which supports a large number of backends. These backends can either be plain zone files or be more dynamic in nature. PowerDNS has the ability to give different answers to different geographic regions and can even provide failover for name servers. The web UI Poweradmin is included for easy administration.
## Notes
- PowerDNS Admin credentials saved to ~/poweradmin.creds
- Uses SQLite backend stored at /opt/poweradmin/powerdns.db
- Access Poweradmin at http://IP
