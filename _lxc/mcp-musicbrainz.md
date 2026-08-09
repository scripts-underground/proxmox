---
slug: mcp-musicbrainz
title: MusicBrainz MCP
tags: [music, mcp]
logo: /assets/logos/mcp-musicbrainz.webp
by: alexindigo
repo: https://github.com/zas/mcp-musicbrainz
site: https://github.com/zas/mcp-musicbrainz
port: 8000
cpu: 1
ram: 512
disk: 4
maintainer: alexindigo
---

MusicBrainz MCP is a Model Context Protocol server that exposes the MusicBrainz music database to AI assistants — 32 read-only tools for searching and browsing artists, releases, release groups, recordings, labels, works, areas, events, instruments, places, and series, plus ISRC/ISWC lookups, cover-art URLs, fuzzy search, and relationship browsing.

## Notes

- The MCP endpoint is `http://<container-ip>:8000/mcp` (streamable HTTP transport) — point your MCP client (opencode, Claude Desktop, Cursor, ...) at that URL. No authentication.
- The service runs as an unprivileged `mcp` user; `/opt/mcp-musicbrainz` stays root-owned.
- Responses are cached on disk for 24 hours (`.musicbrainz_cache/`) to respect MusicBrainz rate limits.

## Links

- [GitHub](https://github.com/zas/mcp-musicbrainz)
- [MusicBrainz](https://musicbrainz.org/)
