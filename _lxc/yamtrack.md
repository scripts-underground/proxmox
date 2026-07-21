---
slug: yamtrack
title: Yamtrack
tags: [media, tracker, movies, anime]
logo: /assets/logos/yamtrack.webp
by: MickLesk
repo: https://github.com/FuzzyGrim/Yamtrack
site: https://github.com/FuzzyGrim/Yamtrack
port: 8000
cpu: 2
ram: 2048
disk: 8
maintainer: MickLesk
---

Yamtrack is a self-hosted media tracker for movies, TV shows, anime, manga, video games, books, comics, and board games with multi-user support and Celery-powered background tasks.

## Notes

- Set API keys (TMDB_API, MAL_API, IGDB_ID, IGDB_SECRET) in `/opt/yamtrack/src/.env` to enable media search from external providers.
- If using a reverse proxy, set the `URLS` variable in `.env` to your external URL (e.g., `URLS=https://yamtrack.example.com`).
- Access the Django admin at `http://<ip>:8000/admin/`.
- The first registered account automatically becomes the admin user.

## Links

- [GitHub](https://github.com/FuzzyGrim/Yamtrack)
- [Documentation](https://github.com/FuzzyGrim/Yamtrack/wiki)
