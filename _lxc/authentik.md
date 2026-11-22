---
slug: authentik
title: authentik
tags: [auth]
logo: /assets/logos/authentik.webp
by: Thieneret
repo: https://github.com/goauthentik/authentik
site: https://goauthentik.io/
port: 9000
cpu: 4
ram: 8192
disk: 16
maintainer: Thieneret
---

authentik is an IdP (Identity Provider) and SSO (Single Sign On) platform.

## Notes

- A 1 GB secondary volume is automatically created and attached to the container at /opt/authentik-data. This is required for Authentik's internal file manager to work.
- You will get a Not Found error if initial setup URL doesn't include the trailing forward slash /. Make sure you use the complete url (http://<your server's IP or hostname>:9000/if/flow/initial-setup/) including the trailing forward slash.
- GeoIP/ASN policies need real MaxMind databases. Fresh installs leave the configured paths under `/opt/authentik-data/geoip` unpopulated; test databases are never installed. Follow [authentik's GeoIP setup](https://docs.goauthentik.io/install-config/geoip/), configure `/usr/local/etc/GeoIP.conf` with your MaxMind account, then run `geoipupdate -f /usr/local/etc/GeoIP.conf`. Remove the leading `#` from its crontab entry to enable automatic updates.
- Updates preserve existing databases and configuration. A known-test-database warning requires you to replace that data with real MaxMind databases; the updater never deletes or replaces it automatically.

## Links

- [Website](https://goauthentik.io/)
- [GitHub](https://github.com/goauthentik/authentik)
