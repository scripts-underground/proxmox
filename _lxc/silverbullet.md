---
slug: silverbullet
title: SilverBullet
tags: [notes]
logo: /assets/logos/silverbullet.webp
by: dsiebel
repo: https://github.com/silverbulletmd/silverbullet
site: https://silverbullet.md/
port: 3000
cpu: 1
ram: 512
disk: 2
maintainer: dsiebel
---

A note-taking application that runs as a single binary, with a markdown editor, backlinks, and extensible plug-in system.

## Notes

- Access the web UI at `http://<ip>:3000` to start using SilverBullet.
- By default, Chromium (for the Runtime API) is not installed. To enable it, SSH into the container and run: `apt install -y chromium` then add `Environment=SB_CHROME_PATH=/usr/bin/chromium` and `Environment=SB_CHROME_DATA_DIR=/opt/silverbullet/space/.chrome-data` to the service file, followed by `systemctl daemon-reload && systemctl restart silverbullet`.
- Data is stored in `/opt/silverbullet/space`.

## Links

- [Website](https://silverbullet.md/)
- [GitHub](https://github.com/silverbulletmd/silverbullet)
