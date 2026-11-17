# Shared settings for repo-updater. Sourced by run.sh, check.sh, apply.sh and the CGI page.
: "${BASE_DIR:?BASE_DIR not set}" "${HOST_NAME:?HOST_NAME not set}" "${SERVER:?SERVER not set (e.g. server1)}"
PROJECT="${COMPOSE_PROJECT:-mediaserver}"
COMPOSE_FILE_NAME="docker-compose-${SERVER}.yaml"
BRANCH="${REPO_BRANCH:-main}"
STATE_DIR="${REPO_UPDATE_STATE:-$BASE_DIR/appdata/repo-updater}"
LOG="$STATE_DIR/updater.log"
# Never recreated from the link: losing these can lock everyone out, or they have
# their own deploy steps. Shell patterns are allowed (e.g. sbs-*). Changes to them
# are listed in the result email for a manual step.
SKIP=" ${REPO_UPDATE_SKIP:-cloudflared guacamole guacd repo-updater} "
skipped() {
  set -f # patterns, not file names
  for p in $SKIP; do case "$1" in $p) set +f; return 0 ;; esac; done
  set +f; return 1
}
export HOME=/tmp DOCKER_CONFIG=/tmp/.docker GIT_TERMINAL_PROMPT=0
mkdir -p "$STATE_DIR"
cd "$BASE_DIR" || exit 1

dc() { docker compose -p "$PROJECT" -f "$BASE_DIR/$COMPOSE_FILE_NAME" "$@"; }
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# Changed files between two commits that matter to this server:
# its own compose files plus shared ones.
relevant_files() {
  git diff --name-only "$1" "$2" | grep -E "^(compose/$SERVER/|$COMPOSE_FILE_NAME\$|compose/(php|nextcloud)/|scripts/)" || true
}

# mail SUBJECT < body
mail() {
  { echo "To: ${MAIL_TO:?MAIL_TO not set}"; echo "Subject: [$HOST_NAME] $1"
    echo "Content-Type: text/plain; charset=utf-8"; echo; cat; } \
    | NAS_MAIL_FROM_NAME="$HOST_NAME" sh "$BASE_DIR/scripts/send_mail.sh" >> "$LOG" 2>&1
}
