---
slug: immich
title: Immich
tags: [photos]
logo: /assets/logos/immich.webp
by: vhsdream
repo: https://github.com/immich-app/immich
site: https://immich.app
port: 2283
cpu: 4
ram: 6144
disk: 20
maintainer: vhsdream
---

## Notes

- The default supported source release is pinned to `v3.3.1` for both installation and updates. `var_lxc_release` selects that app-local pin; explicit requested-release overrides retain priority.
- CPU machine learning uses the interpreter required by the selected source (Python3.13 for the default release). Image-processing libraries and build tools follow that source's pinned metadata.
- Image-library/application compilation and initial dependency downloads can take substantial time. Failed dependency retries stop the update and retain its pending state for a later retry.
- Existing upload locations, configuration and installed database-major choices are preserved during updates.
