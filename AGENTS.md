# AGENTS.md

## Build Artifacts and Worktrees

SwiftPM writes build artifacts to `native/MuesliNative/.build` inside the active worktree by default. That can consume several GB per worktree when multiple feature worktrees are used.

For local app builds, set `MUESLI_SWIFTPM_SCRATCH_PATH` so `scripts/build_native_app.sh` passes a shared `--scratch-path` to SwiftPM:

```bash
MUESLI_SWIFTPM_SCRATCH_PATH="$HOME/Library/Caches/muesli-spm/dev" ./scripts/dev-test.sh
MUESLI_SWIFTPM_SCRATCH_PATH="$HOME/Library/Caches/muesli-spm/preprod" ./scripts/build_native_app.sh release
```

## Beta Installs

For the fork's local beta app, use `scripts/beta-test.sh`, not `scripts/build_native_app.sh` directly.

- `scripts/beta-test.sh` installs the app as `/Applications/muesli-beta.app`
- it uses bundle id `com.jr4y.muesli.beta`
- it stores data under `~/Library/Application Support/MuesliBeta/`
- if the local Developer ID signing identity is unavailable, it automatically falls back to an unsigned local install by setting `MUESLI_SKIP_SIGN=1`

Important: `scripts/build_native_app.sh` by itself is the generic installer and defaults to `/Applications/Muesli.app`. It should not be used directly when the goal is to install or refresh the local beta build.

Recommended beta invocation:

```bash
MUESLI_SWIFTPM_SCRATCH_PATH="$HOME/Library/Caches/muesli-spm/dev" ./scripts/beta-test.sh
```

Caveat: do not run concurrent builds from different worktrees into the same scratch path. Use separate paths per channel, agent, or simultaneous build, such as `dev`, `preprod`, `test`, or `agent-1`.

Deleting a scratch path only removes rebuildable SwiftPM artifacts. It does not delete installed app bundles or app data under `~/Library/Application Support/`.

For direct SwiftPM test runs, pass the scratch path yourself:

```bash
swift test --package-path native/MuesliNative --scratch-path "$HOME/Library/Caches/muesli-spm/test"
```
