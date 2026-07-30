---
slug: splunk-enterprise
title: Splunk Enterprise
tags: [monitoring]
logo: /assets/logos/splunk-enterprise.webp
by: rcastley
repo: https://github.com/splunk/splunk
site: https://www.splunk.com/
port: 8000
cpu: 4
ram: 8192
disk: 40
maintainer: rcastley
---

Log analysis and monitoring platform for searching, analyzing, and visualizing machine-generated data.

## Notes

- You must accept the Splunk General Terms during installation.
- Admin credentials (username/password) are saved to `~/splunk.creds` inside the container.
- Access the web UI at `http://{ip}:8000` and log in with the admin credentials.
- Upstream does not provide an automated update path; updates should be performed manually.

## Links

- [Website](https://www.splunk.com/)
- [Download](https://www.splunk.com/en_us/download/splunk-enterprise.html)
- [Splunk General Terms](https://www.splunk.com/en_us/legal/splunk-general-terms.html)
