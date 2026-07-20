---
slug: dotnetaspwebapi
title: Dotnet ASP Web API
tags: [web]
logo: /assets/logos/dotnetaspwebapi.webp
by: Kristian Skov
repo: https://github.com/dotnet/aspnetcore
site: https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/linux-nginx?view=aspnetcore-9.0&tabs=linux-ubuntu
port: 80
cpu: 1
ram: 1024
disk: 8
maintainer: Kristian Skov
---

A turnkey LXC template for hosting ASP.NET Core Web API applications on Linux with Nginx, FTP, and systemd service management. Pre-installs the .NET SDK 9.0 so you can deploy via FTP and run your API behind a reverse proxy with zero configuration.

## Notes

- During installation you will be prompted for your project's assembly name (the .dll filename).
- Deploy your published application files to `/var/www/html` via FTP.
- The Kestrel service `kestrel-aspnetapi` serves the API on `http://127.0.0.1:5000`.
- Nginx reverse proxies port `80` to Kestrel.

## Links

- [ASP.NET Core on Linux with Nginx](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/linux-nginx?view=aspnetcore-9.0&tabs=linux-ubuntu)
- [ASP.NET Core Repository](https://github.com/dotnet/aspnetcore)
