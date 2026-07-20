---
slug: kitchenowl
title: KitchenOwl
tags: [food, recipes]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/kitchenowl.webp
by: snazzybean
repo: https://github.com/TomBursch/kitchenowl
site: https://kitchenowl.org/
port: 80
cpu: 1
ram: 2048
disk: 6
maintainer: snazzybean
---

Smart self-hosted grocery list and recipe manager with real-time synchronization, meal planning, and expense tracking.

## Notes

- Access the web UI at `http://<ip>:80`.
- Nginx reverse proxy fronts the Flask backend on port 5000.
- JWT secret is auto-generated on install.
- Update from the LXC console via the helper.

## Links

- [Website](https://kitchenowl.org/)
- [GitHub](https://github.com/TomBursch/kitchenowl)
