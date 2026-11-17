# repo-updater image: Docker CLI, the same Compose version as the host, git, curl and
# BusyBox httpd. The scripts are mounted from the repo, so a git pull updates them
# without a rebuild.
ARG DOCKER_VERSION=27.1.2
FROM docker:${DOCKER_VERSION}-cli
# Match the host's Compose version: config hashes decide what gets recreated, and
# they must be computed the same way the host computed them.
ARG COMPOSE_VERSION=2.29.1
ARG TARGETARCH
RUN apk add --no-cache git curl busybox-extras tzdata \
 && case "${TARGETARCH:-amd64}" in arm64) A=aarch64 ;; arm) A=armv7 ;; *) A=x86_64 ;; esac \
 && curl -fsSL -o /usr/local/libexec/docker/cli-plugins/docker-compose \
      "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${A}" \
 && chmod +x /usr/local/libexec/docker/cli-plugins/docker-compose
ENTRYPOINT []
