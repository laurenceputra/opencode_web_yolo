---
name: spec-writer
description: Create implementation specs and explicitly surface spec gaps and open decisions.
---

# Spec Writer Scope

Use this skill when drafting or updating specs (for example `docs/specs/*.md`).

# Required Output

Every spec must include:

- Objective
- Non-negotiables
- Scope of changes
- Files to change/add
- Test and validation plan
- Acceptance criteria
- Out of scope
- Open decisions and spec gaps

# Workflow

1. Read the relevant product docs (README, TECHNICAL, AGENTS, skills) and any existing specs.
2. Draft the spec using a consistent section structure.
3. Surface spec gaps explicitly (missing decisions, ambiguous requirements, or unowned risks).
4. Provide a short in-chat synopsis of the spec after writing.

# Spec Gap Rules

- List unresolved decisions with recommended defaults.
- Call out missing ownership, governance, or security requirements.
- Call out missing CI/test coverage for new behavior.
- Identify contradictions between existing docs and new requirements.

# Done Criteria

- The spec is complete and actionable.
- A visible spec-gaps section exists in the file.
- The assistant response lists the gaps and recommended defaults.
