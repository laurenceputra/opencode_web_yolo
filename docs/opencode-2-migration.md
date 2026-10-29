# OpenCode 2.x migration contract

## Objective

The operator procedure is maintained in the distributed, top-level
[OpenCode 2.x migration runbook](../OPENCODE_2_MIGRATION.md).

## Non-negotiables

Release assets must remain flat so the actual 0.5.0 updater can validate the
new archive before promoting the new wrapper. Do not add slash-containing
manifest entries or weaken path validation to distribute documentation.

## Scope of changes

Distribute the existing operator procedure as a flat managed release asset, with
README/TECHNICAL links that resolve in installed releases. Preserve backup,
authentication, persistence and rollback guarantees in the operator runbook.

## Files to change/add

- `OPENCODE_2_MIGRATION.md`, `.opencode_web_yolo.manifest`, README and TECHNICAL.
- Self-update/bootstrap regression tests and CI history checkout.

## Test and validation plan

Regression acceptance must execute the unmodified 0.5.0 wrapper from commit
`a95a84c349c67f4662913a1efb35519654e733ec` against the new release archive,
then verify re-execution and installation of the flat operator runbook.

## Acceptance criteria

The actual old updater accepts the new archive without path-validator changes;
the installed wrapper and operator runbook match the new release byte-for-byte.
All manifest entries remain flat, and backup/restore runbook tests still pass.

## Out of scope

General nested release-asset support or changes to updater path containment.

## Open decisions and spec gaps

None for the flat distribution change. Broader migration acceptance limits are
recorded in the operator runbook rather than duplicated here.
