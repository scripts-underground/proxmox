# Script AST — structural analysis of bash scripts

> Audience: maintainers of `tools/ast/main.go`, the script classification
> pipeline, and any consumer that reads `_ast/` JSON files.
>
> This document covers **what the AST parser extracts and why** — the
> semantic analysis that happens server-side. How the data is rendered or
> surfaced on the site is a separate concern (see `_layouts/app.html` and
> `_plugins/scripts_json.rb` for the consumption layer).

## 1. Purpose

The AST tool (`tools/ast/main.go`) transforms every bash script in the
project into structured JSON under `_ast/<type>/<slug>.json`. Multiple
consumers read this data for different purposes:

- **Source rendering** — the Jekyll app layout renders source code with
  token-accurate syntax spans (16 token kinds, no third-party highlighter).
- **Safety classification** — the Jekyll plugin reads `has_host`,
  `has_external`, `has_eval`, and tool-flag fields to surface warnings
  on script pages (e.g. "this script runs code on the host").
- **Hook detection** — the plugin uses `hooks` and `hook_order` to map
  lifecycle functions (`install_script`, `update_script`, etc.) for
  metadata generation and cross-referencing.
- **Future uses** — linting, audit, dependency analysis, version-impact
  tracking all benefit from a single per-script JSON source of truth.

A single tool that emits one JSON per script keeps every consumer reading
the same representation, rather than each re-parsing the bash.

## 2. Pipeline overview

```
scripts/<type>/<slug>.sh
  → go run ./tools/ast/.
    → mvdan.cc/sh/v3/syntax parses the file into an AST tree
      → AST walker (visitNode) emits tokens + structural data
        → JSON written to _ast/<type>/<slug>.json (schema v2)
```

Consumers (Jekyll plugin, app layout, future tooling) read the JSON files.
The tool itself has no awareness of its consumers — it emits data and exits.

## 3. mvdan/sh primer

`mvdan.cc/sh/v3/syntax` is a pure-Go bash parser. It parses bash source
into a typed AST: a tree of `syntax.Node` values — each node type
represents a grammar construct (`*syntax.IfClause`, `*syntax.CallExpr`,
`*syntax.Heredoc`, etc.).

Why it was chosen:

- **Full bash grammar coverage** — heredocs, parameter expansion,
  arithmetic, process substitution, coprocesses, and the full keyword set.
- **Accurate positions** — every node reports its start `Line`/`Col`
  (1-indexed) down to the character.
- **Pure Go** — no CGO, no external parser binary. Fits the Go toolchain
  used by the rest of the project (the AST tool is a standalone Go module).

Our walker visits each node type and does two things:

1. Emits a **token** (typed span) for the construct.
2. Accumulates **structural data** (function definitions, heredoc
   analysis, host ranges, variable assignments, tool flags).

The parser does not execute the script — it reads the grammar only.
Dynamic analysis (what value a variable resolves to at runtime) is
deliberately out of scope.

## 4. Schema v2 reference

Every JSON file follows this structure. All arrays are empty (`[]`) when
the script has no examples of that feature.

| Field | Type | Purpose | Consumer |
|---|---|---|---|
| `schema_version` | `int` | Always `2`. Incremented on breaking format changes. | Every consumer |
| `slug` | `string` | Script identifier (e.g. `"alpine"`). | Jekyll plugin for page routing |
| `type` | `string` | One of `lxc`, `addon`, `pve`, `vm`. | Jekyll plugin for collection lookup |
| `total_lines` | `int` | Number of lines in the source file. | Renderer (line-number display) |
| `source` | `string` | Raw script text. | Renderer (fallback text), future text-tools |
| `source_lines` | `[string]` | Pre-split script lines (one entry per line, no trailing `\n`). Replaces `line_offsets` which was removed in v2. | Renderer `lineText()`, `gatherLineSpans()` |
| `tokens` | `[Token]` | Typed, positioned spans covering the entire script (see §5). | Renderer (syntax spans), classification (flag detection) |
| `functions` | `[FunctionInfo]` | Every function definition: `name`, `start_line`, `end_line`, `name_span`. | Hook detection, cross-referencing |
| `assigns` | `[Assign]` | Variable assignments with metadata flags (see §4 notes). | Jekyll plugin (bootstrap zone detection) |
| `host_ranges` | `[LineRange]` | Line ranges of bash logic that executes on the Proxmox host (see §7). | Safety classification (`has_host`) |
| `heredocs` | `[Heredoc]` | Full heredoc analysis (see §6). | Renderer (body styling), classification |
| `external_spans` | `[Span]` | Line ranges sourced/curl'd from outside the script (see §8). | Safety classification (`has_external`) |
| `hooks` | `{string: bool}` | Which hook functions the script defines (`install_script`, `update_script`, `uninstall_script`, `pre_build_script`, `post_build_script`, `post_install_script`). | Jekyll plugin (metadata, UI rendering) |
| `hook_order` | `[string]` | Hook names in definition order. | Jekyll plugin (UI ordering) |
| `flags` | `Flags` | Tool-use flags (docker, podman, npm, yarn, pnpm, pip, cargo, go, git, sudo, eval). | Safety classification, compatibility notes |
| `has_external` | `bool` | True if the script sources external content at runtime (see §8). | Safety classification |
| `has_eval` | `bool` | True if the script uses `eval`. | Safety classification |
| `has_host` | `bool` | True if the script contains host-bound logic (see §7). | Safety classification |
| `has_bootstrap` | `bool` | True if the script ends with a bootstrap-source line. | Framework detection |
| `bootstrap_line` | `int` | Line number of the bootstrap source call, or `0`. | Framework detection |

