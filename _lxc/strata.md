---
slug: strata
title: Strata
tags: [ai]
logo: /assets/logos/strata.webp
by: alexindigo
repo: https://github.com/Niko1221/Strata
site: https://github.com/Niko1221/Strata
port: 80
cpu: 6
ram: 65536
disk: 40
maintainer: alexindigo
---

Native Strata CUDA engine and the author's Chat/Monitor/Settings server, built from
pinned source for CUDA 12.8 / SM89. Supports the project's Qwen3.8-Flash-Next native packs.
Installation downloads no model weights and starts no mock server. The service is
enabled but intentionally skipped until a genuine model pack/tokenizer is supplied.

Persistent models, packs and optional MTP live under `/var/lib/strata`; configure
their real paths in `/etc/strata/config.json`. Supply suitable persistent data
storage before adding models: the referenced UD-IQ4_XS model alone is 93.7 GB, and
the empty 40 GiB app-disk default is not a model-storage allocation.

The template preserves 131072 total context, INT8 KV and 32768 GPU-resident KV cells,
with native lazy loading and 300-second idle unloading. Editable RAM/VRAM floors
in `/etc/strata/admission.json` are enforced at actual engine execution, rather
than relying on the upstream non-enforcing before_load hook. Resource defaults
and a compiled engine do not prove model fit, GPU compatibility or inference.

Updates preserve administrator configuration, launcher, service/account and data.
Source pins are bumped only after validation; no kernel driver is installed by this script.
Set `var_lxc_cuda_arch` to override SM89 and `var_lxc_build_jobs` to bound compilation.
