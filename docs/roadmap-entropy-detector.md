# Roadmap Entropy Detector

## Objective

Provide a repo-local, read-only quality gate that detects roadmap scope creep and contract drift by comparing an approved tracked spec against the wrapper command surface, implementation contracts, command discovery surfaces, maintainer docs, tests, and CI wiring.

## Non-negotiables

- The detector remains a read-only quality gate; it must not mutate repo files, start Docker, or reach out to the network.
- The tracked source of truth lives at `docs/roadmap-entropy-detector.md`.
- The detector fails when approved scope or required references drift across the wrapper, docs, tests, or CI.
- The detector is for repository maintenance and CI; it is not a product-planning subsystem.

## Approved Scope

- Add `opencode_web_yolo check-roadmap` with `roadmap-entropy` as an alias in `.opencode_web_yolo.sh`.
- Validate required spec sections plus explicit drift markers declared in this file.
- Watch the wrapper, command discovery surfaces, maintainer docs, tests, CI workflow, and release notes for alignment.
- Keep the implementation shell-based and repository-local.

## Files Under Watch

- `.opencode_web_yolo.sh`
- `.opencode_web_yolo_completion.bash`
- `.opencode_web_yolo_completion.zsh`
- `README.md`
- `TECHNICAL.md`
- `tests/test_help.sh`
- `tests/test_roadmap_entropy.sh`
- `tests/run.sh`
- `.github/workflows/ci.yml`
- `CHANGELOG.md`
- `skills/opencode-web-runtime/references/flag-contracts.md`

## Test and Validation Plan

- `bash -n .opencode_web_yolo.sh .opencode_web_yolo_completion.bash tests/test_help.sh tests/test_roadmap_entropy.sh tests/run.sh`
- `shellcheck -x .opencode_web_yolo.sh .opencode_web_yolo_completion.bash tests/test_help.sh tests/test_roadmap_entropy.sh tests/run.sh`
- `bash tests/test_help.sh`
- `bash tests/test_roadmap_entropy.sh`
- `bash tests/run.sh`

## Acceptance Criteria

- `opencode_web_yolo check-roadmap` exits successfully on the aligned repository state and prints a stable report format.
- Help text, completion scripts, and runtime flag contracts make the detector discoverable and explain that it is repo-local and no-Docker.
- `README.md` and `TECHNICAL.md` describe what the detector checks and how maintainers run it locally and in CI.
- Tests and CI exercise the detector command and enforce syntax/lint coverage for the new test.

## Out of Scope

- Storing roadmap items, approvals, or ownership metadata outside this tracked spec.
- Semantic analysis of intent beyond the explicit marker strings below.
- Auto-remediation, issue creation, or PR automation beyond a standard CI failure.
- Extending managed installs into a full repository maintenance environment.

## Open Decisions and Spec Gaps

- Default to repository-checkout execution. Recommended default: fail with a clear error if the tracked repo files are not available.
- Use explicit string markers instead of semantic diffing. Recommended default: keep markers narrow and operator-facing so failures are actionable.
- The detector only watches files listed below. Recommended default: update this spec in the same change whenever the approved contract surface grows.

## Drift Markers

```text
FILE|.opencode_web_yolo.sh
FILE|.opencode_web_yolo_completion.bash
FILE|.opencode_web_yolo_completion.zsh
FILE|README.md
FILE|TECHNICAL.md
FILE|tests/test_help.sh
FILE|tests/test_roadmap_entropy.sh
FILE|tests/run.sh
FILE|.github/workflows/ci.yml
FILE|CHANGELOG.md
FILE|skills/opencode-web-runtime/references/flag-contracts.md
MATCH|.opencode_web_yolo.sh|check-roadmap, roadmap-entropy
MATCH|.opencode_web_yolo.sh|check-roadmap|roadmap-entropy)
MATCH|.opencode_web_yolo.sh|opencode_web_yolo roadmap entropy report
MATCH|.opencode_web_yolo.sh|docs/roadmap-entropy-detector.md
MATCH|.opencode_web_yolo.sh|run_roadmap_entropy
MATCH|.opencode_web_yolo_completion.bash|check-roadmap roadmap-entropy
MATCH|.opencode_web_yolo_completion.zsh|check-roadmap:Run roadmap entropy detector
MATCH|.opencode_web_yolo_completion.zsh|roadmap-entropy:Run roadmap entropy detector
MATCH|README.md|## Roadmap Entropy Detector
MATCH|README.md|read-only quality gate
MATCH|README.md|opencode_web_yolo check-roadmap
MATCH|TECHNICAL.md|## Roadmap Entropy Detector
MATCH|TECHNICAL.md|read-only quality gate
MATCH|TECHNICAL.md|tests/test_roadmap_entropy.sh
MATCH|tests/test_help.sh|check-roadmap, roadmap-entropy
MATCH|tests/test_roadmap_entropy.sh|status=ok
MATCH|tests/test_roadmap_entropy.sh|status=drift
MATCH|tests/run.sh|test_roadmap_entropy.sh
MATCH|.github/workflows/ci.yml|bash -n tests/test_roadmap_entropy.sh
MATCH|.github/workflows/ci.yml|shellcheck -x tests/test_roadmap_entropy.sh
MATCH|CHANGELOG.md|Roadmap entropy detector
MATCH|skills/opencode-web-runtime/references/flag-contracts.md|check-roadmap
MATCH|skills/opencode-web-runtime/references/flag-contracts.md|roadmap-entropy
```
