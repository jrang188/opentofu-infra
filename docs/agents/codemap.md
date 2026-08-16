# Directory Atlas: docs/agents/

## Responsibility

Conventions for AI/agent sessions working in this repo: how to consume the
repo's domain documentation, how to use the GitHub issue tracker, and what
triage labels mean. These files are the bridge between the generic
vendored skills (`skills-lock.json` → `.agents/skills/`) and this repo's
actual practices.

## Design

Three sibling files, one convention each — no index file:

- `domain.md` — how engineering skills should consume domain docs before
  exploring: read root `CONTEXT.md` (or `CONTEXT-MAP.md` + per-context
  `CONTEXT.md`), read relevant `docs/adr/` ADRs, proceed silently if absent,
  use the glossary's vocabulary, and surface ADR conflicts explicitly.
  Repo is single-context: one `CONTEXT.md` + `docs/adr/` at the root.
- `issue-tracker.md` — GitHub issues as the tracking surface, all operations
  via the `gh` CLI. Conventions for create/read/list/comment/label/close,
  the PRs-as-request-surface flag (currently **no**), and the wayfinder
  operations (map issue, child tickets, native dependencies, frontier query,
  claim, resolve).
- `triage-labels.md` — a mapping table from the five canonical skill roles
  (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`,
  `wontfix`) to the repo's actual label strings. Right column is editable
  to match local vocabulary.

## Flow

- `domain.md` is read first, before exploring code: locate `CONTEXT.md` /
  `docs/adr/`, load the glossary vocabulary, then explore. Missing files are
  not flagged; `/domain-modeling` creates them lazily.
- `issue-tracker.md` is consulted whenever a skill says "publish to the
  issue tracker" (create a GitHub issue) or "fetch the relevant ticket"
  (`gh issue view <n> --comments`). Repo inference comes from `git remote -v`.
- `triage-labels.md` is a lookup: when a skill names a role, substitute the
  corresponding label string from the right-hand column.

## Integration

- `AGENTS.md` (Agent skills section) links all three files as the default
  vocabulary and conventions for this repo.
- Consumed by the vendored skills: `/triage` reads the PRs-as-request-surface
  flag in `issue-tracker.md`; `/wayfinder` uses the wayfinding operations;
  the domain-doc conventions in `domain.md` back any doc-reading skill.
- `CONTEXT.md` and `docs/adr/` (referenced by `domain.md`) live at the repo
  root, not under `docs/agents/`.
