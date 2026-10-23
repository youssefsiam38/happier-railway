# Railway template configuration

The template's exact configuration. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Happier Relay Server |
| Code | `happier-relay-server` |
| Template id | `01418edc-8437-44b5-ab30-437ef6f53255` |
| Deploy URL | https://railway.com/deploy/happier-relay-server |
| Category | AI/ML |
| Card description | Your own E2EE Happier relay to steer Claude Code and Codex from any device |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

Generated values use Railway's `secret()` function: `hexN` is `${{secret(N, "abcdef0123456789")}}` and `alnumN` is
`${{secret(N, "a-zA-Z0-9")}}` spelled out. Alphanumeric passwords are used wherever a value is embedded in a
connection URL, so nothing needs percent-encoding. Images are referenced by tag and digest (`repo:tag@sha256:…`);
`UPSTREAM.md` records the upstream digest.

## Services

### `happier`

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/happier-railway:1.0.0@sha256:02d0c4a742b59df51e4d7eb9d81aba042fa1523441c319c4c7d2f79735065134` |
| Public domain | target port 3005 |
| Volume | `/data` |
| Healthcheck | `/health`, timeout from `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `PORT` | `3005` |
| `HANDY_MASTER_SECRET` | generated, alnum64 |
| `HAPPIER_PUBLIC_SERVER_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` |
| `HAPPIER_WEBAPP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` |
| `SIGNUP_ACCOUNT_LIMIT` | `1` |
| `HAPPIER_SERVER_TRUST_PROXY` | `100.64.0.0/10` |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `120` |
| `AUTH_ANONYMOUS_SIGNUP_ENABLED` | optional, unset |
| `HAPPIER_SENTRY_USE_CENTRAL_DSN` | optional, unset |

## Notes

- Wrapper `ghcr.io/youssefsiam38/happier-railway:1.0.0` (amd64 + arm64) FROM the official
  `happierdev/relay-server:stable-a2c45c86804b` (server 0.2.17), run unmodified.
- Sign-up lock: open until `SIGNUP_ACCOUNT_LIMIT` accounts exist (default 1), then the server restarts with upstream's
  `AUTH_ANONYMOUS_SIGNUP_ENABLED=false` (about 8 s of 502s). Existing accounts, device linking and terminal pairing
  keep working.
- `HAPPIER_SERVER_TRUST_PROXY=100.64.0.0/10`: Railway's edge was observed connecting from that range.
- Live e2e on a clean-room deploy of this template (2026-10-23): 29/29 fresh, 22/22 after a redeploy; web-app sign-up
  and recovery after the lock restart checked in a browser.
