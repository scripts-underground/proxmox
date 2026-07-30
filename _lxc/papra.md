---
slug: papra
title: Papra
tags: [document-management]
logo: /assets/logos/papra.webp
by: MickLesk
repo: https://github.com/papra-hq/papra
site: https://github.com/papra-hq/papra
port: 1221
cpu: 2
ram: 2048
disk: 10
maintainer: MickLesk
---

Open-source document management system for organizing and processing your documents with OCR capabilities.

## Notes

- Access the web UI at `http://<ip>:1221` to complete setup.
- Papra uses OCR (Tesseract) for document text extraction.
- Database and documents are stored under `/opt/papra_data/`.
- PNG (`pnpm`) is bundled with Node.js via corepack.

## Links

- [GitHub](https://github.com/papra-hq/papra)
