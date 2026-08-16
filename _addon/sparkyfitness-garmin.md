---
slug: sparkyfitness-garmin
title: SparkyFitness-Garmin
tags: [health, fitness]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/sparkyfitness.webp
by: tomfrenzel
repo: https://github.com/CodeWithCJ/SparkyFitness
site: https://codewithcj.github.io/SparkyFitness/
port: 8000
maintainer: tomfrenzel
---

SparkyFitness-Garmin is the Garmin companion microservice for SparkyFitness. It exposes Garmin Connect data over HTTP (uvicorn/FastAPI) so a SparkyFitness installation can pull in Garmin activity and health metrics via `GARMIN_MICROSERVICE_URL`.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only) that already has SparkyFitness installed (`/opt/sparkyfitness`)
- Update with: `update-sparkyfitness-garmin` — Uninstall with: `uninstall-sparkyfitness-garmin`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [GitHub](https://github.com/CodeWithCJ/SparkyFitness)
- [Website](https://codewithcj.github.io/SparkyFitness/)
