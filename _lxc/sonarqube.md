---
slug: sonarqube
title: SonarQube
tags: [automation]
logo: /assets/logos/sonarqube.webp
by: prop4n
repo: https://github.com/SonarSource/sonarqube
site: https://docs.sonarsource.com/sonarqube-server
port: 9000
cpu: 4
ram: 6144
disk: 25
maintainer: prop4n
---

SonarQube is a self-managed tool that systematically helps teams deliver clean code. It supports analysis of code quality and security across multiple programming languages.

## Notes

- Access the web UI at `http://{ip}:9000` to log in.
- Default admin credentials: `admin` / `admin` (change on first login).
- SonarQube requires Java 21 and PostgreSQL 17.
- The update script creates a full backup of `/opt/sonarqube` before applying updates.

## Links

- [GitHub](https://github.com/SonarSource/sonarqube)
- [Website](https://docs.sonarsource.com/sonarqube-server)
