---
slug: localsend-nas
title: LocalSend-NAS
tags: [file-sharing, localsend]
logo: /assets/logos/localsend-nas.webp
by: alexindigo
repo: https://github.com/alexindigo/localsend-nas
site: https://github.com/alexindigo/localsend-nas
port: 80
cpu: 1
ram: 512
disk: 4
maintainer: alexindigo
---

LocalSend node for sending and receiving files through a web UI, built for NAS-style deployments. Browse mounted shares, assemble a basket, and send directly to a recipient's LocalSend app, or accept incoming files into a configured share - files never round-trip through your laptop.

## Receiving and settings

Receiving is enabled by default. Incoming requests appear in the web UI, where you can accept into a configured named share or decline. The default countdown is 30 seconds: without a dropbox configured, a request is rejected on timeout, including when no UI is open. With a valid dropbox share configured, the request is automatically accepted into that share when the countdown expires.

Use the gear menu to set the countdown, dropbox destination, and metadata-file visibility. These UI settings are persisted in `/data/settings.json`; they are not installer environment options.

## Browsing shares and choosing receive destinations

The installed share is `files=/opt` (`LOCALSEND_NAS_SHARES=files=/opt`). Readable storage mounted below `/opt` appears in that share's file browser for sending, without adding another share. The application itself is installed at `/opt/localsend-nas`.

Receiving selects a **configured named share root**, not the folder currently open in the file browser. With the installed configuration, selecting `files` receives into `/opt`, including any sender-provided folder structure. To receive directly into an existing mounted `/opt/inbox`, configure it as a separate named share and ensure it is writable by the native service.

Inside the LXC, run `systemctl edit localsend-nas` and add this drop-in:

```ini
[Service]
Environment="LOCALSEND_NAS_SHARES=files=/opt,inbox=/opt/inbox"
```

Save the drop-in, then run `systemctl restart localsend-nas` inside the LXC. Both share roots must already exist as directories. The `inbox` destination will then be available for manual acceptance or as the dropbox setting. These are existing native-service environment settings; prefixing the Proxmox installer command with app environment variables does not configure the installed service.

### Storage access and send-only operation

You provide the mounts and their intended permissions. The native service runs as root inside the container, but unprivileged-LXC UID mapping, mount options, ownership, and ACLs still determine access to host or network storage. This script does not mount storage or change its ownership. Docker's `PUID`/`PGID` settings do not apply to this native service.

A read-only mounted share can be browsed and sent from if it is readable. The receive UI does not filter out every unwritable destination: accepting a request or choosing a dropbox does not grant write access, and an upload can fail without falling back to another share.

For optional send-only operation, use `systemctl edit localsend-nas` inside the LXC to add the following setting (alongside any share override):

```ini
[Service]
Environment="LOCALSEND_NAS_READ_ONLY=1"
```

Run `systemctl restart localsend-nas` after saving. This existing global read-only mode disables receiving; it does not make mounts read-only or stop identity and settings files from being written.

## Network and monitoring

The web UI uses HTTP port 80. LocalSend protocol v2.2 uses HTTPS on TCP 53317 and multicast discovery on UDP 53317 at `224.0.0.167`. Use bridged LXC networking (for example, `vmbr0`) on the peers' LAN, and allow the protocol and multicast traffic through relevant firewalls and switches.

Health endpoints for monitoring are `/api/health` and `/api/selftest`. Their success does not prove destination writability, successful file transfers, or multicast reachability from other devices.

## Persistent state and backups

`/data` stores the device identity, UI settings, and saved manual targets. Actual source and received files live in the configured shares, not in `/data` by default. Back up both `/data` and the share contents, and retain your service drop-ins and mount configuration. Losing the identity changes the device fingerprint.

## Links

- [GitHub](https://github.com/alexindigo/localsend-nas)
- [LocalSend](https://localsend.org)
