---
slug: authentik
title: authentik
tags: [auth-security]
logo: /assets/logos/authentik.webp
by: Thieneret
repo: https://github.com/goauthentik/authentik
site: https://goauthentik.io/
port: 9000
cpu: 4
ram: 4096
disk: 11
maintainer: Thieneret
---

authentik is an IdP (Identity Provider) and SSO (Single Sign On) platform.

## Notes

- A 1 GB secondary volume is automatically created and attached to the container at /opt/authentik-data. This is required for Authentik's internal file manager to work.
- You will get a Not Found error if initial setup URL doesn't include the trailing forward slash /. Make sure you use the complete url (http://<your server's IP or hostname>:9000/if/flow/initial-setup/) including the trailing forward slash.
- If you want automatic GeoIP updates, create a free account at https://www.maxmind.com/en/geolite2/signup, then edit the /usr/local/etc/GeoIP.conf file with your credentials and remove the # in front of the geoipupdate line in the crontab.

## Links

- [Website](https://goauthentik.io/)
- [GitHub](https://github.com/goauthentik/authentik)
