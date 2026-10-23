# Maintenance

## Bumping Happier

1. Resolve the new `stable-<sha>` tag and digest ([UPSTREAM.md](UPSTREAM.md)); update `images/happier/Dockerfile`
   and `UPSTREAM.md`.
2. Read the server release notes for changes to `AUTH_ANONYMOUS_SIGNUP_ENABLED`, the `Account` table, the SQLite
   file name (`happier-server-light.sqlite`), `run-server`, or the `happier` user — the start script depends on them.
3. `docker compose build && tests/static.sh && tests/smoke.sh && tests/persistence.sh`.
4. Commit, push (CI runs the same tests), then tag `vX.Y.Z` → `publish-image` builds, re-tests and pushes
   `ghcr.io/youssefsiam38/happier-railway:X.Y.Z` (amd64 + arm64).
5. Resolve the wrapper digest, update `_audit/spec_happier.py` (`TAG`, `DIGEST`), run `tplkit.patch_template` on the
   template id in `RAILWAY_TEMPLATE.md`, check `template mismatches: []`.
6. Deploy the template into a throwaway project and run `tests/railway-smoke.sh` (fresh + `--verify` after a
   redeploy). Delete the project.

## Rebuilding the template from scratch

`_audit/spec_happier.py` → `tplkit.skeleton` → `railway templates create` → `tplkit.patch_template` (see the
railway-template-builder toolkit). Volumes, domains and the health check are only set by the skeleton.

## Gotchas

- The light server does not exit after SIGTERM (its shutdown handlers finish, the process stays). The start script
  SIGKILLs it after `SHUTDOWN_GRACE_SECONDS` (default 5). A Railway redeploy of a closed server is unaffected
  (Railway kills the old container).
- `AUTH_ANONYMOUS_SIGNUP_ENABLED` is read per request from the environment, so closing sign-up needs a restart; it
  cannot be changed from outside the process.
- Railway volumes are root-owned; the image runs as `happier` (uid 1000).
- Health check `/health` (also `/ready`). Startup takes about 3 s; migrations are applied by the packaged binary.
