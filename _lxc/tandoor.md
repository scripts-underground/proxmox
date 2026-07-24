---
slug: tandoor
title: Tandoor Recipes
tags: [recipes]
logo: /assets/logos/tandoor.webp
by: MickLesk
repo: https://github.com/TandoorRecipes/recipes
site: https://tandoor.dev/
port: 8002
cpu: 4
ram: 4096
disk: 10
maintainer: MickLesk
---

Application for managing recipes, planning meals, building shopping lists and much more.

## Notes

- If you want to use Tandoor behind a reverse proxy, add the address to `ALLOWED_HOSTS` in `/opt/tandoor/.env`.
- Tandoor uses PostgreSQL for data storage — credentials are in `/opt/tandoor/.env`.

## Links

- [Website](https://tandoor.dev/)
- [GitHub](https://github.com/TandoorRecipes/recipes)
- [Docs](https://docs.tandoor.dev/)
