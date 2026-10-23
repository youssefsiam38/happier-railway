# Deploy and Host Happier Relay Server on Railway

Happier is an open-source, end-to-end encrypted app for running and steering coding agents such as Claude Code,
Codex and OpenCode on your own machines from your phone, desktop or browser. Its relay server syncs sessions,
messages and approvals between your devices. This template deploys your own relay with the web app included, keeps
its data on a volume, and closes sign-up as soon as your account exists. It is a community-maintained template and
is not affiliated with the Happier project.

## About Hosting Happier Relay Server

The relay is a single Node.js server (Happier's light flavour) with an embedded SQLite database, serving the API, a
WebSocket channel for live updates, and the Happier web app on one port. Session content is encrypted on your
devices; the relay stores ciphertext. Agents keep running on your own computers, which connect out to the relay.

A stock relay on a public URL lets anyone who finds it create an account. This template keeps sign-up open only
until the first account exists, then restarts the server with sign-up switched off; your other devices still link to
your account.

## Common Use Cases

- Approve, steer and review Claude Code or Codex sessions on your workstation from your phone
- Keep agent session history and sync on infrastructure you control instead of a shared cloud relay
- Pair several dev boxes and laptops to one account and switch between them from any device
- Run a private relay for the Happier desktop, mobile and web apps

## Dependencies for Happier Relay Server Hosting

- None external: SQLite is embedded and stored on the service's volume
- Your own computers run the Happier CLI and daemon with your agent subscriptions (Claude, Codex, ...)

### Deployment Dependencies

- Happier (MIT): https://github.com/happier-dev/happier
- Template source, image and tests: https://github.com/youssefsiam38/happier-railway

### Implementation Details

**First steps:** right after the deploy turns green, open your service's domain and create your account in the web
app; back up the secret key it shows. Sign-up closes about 10 seconds later. In the Happier phone or desktop app, add
the server (`https://<your domain>`) and link your account. On each computer:
`happier server add --name railway --server-url https://<your domain> --webapp-url https://<your domain> --use`,
then `happier auth login`.

**What's configured for you:** the official `happierdev/relay-server` image pinned by digest and used unmodified,
plus a start script that fixes the volume's ownership for the non-root server and enforces the sign-up limit
(`SIGNUP_ACCOUNT_LIMIT`, default 1); the public URL set from your Railway domain for QR codes and deep links; a
generated token secret; data on a volume at `/data`; a health check on `/health`; upstream crash reporting off.

**More people:** raise `SIGNUP_ACCOUNT_LIMIT` and redeploy; sign-up reopens until that many accounts exist.

Tested on a live deployment of this template over HTTPS: account creation and the sign-up lock, refused second
accounts, device-key sign-in, sessions, encrypted messages and key-value storage, the realtime WebSocket channel,
terminal pairing, and data plus the lock surviving a redeploy.

## Why Deploy Happier Relay Server on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you
don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Happier Relay Server on Railway, you are one step closer to supporting a complete full-stack application
with minimal burden. Host your servers, databases, AI agents, and more on Railway.
