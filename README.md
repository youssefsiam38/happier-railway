# Happier relay server — Railway template

One-click [Railway](https://railway.com) template for the self-hosted relay server of
[Happier](https://github.com/happier-dev/happier), the open-source, end-to-end encrypted app for running and steering
coding agents (Claude Code, Codex, OpenCode and more) on your own machines from your phone, desktop or browser.

Community-maintained. Not affiliated with the Happier project; the template uses its own generic icon, not the
Happier logo.

- **Image:** `ghcr.io/youssefsiam38/happier-railway` — the official `happierdev/relay-server` stable image, pinned by
  digest and run unmodified, plus a start script (see [ARCHITECTURE.md](ARCHITECTURE.md)).
- **Licences:** Happier is MIT ([licenses/HAPPIER-LICENSE](licenses/HAPPIER-LICENSE)); this repository is MIT ([LICENSE](LICENSE)).

## What you get

- The Happier relay server and its web app on your Railway domain (`https://<service>.up.railway.app`).
- SQLite database, file uploads and server state on a volume at `/data`.
- **Sign-up closes after your account.** A stock relay lets anyone who finds the URL create an account. Here sign-up
  stays open only until the first account exists; the server then restarts with upstream's
  `AUTH_ANONYMOUS_SIGNUP_ENABLED=false`. Your devices still link to your account.
- Crash reports to the Happier project's central Sentry are off (set `HAPPIER_SENTRY_USE_CENTRAL_DSN=1` to share them).

## Deploy

1. Deploy the template. No inputs are needed.
2. **Right away**, open `https://<your domain>` and create your account (the first account is the only one). Back up
   the secret key the app shows you. About 10 seconds later the server restarts with sign-up closed.
3. Phone or desktop app: add the server (Settings → Server, URL `https://<your domain>`), then restore or link your
   account (Add your phone / scan the QR code from the web app).
4. Each computer that runs agents: install the CLI (`curl -fsSL https://happier.dev/install | bash`), then

   ```bash
   happier setup --relay https://<your domain>
   ```

   and approve the sign-in from the app. (The web app bundled in the relay image suggests dev-channel commands such as
   `hdev setup` and `--channel dev`; the stable `happier` commands above work the same way.)

If someone else created the first account before you (sign-up said "disabled"), delete the volume's data
(redeploy with a new volume) and start again.

More accounts: set `SIGNUP_ACCOUNT_LIMIT` (e.g. `3`) and redeploy; sign-up reopens until that many accounts exist.
`SIGNUP_ACCOUNT_LIMIT=0` leaves sign-up open (upstream default); setting `AUTH_ANONYMOUS_SIGNUP_ENABLED` yourself
always overrides the lock.

## Repository layout

| path | purpose |
|---|---|
| `images/happier/` | wrapper image: `Dockerfile` (FROM the pinned upstream image) and `railway-start.sh` |
| `compose.yaml` | local test topology (one service, one volume), mirrors Railway |
| `tests/` | `static.sh`, `smoke.sh`, `persistence.sh`, `railway-smoke.sh`; `client/happier-client.mjs` speaks Happier's device-key protocol |
| `marketplace/OVERVIEW.md` | Railway Marketplace page |
| `.github/workflows/` | `test.yml` (every push), `publish-image.yml` (tags → GHCR) |

## Local development

```bash
docker compose build
tests/static.sh
tests/smoke.sh
tests/persistence.sh
```

Live test against a deployment (keeps the owner's device key in `KEY_DIR` between runs):

```bash
KEY_DIR=$(mktemp -d) tests/railway-smoke.sh https://<domain>            # fresh deploy
KEY_DIR=<same dir>   tests/railway-smoke.sh https://<domain> --verify   # after a redeploy
```

Requirements: Docker with Compose, Node.js 22+, `jq`, `curl`, `shellcheck` (optional).
