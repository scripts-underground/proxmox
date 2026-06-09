#!/bin/sh
jekyll serve --config /workspaces/scripts-underground-proxmox/_config.yml,/workspaces/scripts-underground-proxmox/_config.dev.yml --host 0.0.0.0 --livereload &
exec "$@"
