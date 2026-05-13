# Google Calendar Local Setup

This fork keeps Google Calendar OAuth credentials out of git on purpose.

For local testing, use:

- `config/google-oauth.json` inside the repo
- or `~/.config/muesli/google-oauth.json` as a fallback

The recommended fork workflow is the repo-local file, because local beta builds
now bundle it automatically during `./scripts/beta-test.sh`.

## File format

Start from [config/google-oauth.json.example](../config/google-oauth.json.example):

```json
{
  "client_id": "YOUR_CLIENT_ID.apps.googleusercontent.com",
  "client_secret": "YOUR_CLIENT_SECRET",
  "verified": false
}
```

Notes:

- `verified` can stay `false` for personal/local use
- when `verified` is `false`, Google only allows listed test users to authorize
- if `client_id` or `client_secret` are empty, Muesli treats Google Calendar as unavailable

## Google Cloud setup

Use a dedicated Google Cloud project for this local test setup.

1. Create or select a Google Cloud project.
2. Enable `Calendar API` for that project.
3. Configure the Google Auth Platform consent screen:
   - set an app name
   - choose a support email
   - choose `External` unless you are strictly staying inside one Workspace org
   - if the app is still in `Testing`, add your own Google account as a test user
4. Under `Data Access`, add these scopes:
   - `https://www.googleapis.com/auth/calendar.events.readonly`
   - `https://www.googleapis.com/auth/calendar.calendarlist.readonly`
5. Create an OAuth client:
   - go to `Google Auth Platform > Clients`
   - click `Create client`
   - choose `Desktop app`
   - save the generated `client_id` and `client_secret`
6. Put those values into `config/google-oauth.json`.
7. Rebuild and reinstall the beta app:

```bash
MUESLI_SWIFTPM_SCRATCH_PATH="$HOME/Library/Caches/muesli-spm/dev" ./scripts/beta-test.sh
```

8. Open `Settings > Calendar` and use `Connect Google Calendar`.

## Important behavior notes

- This app uses a desktop OAuth flow with a local callback on `http://localhost:1456/auth/callback`
- For desktop apps, Google still supports loopback/localhost redirects
- If your OAuth app remains in `Testing`, Google may show an unverified-app warning and test-user grants can expire
- If you previously authorized with fewer scopes, disconnect and connect again so Google issues a token with the updated scope set
- If you edit `config/google-oauth.json`, reinstall the beta app so the bundled copy is refreshed

## What Muesli expects

At runtime, Muesli looks for credentials in this order:

1. `google-oauth.json` embedded in the app bundle
2. `~/.config/muesli/google-oauth.json`

That means:

- official releases can ship with a bundled credential if the maintainer injects one during packaging
- local fork builds can stay self-contained by using `config/google-oauth.json`
