# Fork Workflow

This fork uses a three-branch workflow so upstream updates, in-progress work,
and stable releases stay clearly separated.

## Roles

- `upstream` (remote): the original author's repository
- `origin` (remote): this fork on GitHub
- `vendor` (branch): clean local mirror of `upstream/main`
- `beta` (branch): integration and day-to-day development branch
- `main` (branch): stable branch for the final product

## Intent

- `vendor` should stay as close as possible to the author's latest `main`
- `beta` is where upstream changes are integrated and conflicts are resolved
- `main` only receives changes that are already validated in `beta`

## Recommended flow

When the author publishes new changes:

```bash
git fetch upstream
git switch vendor
git merge --ff-only upstream/main
git switch beta
git merge vendor
```

If everything works as expected, promote the result into `main`:

```bash
git switch main
git merge beta
```

## Rule of thumb

- Never develop directly on `vendor`
- Prefer feature branches from `beta`
- Treat `main` as the stable product branch
- Resolve upstream conflicts in `beta`, not in `main`

## Local beta app

For this fork, daily local validation should use a separate beta app install:

- app bundle: `MuesliBeta.app`
- bundle id: `com.jr4y.muesli.beta`
- support dir: `~/Library/Application Support/MuesliBeta/`
- build entrypoint: `./scripts/beta-test.sh`

Important:

- local fork beta builds must not follow the author's Sparkle feeds
- `./scripts/beta-test.sh` enforces this by setting `MUESLI_SPARKLE_FEED_URL=""`
- this means local `MuesliBeta.app` builds do not use `appcast.xml` or `appcast-preprod.xml`
- `scripts/release-preprod.sh` remains upstream-oriented release infrastructure and is not the build path for this fork's day-to-day beta app

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
