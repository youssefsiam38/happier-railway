# syntax=docker/dockerfile:1
#
# Happier relay server for the Railway template: the official image, pinned by digest, used unmodified, plus
# railway-start.sh, which
#   - makes the root-owned Railway volume at /data writable by the image's non-root `happier` user, and
#   - keeps anonymous sign-up open only until the first account exists (SIGNUP_ACCOUNT_LIMIT, default 1), then
#     restarts the server with upstream's AUTH_ANONYMOUS_SIGNUP_ENABLED=false.
# Crash reports to the upstream project's central Sentry DSN are off by default (HAPPIER_SENTRY_USE_CENTRAL_DSN=0).
#
# Not affiliated with the Happier project.
ARG HAPPIER_IMAGE=happierdev/relay-server:stable-a2c45c86804b@sha256:3f6068f9659980c7cc34456ff844b6bad9e127c18a6642690299dea1e1e4186e

FROM ${HAPPIER_IMAGE}
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown

COPY --chmod=0755 images/happier/railway-start.sh /usr/local/bin/railway-start

ENV SIGNUP_ACCOUNT_LIMIT=1 \
    HAPPIER_SENTRY_USE_CENTRAL_DSN=0

LABEL org.opencontainers.image.title="happier-railway" \
      org.opencontainers.image.description="Happier relay server for the Railway template: the official image pinned by digest, sign-up closed after the first account, volume ownership fixed. Not affiliated with the Happier project." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/happier-railway" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

# Starts as root only to fix the volume's ownership; railway-start drops to `happier` before running the server.
USER root
EXPOSE 3005
CMD ["/usr/local/bin/railway-start"]
