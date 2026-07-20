---
slug: github-runner
title: GitHub Runner
tags: [ci]
logo: /assets/logos/github-runner.webp
by: MickLesk
repo: https://github.com/actions/runner
site: https://github.com/actions/runner
port: null
cpu: 2
ram: 2048
disk: 8
maintainer: MickLesk
---

GitHub Runner is a self-hosted GitHub Actions runner for running CI/CD workflows.

## Notes

- After first boot, run `config.sh` with your GitHub token and start the service.
- The runner user has no sudo access by design.

## Links

- [GitHub](https://github.com/actions/runner)
- [Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
