# AGENTS.md — repo conventions for `PS.GHOps`

Context for an AI agent (or a human working alongside one) to work productively
in this repo without re-reading every skill file from scratch.

**Read first:** [`docs/adr/`](docs/adr/) — architecturally significant decisions. Start there for "why is it this way?" questions.

## Purpose

`PS.GHOps` is a **human-facing operator toolkit** for GitHub: org-scoped
reporting and administration helpers over the `gh` CLI. It is the higher layer
of a two-module design — the low-level, determinism-focused
[`PS.GitHub`](https://github.com/johnsarie27/PS.GitHub) module is the substrate
(REST wrapper, signed commits, auth-scope checks); `PS.GHOps` holds the
convenience/reporting commands built on top of it.

Where `PS.GitHub` is deliberately narrow and agent-facing, `PS.GHOps` is for a
human running ad-hoc org reports and maintenance from a shell.

## Function inventory

### Public functions (exported via manifest)

| Function | Status | Purpose |
|---|---|---|
| `Get-GHActivity` | Experimental | A user's recent issue/PR activity via `gh search`, categorized by lifecycle event. |
| `Get-GHIssue` | Experimental | Issue report scoped by org, repo-name prefix, or explicit repo list (`gh search issues`). |
| `Get-GHOpenBranch` | Experimental | Non-default branches across an org's active repos (`gh repo list` + branches REST). |
| `Get-GHRepoFile` | Experimental | Presence/absence of a repo-relative file path across an org's repos. |
| `Remove-GHStaleCodeScan` | Beta | Removes orphaned code-scanning analyses that block PRs after a scanning workflow is renamed. |

### Private helpers (dot-sourced, not exported)

| Helper | Purpose |
|---|---|
| `Invoke-GHCli` | Runs a `gh` **subcommand** with `$PSNativeCommandUseErrorActionPreference` isolation, `$LASTEXITCODE` checking, a consistent terminating error on failure, and optional `-AsJson` parsing. Subcommands only — REST goes through PS.GitHub's `Invoke-GhApi`. |

`FunctionsToExport` in [PS.GHOps.psd1](PS.GHOps.psd1) is the authoritative export list.

## Cross-cutting rules every public function honors

1. **Two lanes for `gh`.** Subcommands (`gh repo list`, `gh search issues`) go through the private `Invoke-GHCli`; REST calls (`gh api …`) go through PS.GitHub's `Invoke-GhApi` (once the dependency is wired — see ADR-0001). No bare `& gh` in `Public/`.
2. **Native-preference isolation.** `Invoke-GHCli` sets `$PSNativeCommandUseErrorActionPreference = $false` so a caller that enabled it cannot turn the `& gh` + `$LASTEXITCODE` pattern into a `NativeCommandExitException`.
3. **No `--jq` / `--query` for filter/project.** Return deserialized objects; callers use the pwsh pipeline (`Where-Object` / `Select-Object` / `Group-Object`).
4. **Active repos by default.** Org-scanning functions exclude archived repos and forks by default (`gh repo list --no-archived --source`) with `-IncludeArchived` / `-IncludeFork` opt-in switches.
5. **`Verb-GH<Noun>` naming.** All exports use the `GH` prefix (matching this module's name); output is a `[PSCustomObject]` stream.

## Layout

```text
PS.GHOps/
  .devcontainer/         devcontainer + Dockerfile (installs gh CLI)
  .github/
    workflows/ci.yml     Pester + PSScriptAnalyzer, matrix on ubuntu + windows + macos
    workflows/release.yml fires on `v*.*.*` tag push; creates a GitHub Release with a .zip artifact
    release.yml          auto-generated-release-notes categorization by PR label
    dependabot.yml
    CODEOWNERS
  .vscode/               editor settings + PSScriptAnalyzer rules
  Build/                 PSake harness (build.ps1 -> build.psake.ps1); module name derived from the .psd1 basename
  Public/                one .ps1 per exported function, Verb-GHNoun.ps1
  Private/               internal helpers, NOT exported
  Tests/                 Pester tests, Tests/Unit/<Function>.tests.ps1
  docs/adr/              architectural decision records
  PS.GHOps.psd1          module manifest (authoritative export list)
  PS.GHOps.psm1          module loader (dot-sources Public/ + Private/)
  README.md              user-facing quickstart + function list
  CONTRIBUTING.md        new-function checklist + template
```

## Working conventions

- Branch off `main` using `<issue-number>-<short-slug>`; no direct commits to `main`.
- One PR per function or per cross-cutting concern.
- Every function ships with comment-based help (`.SYNOPSIS`/`.DESCRIPTION`/`.PARAMETER`/`.INPUTS`/`.OUTPUTS`/`.EXAMPLE`/`.NOTES`), a `.NOTES Status:` line, an approved verb, and (for exports) an entry in `FunctionsToExport`. A `Tests/Unit/<Verb-Noun>.tests.ps1` is expected for new functions.
- Run the build locally before a PR: `./Build/build.ps1 -ResolveDependency -TaskList Init` then `-TaskList CombineFunctionsAndStage`, `Analyze`, `Test`.

## Relationship to PS.GitHub

`PS.GHOps` is intended to take a `RequiredModules` dependency on `PS.GitHub` once the public functions consume `Invoke-GhApi` for their REST calls. Until then the functions use raw `gh` and the manifest declares no required modules (so import/CI do not require an as-yet-unpublished `PS.GitHub`). See [`docs/adr/0001`](docs/adr/0001-github-operator-toolkit-module.md).
