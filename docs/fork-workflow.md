# Fork Workflow

This fork uses a core three-branch workflow plus one mergework branch so
upstream updates, in-progress work, and stable releases stay clearly
separated.

## Roles

- `upstream` (remote): the original author's repository
- `origin` (remote): this fork on GitHub
- `vendor` (branch): clean local mirror of `upstream/main`
- `beta-mergework` (branch/worktree): temporary merge desk used to trial upstream integration before touching `beta`
- `beta` (branch): integration and day-to-day development branch
- `main` (branch): stable branch for the final product

## Intent

- `vendor` should stay as close as possible to the author's latest `main`
- `beta-mergework` is our workbench for rehearsing a `vendor` merge, validating it, and deciding whether it should advance
- `beta` is where validated fork work lives day to day
- `main` only receives changes that are already validated in `beta`

## Required merge order

When upstream changes need to be reviewed, the order is mandatory:

1. Update `vendor` from `upstream/main`
2. Recreate `beta-mergework` from the current `beta`
3. Merge `vendor` into `beta-mergework`
4. Resolve conflicts and test there
5. Promote to `beta` only after `beta-mergework` is validated

This order is not optional.

- Do not inspect or merge a stale local `vendor`
- Do not merge `vendor` directly into `beta`
- Do not keep reusing an old `beta-mergework` as the base for a new upstream cycle
- Do not promote anything into `beta` before a real test pass in `beta-mergework`

## Canonical upstream sync flow

When the author publishes new changes:

```bash
git fetch upstream
git switch vendor
git merge --ff-only upstream/main
git switch beta
git switch -C beta-mergework
git merge vendor
```

That means:

- `vendor` must be refreshed first, every time
- `beta-mergework` must be recreated from the current `beta`, every time
- the merge under review is always: current `beta` plus current `vendor`

The important mental model is:

- `vendor` answers: "what did the author publish?"
- `beta` answers: "what is our current fork state?"
- `beta-mergework` answers: "what happens when we combine both right now?"

## Validation gate

After merging `vendor` into `beta-mergework`, stop there and validate.

Minimum expectation:

- resolve conflicts in `beta-mergework`
- build and run the beta app from `beta-mergework`
- review the areas touched by upstream
- confirm the merge behaves correctly before touching `beta`

Until that happens, `beta` must remain untouched.

## Promotion rules

Only after `beta-mergework` is validated should the merge advance into `beta`:

```bash
git switch beta
git merge beta-mergework
```

If the merge is not validated yet, do not run that command.

Then promote the result into `main` when ready:

```bash
git switch main
git merge beta
```

## Stop conditions

If any of these are true, stop and fix the setup before proceeding:

- `vendor` is behind `upstream/main`
- `beta-mergework` was not recreated from the current `beta`
- the integration is being tested from `beta` instead of `beta-mergework`
- someone is about to "just merge it into beta and see what happens"

In those cases, reset the process back to:

1. update `vendor`
2. recreate `beta-mergework` from `beta`
3. merge `vendor` into `beta-mergework`
4. validate there
5. only then promote to `beta`

## Rule of thumb

- Never develop directly on `vendor`
- Prefer feature branches from `beta`
- Use `beta-mergework` as the named worktable for upstream merge evaluation
- Treat `main` as the stable product branch
- Resolve upstream conflicts in `beta-mergework` first, then advance `beta`
- If there is any doubt, the safe answer is: "do not touch `beta` yet"

## Local beta app

For this fork, daily local validation should use a separate beta app install.
When validating an upstream merge, run it from `beta-mergework`, not from `beta`.

- app bundle: `muesli-beta.app`
- bundle id: `com.jr4y.muesli.beta`
- support dir: `~/Library/Application Support/MuesliBeta/`
- build entrypoint: `./scripts/beta-test.sh`

Important:

- local fork beta builds must not follow the author's Sparkle feeds
- `./scripts/beta-test.sh` enforces this by setting `MUESLI_SPARKLE_FEED_URL=""`
- this means local `muesli-beta.app` builds do not use `appcast.xml` or `appcast-preprod.xml`
- `scripts/release-preprod.sh` remains upstream-oriented release infrastructure and is not the build path for this fork's day-to-day beta app

Recommended validation habit:

```bash
git switch beta
git switch -C beta-mergework
git merge vendor
./scripts/beta-test.sh
```

Only after that test pass should `beta` be updated.

## Suggested feature flow

```bash
git switch beta
git switch -c feature/some-improvement
```

After the feature is ready:

```bash
git switch beta
git merge feature/some-improvement
```

Then validate and promote to `main` when appropriate.
