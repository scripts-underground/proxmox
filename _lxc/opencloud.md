---
slug: opencloud
title: OpenCloud
tags: [files, cloud]
logo: /assets/logos/opencloud.webp
by: vhsdream
repo: https://github.com/opencloud-eu/opencloud
site: https://opencloud.eu
port: 9200
cpu: 2
ram: 2048
disk: 20
maintainer: vhsdream
---
OpenCloud is the file sharing and collaboration solution of the Heinlein Group.
## Notes
- Valid TLS certificates and fully-qualified domain names behind a reverse proxy for 3 services - OpenCloud (port: 9200), Collabora (port: 9980), and WOPI (port: 9300) are REQUIRED.
- Admin password is randomly generated and stored in the 'idm' section of /etc/opencloud/opencloud.yaml.
- Optional External Apps: extract zip archives from App Store to /etc/opencloud/web/assets/apps.
## Links
- [Website](https://opencloud.eu)
- [GitHub](https://github.com/opencloud-eu/opencloud)
