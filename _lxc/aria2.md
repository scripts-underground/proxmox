---
slug: aria2
title: Aria2
tags: [download-utility]
logo: /assets/logos/aria2.webp
by: tteck
repo: https://github.com/aria2/aria2
site: https://aria2.github.io/
port: 6880
cpu: 2
ram: 1024
disk: 8
maintainer: tteck
---
Lightweight download utility. Supports multi-protocol downloads with RPC interface.
## Notes
- Web UI (AriaNG) is optional, prompted during install.
- RPC secret saved to ~/rpc.secret.
- Default download directory: ~/downloads.
## Links
- [Website](https://aria2.github.io/)
EOF
docker exec -w /workspaces/scripts-underground-proxmox intelligent_albattani sh -c '
shfmt -i 2 -ci -sr -w scripts/lxc/aria2.sh 2>/dev/null; shfmt -i 2 -ci -sr -d scripts/lxc/aria2.sh || exit 1
shellcheck --severity=warning scripts/lxc/aria2.sh || exit 1
! grep -n "arch_resolve" scripts/lxc/aria2.sh || exit 1
echo ALL_CLEAN
' && docker exec -w /workspaces/scripts-underground-proxmox/tools/ast intelligent_albattani go run . 2>&1 | tail -1 && git add scripts/lxc/aria2.sh _lxc/aria2.md && git commit -m "feat(lxc): add Aria2 migration" && git push origin main