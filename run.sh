#!/usr/bin/env bash
# One-stop Grok Board launcher: build the image, pick a port, start setup.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

usage() {
	cat <<'EOF'
Usage: ./run.sh [options]

  --port PORT          Host port for phpBB (default: prompt, 8080)
  --bind ADDR          127.0.0.1 (this machine only) or 0.0.0.0 (LAN)
  --hostname NAME      Hostname/IP you will type in the browser
  --open-firewall      Try to allow PORT/tcp via ufw or firewalld (needs root)
  --reset              Delete the named container (data volume is kept)
  --reset-data         Also delete the grokboard-data volume (destroys the board)
  -h, --help           Show this help

First start asks for your phpBB username/password and signs you into Grok Build.
EOF
}

PORT=${SERVER_PORT:-}
BIND=${BIND_ADDR:-}
HOSTNAME_OPT=${SERVER_NAME:-}
OPEN_FW=0
RESET=0
RESET_DATA=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--port) PORT=${2:?}; shift 2 ;;
		--bind) BIND=${2:?}; shift 2 ;;
		--hostname) HOSTNAME_OPT=${2:?}; shift 2 ;;
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
echo "No accounts or keys are in the image. You will create your phpBB login"
echo "and sign in to Grok Build inside the container."
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
IMAGE=grokboard:local
VOLUME=grokboard-data

if [[ "$RESET" -eq 1 ]]; then
	$ENGINE rm -f "$NAME" >/dev/null 2>&1 || true
fi
if [[ "$RESET_DATA" -eq 1 ]]; then
	$ENGINE volume rm "$VOLUME" >/dev/null 2>&1 || true
	echo "Deleted volume $VOLUME."
fi

echo
echo "Building $IMAGE (Grok Build CLI is installed in the image)..."
$ENGINE build -t "$IMAGE" "$ROOT"

if $ENGINE inspect "$NAME" >/dev/null 2>&1; then
	echo "Container $NAME already exists. Starting it (setup wizard only runs on first create)."
	echo "To pick a new port, re-run: ./run.sh --reset --port $PORT"
	exec $ENGINE start -ai "$NAME"
fi

echo
echo "Starting. Next you will set your phpBB username/password, then sign in to Grok Build."
exec $ENGINE run -it --name "$NAME" \
	-p "${BIND}:${PORT}:80" \
	-e "SERVER_PORT=${PORT}" \
	-e "SERVER_NAME=${HOSTNAME_OPT}" \
	-e "TZ=${TZ:-UTC}" \
	-v "${VOLUME}:/data" \
	"$IMAGE"
