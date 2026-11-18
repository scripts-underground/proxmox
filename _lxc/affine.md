---
slug: affine
title: AFFiNE
tags: [knowledge, notes, workspace]
logo: /assets/logos/affine.webp
by: MickLesk
repo: https://github.com/toeverything/AFFiNE
site: https://affine.pro/
port: 3010
cpu: 4
ram: 8192
disk: 20
maintainer: MickLesk
---

Open-source, privacy-first workspace for notes, docs, and knowledge management with offline-first design and end-to-end encryption.

## Notes

- Initial build takes 20-30 minutes due to native module compilation.
- Requires at least 8GB RAM for building and 4GB for runtime.
- The supported all-in-one `affine-web` service owns both HTTP and background jobs. Updates retire only the original unmodified `affine-worker` unit; customized units or effective drop-ins require manual migration.
- Installed `update` commands are frozen snapshots, not automatically refreshed by a repository change. To run the revised migration on an existing container, execute the current source-update path **inside that AFFiNE container** as root:

  ```bash
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/scripts-underground/proxmox/main/scripts/lxc/affine.sh)"
  ```

  This runs the current update hook with the existing maintenance/resource checks, without creating a new container or replacing the frozen `update` command. Repeat the source-update command for retries or future revised hooks; ordinary `update` still runs its installed generation.

## Links

- [Website](https://affine.pro/)
- [GitHub](https://github.com/toeverything/AFFiNE)
- [Documentation](https://affine.pro/docs)
