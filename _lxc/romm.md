---
slug: romm
title: RomM
tags: [emulation, gaming]
logo: /assets/logos/romm.webp
by: MickLesk
co_author: [DevelopmentCats, AlphaLawless]
repo: https://github.com/rommapp/romm
site: https://romm.app
port: 80
cpu: 2
ram: 4096
disk: 32
maintainer: MickLesk
---

RomM is a game library manager focused on retro gaming. Emulators, and performance are not included. RomM is designed to work with your existing game library. Features include a modern, responsive web interface, multi-file game, multi-platform support, and direct game streaming in the browser via EmulatorJS and Ruffle.

## Notes

- Access at `http://<ip>`
- Default credentials: register a new admin user at first launch (/login)
- Library path: `/var/lib/romm/library/`
- Place BIOS files in `/var/lib/romm/library/bios/`
- Default resources: 2 CPUs, 4 GiB RAM and a 32 GiB root disk.
- Keep at least 8 GiB available for installation and updates. The installer checks the actual application, state, cache, HOME and temporary filesystems before changing dependencies or stopping update services; paths sharing a filesystem are checked once. Insufficient space stops the operation and preserves existing data.
- The 32 GiB allocation is recommended operational headroom, not ROM-library capacity or a proven bare minimum. A measured empty-library 5.3.0 installation and real 5.3.1 update succeeded on 20 GiB; their one-second observed filesystem high-waters were 4.54 GiB and 4.33 GiB. Provision additional space for ROMs, artwork, database growth, caches and intentionally retained deployment originals/journals. There is no automatic journal pruning.

## Links

- [Website](https://romm.app)
- [GitHub](https://github.com/rommapp/romm)
- [Documentation](https://docs.romm.app)
