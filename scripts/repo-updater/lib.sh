# Shared settings for repo-updater. Sourced by run.sh, check.sh, apply.sh and the CGI page.
: "${BASE_DIR:?BASE_DIR not set}" "${HOST_NAME:?HOST_NAME not set}" "${SERVER:?SERVER not set (e.g. server1)}"
PROJECT="${COMPOSE_PROJECT:-mediaserver}"
COMPOSE_FILE_NAME="docker-compose-${SERVER}.yaml"
BRANCH="${REPO_BRANCH:-main}"
STATE_DIR="${REPO_UPDATE_STATE:-$BASE_DIR/appdata/repo-updater}"
LOG="$STATE_DIR/updater.log"
PENDING="$STATE_DIR/pending.txt"   # services changed by pulled commits, not yet upgraded
COMMITS="$STATE_DIR/commits.txt"   # the pulled commits behind them
# Never upgraded from the button: losing these can lock everyone out, or they have
# their own deploy steps. Shell patterns are allowed (e.g. sbs-*).
SKIP=" ${REPO_UPDATE_SKIP:-cloudflared guacamole guacd repo-updater} "
export HOME=/tmp DOCKER_CONFIG=/tmp/.docker GIT_TERMINAL_PROMPT=0
mkdir -p "$STATE_DIR"
touch "$PENDING" "$COMMITS"
cd "$BASE_DIR" || exit 1

dc() { docker compose -p "$PROJECT" -f "$BASE_DIR/$COMPOSE_FILE_NAME" "$@"; }
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
skipped() {
  set -f # patterns, not file names
  for p in $SKIP; do case "$1" in $p) set +f; return 0 ;; esac; done
  set +f; return 1
}
state_of() { docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
  --filter "label=com.docker.compose.service=$1" --format '{{.State}}' | head -1; }

# Sort the pending services into: upgradable (running), protected, stopped, new.
classify() {
  UP=""; PROT=""; STOP=""; NEWS=""
  for svc in $(cat "$PENDING"); do
    if skipped "$svc"; then PROT="$PROT $svc"; continue; fi
    case "$(state_of "$svc")" in
      running) UP="$UP $svc" ;;
      "") NEWS="$NEWS $svc" ;;
      *) STOP="$STOP $svc" ;;
    esac
  done
}

# ---- HTML email -------------------------------------------------------------
h() { sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g'; }
html_head() {
  cat <<EOF
<!doctype html><html><body style="margin:0;padding:0;background:#f3f4f6">
<div style="max-width:560px;margin:0 auto;padding:24px 16px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#111827">
<div style="background:#ffffff;border-radius:12px;padding:24px;border:1px solid #e5e7eb">
<div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#6b7280">$HOST_NAME</div>
<h1 style="margin:4px 0 16px;font-size:22px;line-height:1.3">$1</h1>
EOF
}
html_foot() {
  echo "</div><p style=\"font-size:12px;color:#9ca3af;margin:12px 4px\">repo-updater on $HOST_NAME &middot; never touched: $(echo $SKIP | h)</p></div></body></html>"
}
html_section() { echo "<h2 style=\"font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:#6b7280;margin:20px 0 8px\">$1</h2>"; }
# html_chips "svc svc" COLOR
html_chips() {
  for s in $1; do
    echo "<span style=\"display:inline-block;margin:0 6px 6px 0;padding:4px 10px;border-radius:999px;background:$2;font-size:14px\">$s</span>"
  done
}
html_commits() {
  echo '<table style="border-collapse:collapse;width:100%;font-size:14px">'
  h < "$1" | while read -r sha msg; do
    echo "<tr><td style=\"padding:4px 8px 4px 0;font-family:Consolas,monospace;color:#6b7280;vertical-align:top\">$sha</td><td style=\"padding:4px 0\">$msg</td></tr>"
  done
  echo '</table>'
}
html_button() {
  echo "<p style=\"margin:24px 0 8px\"><a href=\"$1\" style=\"display:inline-block;background:#2563eb;color:#ffffff;text-decoration:none;padding:12px 22px;border-radius:8px;font-weight:600\">$2</a></p>"
}
html_pre() { echo "<pre style=\"background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:12px;font-size:12px;overflow:auto;white-space:pre-wrap\">$(h)</pre>"; }

# mail SUBJECT < html
mail() {
  { echo "To: ${MAIL_TO:?MAIL_TO not set}"; echo "Subject: [$HOST_NAME] $1"
    echo "MIME-Version: 1.0"; echo "Content-Type: text/html; charset=utf-8"; echo; cat; } \
    | NAS_MAIL_FROM_NAME="$HOST_NAME" sh "$BASE_DIR/scripts/send_mail.sh" >> "$LOG" 2>&1
}
mail_error() { { html_head "$1"; echo "$2" | html_pre; html_foot; } | mail "$1"; }
