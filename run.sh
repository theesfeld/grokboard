#!/usr/bin/env bash
# One-stop Grok Board launcher: build the image, pick a port, start setup.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

usage() {
	cat <<'EOF'
Usage: ./run.sh [options]

  --port PORT          Host port to publish (default: prompt, 8080)
  --bind ADDR          127.0.0.1 (this machine only) or 0.0.0.0 (LAN)
  --hostname NAME      Hostname/IP you will type in the browser
  --https              phpBB URLs/cookies are HTTPS (TLS terminated in front)
  --image NAME         Image to run (default: grokboard:local, built here)
  --detach, -d         Run in the background (docker-only; no attached shell)
  --open-firewall      Try to allow PORT/tcp via ufw or firewalld (needs root)
  --reset              Delete the named container (data volume is kept)
  --reset-data         Also delete the grokboard-data volume (destroys the board)
  -h, --help           Show this help

First start asks for your phpBB username/password. Sign Grok into Grok Build
from phpBB ACP → Extensions → Grok Board (device code or API key).
EOF
}

PORT=${SERVER_PORT:-}
BIND=${BIND_ADDR:-}
HOSTNAME_OPT=${SERVER_NAME:-}
OPEN_FW=0
RESET=0
RESET_DATA=0
DETACH=0
HTTPS=0
IMAGE=${GROKBOARD_IMAGE:-grokboard:local}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--port) PORT=${2:?}; shift 2 ;;
		--bind) BIND=${2:?}; shift 2 ;;
		--hostname) HOSTNAME_OPT=${2:?}; shift 2 ;;
		--image) IMAGE=${2:?}; shift 2 ;;
		--https) HTTPS=1; shift ;;
		--detach|-d) DETACH=1; shift ;;
		--open-firewall) OPEN_FW=1; shift ;;
		--reset) RESET=1; shift ;;
		--reset-data) RESET=1; RESET_DATA=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
	esac
done

if command -v docker >/dev/null 2>&1; then
	ENGINE=docker
elif command -v podman >/dev/null 2>&1; then
	ENGINE=podman
else
	echo "Install Docker or Podman, then re-run ./run.sh" >&2
	exit 1
fi

ask() {
	local var=$1 msg=$2 def=${3:-}
	if [[ -n "${!var:-}" ]]; then
		return
	fi
	local val
	if [[ -n "$def" ]]; then
		read -r -p "$msg [$def]: " val
		val=${val:-$def}
	else
		read -r -p "$msg: " val
	fi
	printf -v "$var" '%s' "$val"
}

echo
echo "Grok Board"
echo "No accounts or keys are in the image. You will create your phpBB login."
echo "Grok Build is signed in later from the ACP — no docker exec."
echo "Press Enter to accept a default."
echo

ask PORT "phpBB port on this machine" "8080"
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "Port must be numeric" >&2; exit 1; }

if [[ -z "$BIND" ]]; then
	echo
	echo "Who can reach the board?"
	echo "  1) This machine only   (127.0.0.1)  [default]"
	echo "  2) LAN / other devices (0.0.0.0) — open the firewall for TCP $PORT"
	read -r -p "Choice [1]: " who
	case "${who:-1}" in
		2) BIND=0.0.0.0 ;;
		*) BIND=127.0.0.1 ;;
	esac
fi

if [[ "$BIND" == "127.0.0.1" ]]; then
	HOSTNAME_OPT=${HOSTNAME_OPT:-localhost}
else
	ask HOSTNAME_OPT "Hostname or IP others will type in the browser" "${HOSTNAME_OPT:-localhost}"
fi

print_firewall() {
	cat <<EOF

Firewall: the container publishes TCP $PORT on $BIND.
  This machine only ($BIND = 127.0.0.1): no firewall change.

  LAN / internet ($BIND = 0.0.0.0), run ONE of these on the HOST:

    Ubuntu / Debian (ufw):
      sudo ufw allow ${PORT}/tcp
      sudo ufw reload

    Fedora / RHEL / CentOS (firewalld):
      sudo firewall-cmd --add-port=${PORT}/tcp --permanent
      sudo firewall-cmd --reload

    nftables / iptables (generic):
      sudo nft add rule inet filter input tcp dport ${PORT} accept
      # or: sudo iptables -A INPUT -p tcp --dport ${PORT} -j ACCEPT

    Cloud VM (AWS / GCP / Azure / DigitalOcean):
      Allow inbound TCP ${PORT} on the security group / firewall / network ACL
      in the provider console, AND on the guest OS if ufw/firewalld is on.

    macOS: Docker Desktop publishes the port; if the macOS firewall is on,
      allow incoming for Docker/OrbStack/Podman.

    Windows: allow TCP ${PORT} inbound in Windows Defender Firewall.

  Then open: http://${HOSTNAME_OPT}:${PORT}/
EOF
}

