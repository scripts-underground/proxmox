---
slug: lazylibrarian
title: LazyLibrarian
tags: [eBook]
logo: /assets/logos/lazylibrarian.webp
by: tteck
co_author: [MountyMapleSyrup]
repo: https://gitlab.com/LazyLibrarian/LazyLibrarian
site: https://gitlab.com/LazyLibrarian/LazyLibrarian
port: 5299
cpu: 2
ram: 1024
disk: 4
maintainer: tteck
---

Initial installation clones the upstream default branch and installs into the
app's Python3.12 `venv`, using its interpreter explicitly. Updates retain that
interpreter and pull `origin master`; they do not preserve an operator's detached
source pin. The installer does not add a source or uv version pin.
