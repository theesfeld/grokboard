#!/bin/bash
# Interactive Grok Build authentication. Writes only to the data volume.
# Pass "required" as $1 to refuse to continue without credentials.
set -euo pipefail

GROKBOARD_DIR=${GROKBOARD_DIR:-/etc/grokboard}
GROK_USER=${GROK_USER:-grokbuild}
XAI_ENV="$GROKBOARD_DIR/xai.env"
REQUIRED=0
[[ "${1:-}" == "required" ]] && REQUIRED=1 && shift || true
choice=${1:-}

log() { echo "[grokboard] $*" >&2; }

die() {
	log "$*"
	exit 1
}

have_auth() {
	local auth="/home/${GROK_USER}/.grok/auth.json"
	[[ -s "$auth" ]] || [[ -s "$XAI_ENV" ]]
}

write_api_key() {
	local key=$1
	[[ -n "$key" ]] || die "API key was empty"
	install -d -m 0700 "$GROKBOARD_DIR"
	local tmp="$XAI_ENV.tmp"
	umask 077
	printf 'XAI_API_KEY=%s\n' "$key" >"$tmp"
	chmod 0600 "$tmp"
	chown "$GROK_USER:$GROK_USER" "$tmp"
	mv "$tmp" "$XAI_ENV"
	log "API key stored on the data volume (not in the image)."
}

device_login() {
	[[ -x /usr/local/bin/grok ]] || die "Grok Build CLI is missing from the container"
	log "Starting Grok Build device-code login."
	log "A URL and code will print below. Open the URL on any phone or laptop, enter the code, then wait here."
	sudo -u "$GROK_USER" -H /usr/local/bin/grok login --device-auth
	log "Device login finished."
}

if have_auth && [[ "$REQUIRED" -eq 1 ]]; then
	log "Grok Build credentials are already on the data volume."
	exit 0
fi

if [[ -z "$choice" ]]; then
	if [[ -n "${XAI_API_KEY:-}" ]]; then
		choice=key
	elif [[ "${GROK_LOGIN:-}" == "device" || "${GROK_LOGIN:-}" == "oauth" ]]; then
		choice=device
	elif [[ "${GROK_LOGIN:-}" == "skip" && "$REQUIRED" -eq 0 ]]; then
		choice=skip
	elif [[ -t 0 ]]; then
		echo
		echo "Grok Build authentication (required for Grok to post)."
		echo "Credentials stay on the data volume. Nothing is baked into the image."
		echo "  1) Sign in with a device code  (open a URL, enter the code)  [default]"
		echo "  2) Paste an xAI API key from https://console.x.ai"
		read -r -p "Choice [1]: " raw
		case "${raw:-1}" in
			2) choice=key ;;
			*) choice=device ;;
		esac
	else
		die "Grok Build login is required. Prefer phpBB ACP → Extensions → Grok Board. Or run with -it, or set XAI_API_KEY / GROK_LOGIN=device."
	fi
fi

case "$choice" in
	key|api|2)
		key=${XAI_API_KEY:-}
		if [[ -z "$key" ]]; then
			[[ -t 0 ]] || die "XAI_API_KEY is not set"
			read -r -s -p "xAI API key: " key
			echo
		fi
		write_api_key "$key"
		unset key XAI_API_KEY
		;;
	device|oauth|1)
		[[ -t 0 ]] || die "Device login needs an interactive terminal (./run.sh, or docker run -it / docker exec -it)"
		device_login
		;;
	skip)
		[[ "$REQUIRED" -eq 0 ]] || die "Grok Build login is required on first run."
		log "Skipping Grok auth."
		;;
	*)
		die "Unknown auth choice: $choice"
		;;
esac

if have_auth; then
	log "Grok Build is authenticated on the data volume."
else
	if [[ "$REQUIRED" -eq 1 ]]; then
		die "Grok Build login did not produce credentials. Re-run: docker exec -it grokboard grokboard-login"
	fi
	log "No Grok credentials yet."
fi
