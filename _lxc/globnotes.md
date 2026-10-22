---
slug: globnotes
title: Globnotes
tags: [notes, markdown]
logo: /assets/logos/globnotes.webp
by: alexindigo
repo: https://github.com/alexindigo/globnotes
site: https://github.com/alexindigo/globnotes
port: 80
cpu: 2
ram: 2048
disk: 8
maintainer: alexindigo
---

Globnotes is a self-hosted Markdown note-taking app where a note's title is its
path. Browse, search, and edit Obsidian vaults and nested Markdown trees in a
browser, using either Source or WYSIWYG editing. Notes are ordinary files;
application settings and the SQLite search index live separately in persistent
application state.

### Getting started

The script installs the released application natively with its source-pinned
Deno runtime on Debian 13. Open `http://<LXC-IP>/` on port **80** and complete the
first-run setup wizard to choose authentication. No default application password
is provisioned. Plain HTTP works directly; a reverse proxy or TLS certificate is
not an installation prerequisite.

The service runs as the dedicated `globnotes` account. Its source and runtime are
in `/opt/globnotes`, while the notes vault is `/var/lib/globnotes/notes`.
Configure the service through `/etc/globnotes/env`, then restart it with
`systemctl restart globnotes`. This is a systemd **EnvironmentFile**, not a shell
script. The installer-owned revision file in `/opt/globnotes/runtime/release.env`
is separate from operator settings.

The released `deno.lock` stays root-owned and unchanged through the frozen build.
The service uses a separate generated lock in
`/opt/globnotes/runtime/dependency-lock/deno.lock`, inside a private directory owned
by `globnotes`. Deno can record approved cached plugin imports there without
making the application root writable. Each release seeds its own runtime lock
from its released dependency metadata; plugin integrity entries are not merged
between release generations. Code rollback restores that generation's runtime
lock along with its executable and source.

### Choosing a persistent application-state directory

By default, state is stored in `/var/lib/globnotes/notes/.globnotes`, the
application's hidden directory inside the notes vault. To select a separate
directory at installation, prefix the complete install command with
`GLOBNOTES_INDEX_PATH`:

```bash
GLOBNOTES_INDEX_PATH=/var/lib/globnotes/state bash -c "$(curl -fsSL https://raw.githubusercontent.com/scripts-underground/proxmox/main/scripts/lxc/globnotes.sh)"
```

Paths with spaces can be quoted normally:

```bash
GLOBNOTES_INDEX_PATH='/var/lib/globnotes/app state' bash -c "$(curl -fsSL https://raw.githubusercontent.com/scripts-underground/proxmox/main/scripts/lxc/globnotes.sh)"
```

This is a path **inside the LXC**. It does not create a Proxmox host bind mount or
map a NAS directory. Prepare any mounts separately and give the `globnotes`
account read/write/traverse access inside the container. Missing directories are
created for that account; existing notes, mounts and their ownership are
preserved. Use an absolute state path disjoint from the notes vault (apart from
the default `.globnotes`), code, configuration and Deno cache. The installer
rejects overlapping locations before installation effects.

An explicit state location is saved in `/etc/globnotes/env` and retained through
updates. Changing it later is an operator-managed relocation: the updater does
not copy or relocate state. Apply persistent-root configuration changes to the
service before running an update.

### Persistence, backups and updates

Back up both the **notes vault** and the **entire application-state directory**.
Despite its name, `GLOBNOTES_INDEX_PATH` contains persistent authentication and
settings, SQLite database/WAL/SHM files, branding, custom plugins and their core
state. It is not a disposable search cache. Preserve `/etc/globnotes/env` with
your deployment configuration. Take consistent backups with the service stopped
or an appropriate filesystem/database snapshot.

The built-in backup plugin also keeps vault-side history and ledger files.
Moving core state does not move all plugin-related material out of the vault;
include those vault-side files in backups as well.

Run `update` inside the LXC to install a newer published stable release. Updates
preserve notes, state and operator environment, and replace the complete built
code/runtime tree. Source and runtime downloads are validated first. The service
then stops while an independent copy of the effective `DENO_DIR` cache is prepared
and the new release is built. Cached plugin imports are retained; cache size can
grow with plugin use. The default cache is `/var/cache/globnotes`.

A no-update check does not stop the service. A failed build or publication restores
the prior code/cache and prior running state; persistent user data is never rolled
back over new writes. The installed-version marker advances only after the new
service reports the selected version and revision. Successful updates immediately
remove their own retired code/cache trees. An incomplete recovery reports retained
recovery paths for inspection.

This script creates fresh native-Deno installations and updates that layout. It
does not migrate older Python-based installations or their data.
