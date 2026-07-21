---
slug: paperless-ngx
title: Paperless-ngx
tags: [document, management]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/paperless-ngx.webp
by: tteck
co_author: [MickLesk]
repo: https://github.com/paperless-ngx/paperless-ngx
site: https://docs.paperless-ngx.com/
port: 8000
cpu: 2
ram: 3072
disk: 12
maintainer: tteck
---

Paperless-ngx is a software tool designed for digitizing and organizing paper documents. It provides a web-based interface for scanning, uploading, and organizing paper documents, making it easier to manage, search, and access important information.

## Notes

- Show login credentials: `cat ~/paperless-ngx.creds` inside the container.
- English is the default OCR language. Install additional languages with `apt install tesseract-ocr-[lang]` (e.g. `tesseract-ocr-deu`).
- All Python commands must use `uv run` prefix (e.g. `uv run python3 manage.py document_exporter $path`).

## Links

- [Documentation](https://docs.paperless-ngx.com/)
- [GitHub](https://github.com/paperless-ngx/paperless-ngx)