### Assign metadata flags

The `assigns` array carries extra analysis:

- `value_has_cmdsubst` — the assigned value contains a command
  substitution (`$(...)` or backtick). Useful for distinguishing static
  defaults from computed values.
- `is_repo_base` — the variable is `REPO_BASE` or closely related (used
  in bootstrap URL construction).
- `in_bootstrap_zone` — the assignment appears after the bootstrap source
  line (inside the framework-source guard block).
- `value_is_param_default` — the variable uses `${var:-default}` syntax
  (a parameter expansion default, not a bare assignment).

## 5. Token kind reference

Every token has: `kind` (string), `start_line`, `start_col`, `end_line`,
`end_col`, and an optional `op` (literal text for operators/keywords).
Positions are 1-indexed, matching mvdan/sh's convention.

| Kind | Bash construct | Example | Notes |
|---|---|---|---|
| `comment` | `#`-prefixed line | `# this is a comment` | Everything from `#` to end of line. |
| `keyword` | Shell keyword | `if`, `then`, `fi`, `for`, `do`, `done`, `case`, `while`, `until`, `select` | The `op` field carries the keyword text. |
| `command` | Simple command name | `echo`, `apt-get`, `curl` | First word of a `CallExpr`. |
| `function-name` | Function definition | `install_script` | The name being defined (after the `function` keyword or at the start of a `FuncDecl`). |
| `function-call` | Function invocation | `header_info`, `msg_ok "..."` | A `CallExpr` where the first word matches a known function (detected via scope tracking). |
| `var-name` | Variable reference | `$CTID`, `${APP}` | Any `${...}` or `$NAME` reference that is not an assignment LHS. |
| `var-assign` | Variable assignment | `APP="Alpine"` | The variable name on the left side of `=` or `+=`. The `op` field records the full assignment text (name + operator). |
| `param-exp` | Parameter expansion | `${var:-default}`, `${var%suffix}` | Any `${...}` that is not a plain variable name (has modifiers, defaults, substitutions). |
| `string-sq` | Single-quoted string | `'literal'` | No interpolation. |
| `string-dq` | Double-quoted string | `"hello $USER"` | Interpolation allowed inside. |
| `cmd-subst` | Command substitution | `$(command)` | Starts at `$(` and ends at the matching `)`. Nested cmd-substs yield both inner and outer tokens — consumers see the outermost span and the inner tokens inside it. |
| `proc-subst` | Process substitution | `<(cmd)`, `>(cmd)` | Starts at `<(` or `>(`. |
| `arith-exp` | Arithmetic expression | `$((a + b))`, `((a++))` | Covers both `$((...))` (expanded) and `((...))` (bare) forms. |
| `test-operator` | Test/conditional operator | `-z`, `-f`, `-eq`, `-n` | Operators inside `[[ ... ]]` or `(( ... ))` contexts. |
| `operator` | Other operator | `&&`, `||`, `|`, `;`, `&`, `>`, `<`, `>>`, `2>&1` | Redirections, pipes, list terminators, background operators. |
| `heredoc-delim` | Heredoc delimiter | `EOF`, `'EOF'` | The delimiter word. `expand: true` for `<<EOF` (interpolates), `false` for `<<'EOF'` (literal). |

Most tokens are single-line. Multi-line tokens exist (a backslash-continued
string, a here-document body, a multi-line command-substitution). For those,
`start_line` and `end_line` differ, and consumers that clip tokens to a
single line must respect the span boundaries.

## 6. Heredoc analysis

Heredocs are special in bash — the delimiter line is not bash code (it's
a marker), and the body between the opening and closing delimiters may
contain variable interpolation or literal text.

For each heredoc we record:

- **`op`** — the operator position (`<<` or `<<-`). `strip_tabs: true`
  indicates `<<-` (leading tabs stripped from body lines).
- **`marker_start`** — the opening delimiter word and its position.
- **`marker_end`** — the closing delimiter word and its position
  (the standalone line that terminates the heredoc).
- **`body`** — a `LineRange` covering all body lines between the two
  delimiters.
- **`expand`** — `true` if the delimiter is unquoted (`<<EOF`), meaning
  the body is expanded (variables interpolated). `false` for `<<'EOF'`
  or `<<"EOF"` (literal body).

Why this matters: `expand` is relevant for classification — expanded
heredocs may contain variable references that should be flagged when
the variable source is untrusted or host-derived.

## 7. Host range detection

"Host ranges" are line ranges of bash logic that executes on the Proxmox
host rather than inside the container or VM.

