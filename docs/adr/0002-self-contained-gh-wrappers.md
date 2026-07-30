# ADR 2: Self-Contained `gh` Wrappers — No PS.GitHub Runtime Dependency

Supersedes [ADR-0001](0001-github-operator-toolkit-module.md) in part (the deferred `RequiredModules` dependency on `PS.GitHub`).

## Status

Accepted

## Context

- [ADR-0001](0001-github-operator-toolkit-module.md) set the direction that REST calls would route through `PS.GitHub`'s `Invoke-GhApi`, with a `RequiredModules` dependency added once the functions were wired.
- `PS.GitHub` is not published to a gallery; consuming it at runtime or in CI requires a pinned release-zip download or a second checkout — the same unresolved distribution problem that stalled the `PS-MCS/gh-org` migration.
- The module already owns a **local** subcommand wrapper (`Invoke-GHCli`) rather than reusing `PS.GitHub`'s private `Invoke-Gh`.
- `PS.GHOps`'s REST needs are a small subset of `PS.GitHub`'s `Invoke-GhApi` surface — GET, pagination, 404-tolerance — not writes, body handling, or empty-204.

## Decision

- We will add a **local, private `Invoke-GHApi`** as the REST counterpart to `Invoke-GHCli`, so the module depends only on the `gh` CLI — no PowerShell-module runtime dependency.
- `RequiredModules` stays `@()`; the intended `PS.GitHub` dependency from ADR-0001 is **withdrawn**.
- Two lanes remain, both isolating `$PSNativeCommandUseErrorActionPreference`: subcommands → `Invoke-GHCli`; REST → the local `Invoke-GHApi`.

## Consequences

- **Positive** — the distribution problem disappears; install and CI need only the `gh` CLI, and import never blocks on an unpublished module.
- **Positive** — consistent with the existing local `Invoke-GHCli`; each module owns its `gh` internals.
- **Negative** — a second `Invoke-Gh*Api` now exists in the ecosystem (`PS.GitHub`'s and this one); they can drift. Mitigated by keeping this one lean and scoped to what `PS.GHOps` needs.
- **Negative** — no dogfooding of `PS.GitHub`, which ADR-0001 counted as a benefit of the layering.
- **Neutral** — if a richer REST surface (writes, empty-204, body handling) is ever needed, revisit whether to grow the local helper or reconsider the `PS.GitHub` dependency.