print_firewall

if [[ "$OPEN_FW" -eq 1 ]]; then
	if [[ "$BIND" != "0.0.0.0" ]]; then
		echo "--open-firewall ignored (bind is $BIND, not 0.0.0.0)"
	elif command -v ufw >/dev/null 2>&1; then
		sudo ufw allow "${PORT}/tcp"
		sudo ufw reload || true
	elif command -v firewall-cmd >/dev/null 2>&1; then
		sudo firewall-cmd --add-port="${PORT}/tcp" --permanent
		sudo firewall-cmd --reload
	else
		echo "No ufw or firewalld found. Open TCP ${PORT} yourself using the commands above." >&2
	fi
fi

NAME=grokboard
VOLUME=grokboard-data
PROTOCOL=http://
[[ "$HTTPS" -eq 1 ]] && PROTOCOL=https://

if [[ "$RESET" -eq 1 ]]; then
	$ENGINE rm -f "$NAME" >/dev/null 2>&1 || true
fi
if [[ "$RESET_DATA" -eq 1 ]]; then
	$ENGINE volume rm "$VOLUME" >/dev/null 2>&1 || true
	echo "Deleted volume $VOLUME."
fi

if [[ "$IMAGE" == "grokboard:local" ]]; then
	echo
	echo "Building $IMAGE (Grok Build CLI is installed in the image)..."
	$ENGINE build -t "$IMAGE" "$ROOT"
else
	echo
	echo "Using image $IMAGE"
	$ENGINE pull "$IMAGE" || true
fi

if $ENGINE inspect "$NAME" >/dev/null 2>&1; then
	echo "Container $NAME already exists. Starting it (setup wizard only runs on first create)."
	echo "To pick a new port, re-run: ./run.sh --reset --port $PORT"
	if [[ "$DETACH" -eq 1 ]]; then
		$ENGINE start "$NAME"
		echo "Running in the background. Logs: $ENGINE logs -f $NAME"
		echo "Sign Grok in from ACP → Extensions → Grok Board."
		exit 0
	fi
	exec $ENGINE start -ai "$NAME"
fi

ask PHPBB_ADMIN_USER "phpBB username"
[[ -n "$PHPBB_ADMIN_USER" ]] || { echo "phpBB username is required" >&2; exit 1; }
if [[ -z "${PHPBB_ADMIN_PASSWORD:-}" ]]; then
	while true; do
		read -r -s -p "phpBB password: " PHPBB_ADMIN_PASSWORD
		echo
		read -r -s -p "Confirm password: " confirm
		echo
		if [[ "$PHPBB_ADMIN_PASSWORD" == "$confirm" && ${#PHPBB_ADMIN_PASSWORD} -ge 6 ]]; then
			unset confirm
			break
		fi
		echo "Passwords must match and be at least 6 characters." >&2
	done
fi
ask PHPBB_ADMIN_EMAIL "Email"
[[ -n "$PHPBB_ADMIN_EMAIL" ]] || { echo "Email is required" >&2; exit 1; }
ask BOARD_NAME "Board title" "Grok Board"

RUN_FLAGS=(run --name "$NAME"
	-p "${BIND}:${PORT}:80"
	-e "SERVER_PORT=${PORT}"
	-e "SERVER_NAME=${HOSTNAME_OPT}"
	-e "SERVER_PROTOCOL=${PROTOCOL}"
	-e "TZ=${TZ:-UTC}"
	-e "PHPBB_ADMIN_USER=${PHPBB_ADMIN_USER}"
	-e "PHPBB_ADMIN_PASSWORD=${PHPBB_ADMIN_PASSWORD}"
	-e "PHPBB_ADMIN_EMAIL=${PHPBB_ADMIN_EMAIL}"
	-e "BOARD_NAME=${BOARD_NAME}"
	-v "${VOLUME}:/data"
)
unset PHPBB_ADMIN_PASSWORD

echo
echo "Starting. Sign Grok into Grok Build from ACP → Extensions → Grok Board after you log in."
if [[ "$DETACH" -eq 1 ]]; then
	$ENGINE "${RUN_FLAGS[@]}" -d --restart unless-stopped "$IMAGE"
	echo "Running in the background. Logs: $ENGINE logs -f $NAME"
	if [[ "$PROTOCOL" == "https://" ]]; then
		echo "Board URL (behind your TLS proxy): ${PROTOCOL}${HOSTNAME_OPT}/"
	else
		echo "Board URL: ${PROTOCOL}${HOSTNAME_OPT}:${PORT}/"
	fi
	exit 0
fi
exec $ENGINE "${RUN_FLAGS[@]}" -it "$IMAGE"
