# Update and Re-exec Sequence

Use this sequence when implementing self-update behavior.

## Sequence

1. Resolve local wrapper home and local `VERSION`.
2. Exit early if update checks are disabled by env/flags.
3. Resolve remote repo/branch and fetch remote `VERSION`.
4. Compare versions semantically.
5. If remote is newer:
   - download one `https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz` snapshot
   - extract it on the install filesystem and validate `VERSION`, the tracked managed-file manifest, every non-empty managed file, and shell syntax where applicable
   - promote individual files atomically, with the wrapper near-last and `VERSION` last
   - re-exec wrapper with original arguments
6. If local managed files are incomplete, run the same archive repair even when versions are equal. A re-exec marker permits validation without looping.
7. If remote is not newer and the local install is complete, continue normal execution.

## Reliability Rules

- Make updates atomic (temp dir then swap) where possible.
- Preserve execute bits for scripts.
- Preserve user args and environment during re-exec.
- Fail closed with clear error on partial update.
- Require `tar` before archive extraction and reject malformed, unsafe, empty, or incomplete archives before promotion.
- Reject absolute, multi-root, dot/dotdot, symlink, hardlink, device, FIFO, and other non-regular archive entries before extraction; reject duplicate manifest entries.
- Keep `VERSION` unchanged when download, extraction, or validation fails so a retry remains possible.
