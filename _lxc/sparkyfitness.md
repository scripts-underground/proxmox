---
slug: sparkyfitness
title: SparkyFitness
tags: [health, fitness]
logo: /assets/logos/sparkyfitness.webp
by: tomfrenzel
repo: https://github.com/CodeWithCJ/SparkyFitness
site: https://codewithcj.github.io/SparkyFitness/
port: 80
cpu: 2
ram: 2048
disk: 7
maintainer: tomfrenzel
---

A self-hosted, privacy-first alternative to MyFitnessPal. Track nutrition, exercise, body metrics, and health data while keeping full control of your data.

## Notes

- Access the web UI at `http://<ip>` to register and start tracking.
- Requires PostgreSQL 18 and Node.js 25 (installed automatically).
- The backend API runs on port 3010 with Nginx as a reverse proxy.
- Configuration file is at `/etc/sparkyfitness/.env`.
- Uploaded data is stored in `/var/lib/sparkyfitness/`.

## Links

- [GitHub](https://github.com/CodeWithCJ/SparkyFitness)
- [Website](https://codewithcj.github.io/SparkyFitness/)
