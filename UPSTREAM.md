# Upstream

| | |
|---|---|
| project | Happier — https://github.com/happier-dev/happier |
| licence | MIT ([licenses/HAPPIER-LICENSE](licenses/HAPPIER-LICENSE)) |
| official image | `happierdev/relay-server` (Docker Hub; also `ghcr.io/happier-dev/relay-server`), amd64 + arm64 |
| pinned | `happierdev/relay-server:stable-a2c45c86804b@sha256:3f6068f9659980c7cc34456ff844b6bad9e127c18a6642690299dea1e1e4186e` (server 0.2.17, `server-stable` release of 2026-10-23) |
| wrapper | `ghcr.io/youssefsiam38/happier-railway` (see `RAILWAY_TEMPLATE.md` for the digest the template uses) |

The image is built by upstream from signed server-runtime and web-UI release artifacts.

## Refreshing the pin

```bash
tag=$(curl -s 'https://hub.docker.com/v2/repositories/happierdev/relay-server/tags?page_size=50' \
  | jq -r '[.results[].name | select(startswith("stable-"))][0]')
digest=$(curl -s "https://hub.docker.com/v2/repositories/happierdev/relay-server/tags/$tag/" | jq -r .digest)
echo "happierdev/relay-server:$tag@$digest"
```

Use the immutable `stable-<sha>` tag (the `stable`/`latest` tags move). Put the reference in
`images/happier/Dockerfile` (`ARG HAPPIER_IMAGE=`) and in this file, then follow [MAINTENANCE.md](MAINTENANCE.md).
