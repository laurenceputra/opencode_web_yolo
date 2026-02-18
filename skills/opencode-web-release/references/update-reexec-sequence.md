# Update and Re-exec Sequence

Use this sequence when implementing self-update behavior.

## Sequence

1. Resolve local wrapper home and local `VERSION`.
2. Exit early if update checks are disabled by env/flags.
3. Resolve remote repo/branch and fetch remote `VERSION`.
4. Compare versions semantically.
5. If remote is newer:
   - download/update managed runtime files
   - verify required files are present after update
   - re-exec wrapper with original arguments
6. If remote is not newer, continue normal execution.

## Reliability Rules

- Make updates atomic (temp dir then swap) where possible.
- Preserve execute bits for scripts.
- Preserve user args and environment during re-exec.
- Fail closed with clear error on partial update.
