---
slug: actual-budget-prometheus-exporter
title: Actual Budget Prometheus Exporter
tags: [monitoring, finance]
logo: /assets/logos/actual-budget-prometheus-exporter.webp
by: CrazyWolf13
repo: https://github.com/sakowicz/actual-budget-prometheus-exporter
site: https://github.com/sakowicz/actual-budget-prometheus-exporter
port: 3001
maintainer: CrazyWolf13
---

Prometheus exporter for Actual Budget. Connects to an Actual Budget server via the official API and exposes budget metrics (account balances, budgeted amounts, and more) on a `/metrics` endpoint for Prometheus scraping.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only) — typically installed inside the Actual Budget LXC itself
- Requires the Actual Budget server URL, password, and Budget Sync ID (found in Actual under Settings > Advanced settings > Sync ID)
- Metrics available at `http://<container-ip>:3001/metrics` — configuration at `/opt/actual-budget-prometheus-exporter.env`
- Update with: `update-actual-budget-prometheus-exporter` — Uninstall with: `uninstall-actual-budget-prometheus-exporter`

## Links

- [GitHub](https://github.com/sakowicz/actual-budget-prometheus-exporter)
- [Actual Budget](https://actualbudget.org)
