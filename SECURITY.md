# Security

## What the template enforces

- **One account by default.** Anonymous sign-up is open only until the first account exists, then the server
  restarts with `AUTH_ANONYMOUS_SIGNUP_ENABLED=false`. New device keys get `403 signup-disabled`.
- **End-to-end encryption** is Happier's default: session content, messages and settings are encrypted on your
  devices. The relay (and Railway) store ciphertext.
- **Non-root server process** (`happier` user); the start script only uses root to fix the volume's ownership.
- **Generated token secret** (`HANDY_MASTER_SECRET`); no default credentials exist.
- **No crash reports to a third party** unless you set `HAPPIER_SENTRY_USE_CENTRAL_DSN=1`.

## Residual risks and what you should do

- **Claim it first.** Between the deploy turning green and your sign-up, anyone who guesses the URL could take the
  only account slot. Railway domains are random, and you would notice (your own sign-up is refused). Create your
  account right after deploying. If it was taken: redeploy with a fresh volume.
- **Back up your secret key.** Accounts have no password; losing every device and the secret key loses the account.
- **Short double-sign-up window.** Accounts are counted every 2 seconds, so two sign-ups within the same 2 seconds
  could both succeed. Check the logs for `account limit reached (N of 1)`.
- **Rate limits** are upstream's defaults (per client IP behind Railway's edge).
- **Back up the volume** (`/data`): it holds the database, uploaded files and the master secret.

## Reporting

Template issues: https://github.com/youssefsiam38/happier-railway/issues.
Happier itself: see https://github.com/happier-dev/happier (security policy in that repository).