The walker identifies them by heuristic: logic that appears before the
`build_container` call or outside container-bound function bodies.
The exact bounds are recorded in `host_ranges[]` as `start_line`/`end_line`
pairs.

Downstream consumers (specifically the Jekyll plugin) use `host_ranges`
to determine whether a script executes code on the host. When combined
with `has_bootstrap`, the plugin can distinguish scripts whose body is
entirely container-bound (safe to run) from those with host-side effects.

## 8. External span detection

"External spans" mark content that is `source <(curl ...)`'d or
`source <(wget ...)`'d from a URL at runtime. These indicate that the
script dynamically fetches and executes code from a remote source,
which has implications for reproducibility and trust.

The walker identifies `source <(curl ...)` and `source <(wget ...)`
patterns and records the line range of each such invocation, along with
the URL when extractable. `has_external` is set to `true` if any such
span exists.

## 9. Hook and flag detection

**Hook detection**: the walker scans function definitions against the
known hook names (`install_script`, `update_script`, `uninstall_script`,
`pre_build_script`, `post_build_script`, `post_install_script`). Each
hook present is recorded in `hooks{}` with `true`, and `hook_order[]`
preserves the definition order (not alphabetical).

**Flag detection**: the walker checks each `CallExpr`'s command name
against a known set of tool commands (`docker`, `podman`, `npm`, `yarn`,
`pnpm`, `pip`, `cargo`, `go`, `git`, `sudo`). `eval` is detected as a
keyword rather than a command name. The respective `flags.*` field is
set to `true` when the command is used.

**Boolean flags**: `has_eval`, `has_external`, `has_host`,
`has_bootstrap` are derived from accumulated state during the walk.
If the walker encounters `eval`, `has_eval` is set. If any `host_ranges`
were recorded, `has_host` is set, etc.

## 10. Position semantics

- **Line and column**: 1-indexed, following mvdan/sh's convention. The
  first character of the script is `line=1, col=1`.
- **End position**: End column is *exclusive* — the column *after* the
  last character of the token. For a 3-character keyword `for` at
  column 1, the token is `start_col=1, end_col=4`.
- **Source lines**: `source_lines` is a pre-split array of strings, one
  per line with no trailing `\n`. Consumers get line `i` via
  `source_lines[i - 1]`. Replaces v1's `line_offsets` (byte-offset
  slicing) which was removed because it broke on multi-byte UTF-8
  characters when consumed as UTF-16 code units in the JS renderer.
- **Multi-line tokens**: a token spanning multiple lines (uncommon but
  possible) has `end_line > start_line`. Consumers that process
  line-by-line must check for overlapping tokens.

## 11. Invocation and regeneration

The tool is invoked by running:
```
go run ./tools/ast/.
```

This walks every script in `scripts/`, re-parses it, and writes the
output to `_ast/<type>/<slug>.json`. The command is idempotent — it
overwrites existing files without prompting.

**CI integration**: `.github/workflows/deploy.yml` runs the tool before
the Jekyll build step (line 47). If the tool fails or produces unexpected
output, the deploy workflow will reject the change.

**Plugin guard**: `_plugins/scripts_json.rb` (line 77) raises an error
at build time if a script being rendered has no matching AST file,
ensuring the site never deploys with stale or missing data.

**`.gitignore`**: `_ast/` is listed in `.gitignore` (generated files
are not committed). The compiled `tools/ast/ast` binary is also ignored
— contributors should use `go run` or `go build` as needed, but the
binary must never be committed.

## 12. Extending the tool

### Adding a new token kind

1. Add a `case` branch in `walker.visitNode()` (in `main.go`),
   constructing a `Token{Kind: "<new-kind>", StartLine: ..., ...}`.
2. Add a corresponding `.tok-<new-kind>` CSS class in
   `assets/css/style.css` if a render consumer exists.
3. No schema change needed — consumers gracefully handle any new kind
   they don't know about (rendering falls through to raw text).

### Adding a new classification field

1. Add a field to the `Flags` struct or the `ASTOutput` struct.
2. Set the value during the AST walk.
3. Document which downstream consumer reads it.

When adding a new field to `ASTOutput`, increment `schema_version` only
if the change is *breaking* (removes or renames existing fields).
Additive changes (new fields) keep the same version — consumers ignore
keys they don't understand.

## 13. Design boundaries

- **Bash only**. The tool uses mvdan/sh, which parses bash. POSIX sh,
  zsh-specific, and other shell syntaxes are not supported.
- **Emit only**. The tool produces structured data. All analysis and
  classification logic lives in consumers. The tool does not lint,
  warn, or return diagnostic exit codes.
- **Positions are accurate for grammar tokens**. Complex nested
  constructs (a `cmd-subst` inside a `param-exp` inside a `string-dq`)
  produce multiple overlapping tokens. Both outer and inner tokens are
  emitted — consumers choose which level to use based on their needs.
- **No runtime values**. The tool reads grammar, not execution state.
  Dynamic values (e.g., the result of `$(hostname)`) are not resolved.
