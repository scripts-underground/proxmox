---
slug: edit-mind
title: Edit-Mind
tags: [ai, media, photos]
logo: /assets/logos/edit-mind.webp
by: MickLesk
repo: https://github.com/IliasHad/edit-mind
site: https://github.com/IliasHad/edit-mind
port: 3745
cpu: 4
ram: 8192
disk: 32
maintainer: MickLesk
---

Edit-Mind is an AI-powered media management platform with face recognition, video processing, smart search, and automated organization of photos and videos.

## Native storage and updates

The updater characterizes manager `TMPDIR` as temporary workspace, not retained
application data. It requires systemd JSON environment output and literal absolute
temporary paths outside the application tree and its ancestors. Unit Environment
and EnvironmentFile values override the manager value; dotenv fills absent keys.
Manager values and effective unit values are rechecked after quiescence. Other
uncharacterized manager home, cache, driver and wrapper fields remain refused.

Native media readers use `/media/videos`. Fresh installations create an absent-only
symlink to `/opt/edit-mind/media`; updates retain `HOST_MEDIA_PATH` and accept an
existing mapping only when both paths resolve to the same directory. A conflict
stops before replacement. Reconcile existing data yourself; the updater never
moves, merges or overwrites a media directory.

Updates inventory effective web/jobs/ML/Chroma configuration and PostgreSQL-held
file paths, preserve in-tree state in place, then stop all four writers and recheck
the inventory. PostgreSQL and Redis remain running. Config, keys, model caches and
legacy external `.bak` files are not restored from temporary copies or deleted.
Failed updates remain pending for an ordinary retry, including after a version
marker has advanced.

The supported configuration is deliberately bounded: absolute root working
directories, the installer's native service commands, literal single-line unit
assignments and `KEY=value` EnvironmentFiles (optional matching outer quotes).
Unquoted EnvironmentFile value-edge spaces/tabs are discarded; quoted edge spaces
and empty values are preserved. Unit `Environment=` and dotenv retain their own
distinct grammar.
EnvironmentFiles override unit Environment assignments. Custom persistent paths
may be absolute or relative to each actual consumer's working directory and may
contain spaces. Shell expansion, escapes, continuations, wrappers, service
namespace/remapping directives and code/build/dependency overlaps are refused.
Persistent paths containing a `..` component are refused before normalization,
including traversal through symlinks; simple aliases remain supported.

PostgreSQL discovery requires an explicit single-host/user/database URL. It supports
percent-encoded credentials, a `schema` query option and absent/explicit
`sslmode=prefer` or `disable`; other TLS/connection options and encoded database
names are refused, never downgraded or sent to a fallback database. Inventory is
read-only and bounded to 10,000 distinct local references, at most 4,096 characters
each. Missing configuration, schema or database access stops the update before
application changes. Preserve access to the selected database when retrying a
failed build; discovery does not require `node_modules`.

## Links

- [GitHub](https://github.com/IliasHad/edit-mind)
