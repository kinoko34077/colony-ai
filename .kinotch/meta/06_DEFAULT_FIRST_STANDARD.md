# KiNoTch. Repository Default-First Standardization v0.1

## Purpose

KiNoTch. repositories provide safe, removable common conveniences as
standard Defaults before demanding cross-language proof. Changes that carry
Domain meaning, public compatibility, persistent format, or authority remain
separate Portable Contract candidates and are evaluated by Runtime Pilots.

This document is the canonical policy. Runtime and Project documents refer to
it instead of copying the full policy.

## Four layers

Each shared element has one source of truth.

```text
L1 Hard Base
    ↓
L2 Surface / Tool Defaults
    ↓
L3 Portable Semantic Contracts
    ↓
L4 Project Overlay / Domain
```

### L1 — Hard Base

Hard Base contains repository operation itself: `AGENTS.md`, `.kinotch/`, the
`project/` boundary, Project Manifest, documentation/ADR skeleton, the `knt`
router, `doctor`, `verify`, Base checks, Base refresh, Schema validation, and
common command vocabulary. It must not contain Project-specific information.
Individual repositories do not edit it directly; changes come from the
Repository Base source of truth.

### L2 — Surface / Tool Defaults

Defaults are common conveniences that do not own Domain meaning, public
compatibility, persistent data, or authority. They must be safe to remove and
must be overrideable or disableable per Project. Surface Defaults answer
where a Project is used; Tool Defaults answer which reusable convenience is
provided. They are separate axes and are not Runtime module selections.

Surface Default identifiers are `minimal`, `web-app`, `cli`, `windows`,
`mcp`, `api`, `agent`, and `library`. The `windows-gui` profile is the
canonical profile name for the `windows` Default alias.

Tool Default identifiers are `ci-test`, `generated-integrity`, `file-io`, and
`pwa`. The machine-readable catalog at `.kinotch/defaults/catalog.json` is the
single source for these identifiers, descriptions, compatibility, aliases, and
default state. `knt verify` is an L1 Hard Base command and is always available;
it is not a Tool Default and has no removable Default state.

These are Defaults, not mandatory universal libraries. Existing Framework
dispatch remains authoritative where it already exists. A Surface Profile
never injects `runtime.modules`; Runtime selection is explicit Project data.

### L3 — Portable Semantic Contracts

Portable Contract candidates require the same meaning, the same change reason,
low conversion cost, and no loss of Domain state across implementations.
Current candidates include operation identity, operation input, request or
correlation identity, error code/message/details, optional retryability, narrow
progress meaning, and narrow artifact-reference meaning. Runtime maturity
labels apply only to this layer.

### L4 — Project Overlay / Domain

Project owns Domain algorithms and models, Project UI and state machines,
persistent formats, provider/deploy/auth policy, Project resource authority,
Project error meaning, explicit Runtime modules, and Default overrides or
disablement. Domain code must not be changed merely to fit a Default or
Portable Contract.

## Default states

Project-level Default state uses exactly three values:

```text
DEFAULT   use the selected standard behavior
OVERRIDE  use Project-provided behavior or settings
DISABLED  do not provide the Default for this Project
```

Portable maturity labels such as `pilot-exercised`, `PARTIAL GO`, `REVISE`,
or `stable` do not determine Default state.

## Decision rule

For a new candidate `X`, ask in order:

1. Is it required for repository operation itself? If yes, L1 Hard Base.
2. Does it carry no Domain meaning and remain safely removable? If yes, L2
   Default.
3. Must multiple implementations share the same meaning and change reason?
   If yes, evaluate as an L3 Portable Contract candidate.
4. Otherwise keep it in L4 Project Overlay / Domain.

Low-risk, removable conveniences are provided as Defaults first and observed
in use. A Project may override or disable a Default when it duplicates an
existing Framework, adds adapter-only complexity, leaks Domain information,
adds unused dependencies, or makes the existing path harder to understand.
Default retirement requires the same problem to repeat across Projects.

## Initialization and migration

`knt init --profile <surface> [--profile <surface> ...]` accepts all Surface
Profiles listed in the catalog. `windows` remains an alias for the
`windows-gui` profile. `--default <tool-default>` may be repeated to select
Tool Defaults independently:

```text
knt init --profile web-app
knt init --profile web-app --default pwa
knt init --profile cli --profile mcp --default ci-test
```

Initialization creates a Project overlay from the Base templates, records the
selected Default states, and leaves `runtime.modules` empty. A Project that
uses Runtime declares its modules explicitly. The initializer must not
overwrite an existing `project/project.json` or existing Project files.

`knt migrate` is dry-run by default. It detects Surface and Tool Default
candidates from the catalog, reports the recommended state, and changes
nothing. Only `knt migrate --apply` records candidates. Existing `OVERRIDE` and
`DISABLED` states are always preserved. Domain files are never rewritten.

## Actual implementation boundary

The current Phase 3B implementation materializes only removable helpers:

- `ci-test` adds a separate non-deploy GitHub Actions workflow when absent; it runs `doctor` → `setup` → `verify`. The Base repository's own workflow is not overwritten.
- `pwa` adds a minimal manifest with relative base-path URLs, a pass-through service worker, registration helper, and `pwa-check`.
- `generated-integrity` adds source and artifact SHA-256 metadata, Project-root containment checks, stale checking for both, and metadata update helpers.
- `file-io` adds a format-independent Project callback boundary and a UTF-8 text-only helper; binary Projects provide their own byte/path callback.
- `cli` adds opt-in JSON/error/help/exit helpers without parsing Domain arguments.
- `windows` adds opt-in Explorer/clipboard shell boundaries; GUI state and picker ownership remain Project-owned.
- `mcp` adds tool naming/input/diagnostic guidance without a second dispatch registry.
- `api` adds a permissive error-envelope schema; HTTP status, error code policy, auth, and provider behavior remain Project-owned.

Existing files are preserved. Deploy workflows, public API/error policy,
Domain file formats, GUI state, and Runtime modules are never generated by
these Defaults. A manifest-less repository can be shape-probed by
`knt migrate` in dry-run mode with a Base source override; `--apply` still
requires a Project Manifest and a repository-local `.kinotch/` Base. An
external Base override is never a write source.

## Default eligibility

A candidate may be a Default when it is likely reusable, reduces repeated
setup, owns no Domain meaning, can be removed without changing Domain models or
public data, supports Project override/disable, and adds little branching or
dependency cost. Do not Defaultize Domain algorithms, public error systems,
persistent schemas, provider authority, deployment policy, trainer/model
state, or other project-owned semantics.

## Ownership

Repository Base owns this policy, L1 structure, the Default Catalog, and the
initialization safety boundary. Runtime owns execution semantics and Portable
Contract definitions. Project owns Domain behavior, explicit Runtime module
selection, and the selected Default/Override/Disabled state.
