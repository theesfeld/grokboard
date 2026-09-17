#!/bin/bash
# Grok Board container entrypoint.
# The image has no accounts, API keys, or OAuth tokens. First run collects
# them from the operator and writes them only to /data.
set -euo pipefail

DATA=/data
PHPBB_DIST=/opt/phpbb-dist
PHPBB_ROOT=/var/www/phpbb
GROKBOARD_DIR=/etc/grokboard
GROK_USER=grokbuild

log() { echo "[grokboard] $*" >&2; }

die() {
	log "$*"
	exit 1
}

q() {
	python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$1"
}

prepare_dirs() {
	mkdir -p \
		"$DATA/mysql" \
		"$DATA/phpbb" \
		"$DATA/grokbuild/.grok" \
		"$DATA/grokbuild/workspace" \
		"$DATA/grokbuild/tmp" \
		"$DATA/grokboard" \
		/run/mysqld \
		/run/php \
		/var/www \
		/home/grokbuild

	chown mysql:mysql "$DATA/mysql" /run/mysqld
	chown "$GROK_USER:$GROK_USER" /home/grokbuild "$DATA/grokbuild/.grok"
	chown "$GROK_USER:www-data" "$DATA/grokbuild/workspace" "$DATA/grokbuild/tmp"
	chmod 0770 "$DATA/grokbuild/workspace" "$DATA/grokbuild/tmp"
	chmod 0700 "$DATA/grokbuild/.grok"
	# 0755 so phpBB (www-data) can read auth.status. Secrets in this dir stay 0600.
	chmod 0755 "$DATA/grokboard"

	rm -rf /home/grokbuild/.grok /home/grokbuild/workspace /home/grokbuild/tmp
	ln -s "$DATA/grokbuild/.grok" /home/grokbuild/.grok
	ln -s "$DATA/grokbuild/workspace" /home/grokbuild/workspace
	ln -s "$DATA/grokbuild/tmp" /home/grokbuild/tmp

	rm -rf /etc/grokboard
	ln -s "$DATA/grokboard" /etc/grokboard

	rm -rf /var/www/phpbb
	ln -s "$DATA/phpbb" /var/www/phpbb

	if [[ -f /home/grokbuild/.grok/auth.json ]]; then
		chown "$GROK_USER:$GROK_USER" /home/grokbuild/.grok/auth.json
		chmod 0600 /home/grokbuild/.grok/auth.json
	fi

	# Inherited Grok Build rules (phpBB voice). Overwrite from the image so
	# updates ship; extra *.md files the operator adds in rules/ are left alone.
	install -d -o "$GROK_USER" -g "$GROK_USER" -m 0700 "$DATA/grokbuild/.grok/rules"
	if [[ -d /opt/grokboard/grok-home/rules ]]; then
		install -m 0644 -o "$GROK_USER" -g "$GROK_USER" \
			/opt/grokboard/grok-home/rules/*.md "$DATA/grokbuild/.grok/rules/"
	fi
	if [[ -f /opt/grokboard/grok-home/AGENTS.md ]]; then
		install -m 0644 -o "$GROK_USER" -g www-data \
			/opt/grokboard/grok-home/AGENTS.md "$DATA/grokbuild/workspace/AGENTS.md"
	fi

	local tz=${TZ:-UTC}
	if [[ "$tz" =~ ^[A-Za-z0-9/_+-]+$ ]]; then
		printf 'date.timezone = %s\n' "$tz" >/etc/php/8.3/fpm/conf.d/99-timezone.ini
		printf 'date.timezone = %s\n' "$tz" >/etc/php/8.3/cli/conf.d/99-timezone.ini
		ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
	fi
}

warn_if_ephemeral() {
	if ! awk '$5 == "/data" { found = 1 } END { exit !found }' /proc/self/mountinfo; then
		log "WARNING: /data is not a mounted volume. Forum posts and credentials will vanish when this container is removed."
		log "         Run with: -v grokboard-data:/data"
	fi
}

prompt_value() {
	local var=$1 msg=$2 def=${3:-}
	if [[ -n "${!var:-}" ]]; then
		return
	fi
	if [[ ! -t 0 ]]; then
		[[ -n "$def" ]] || die "Missing $var. Set PHPBB_ADMIN_USER / PHPBB_ADMIN_PASSWORD / PHPBB_ADMIN_EMAIL (or use ./run.sh)."
		printf -v "$var" '%s' "$def"
		return
	fi
	local val
	if [[ -n "$def" ]]; then
		read -r -p "$msg [$def]: " val
		val=${val:-$def}
	else
		read -r -p "$msg: " val
	fi
	[[ -n "$val" ]] || die "$var is required"
	printf -v "$var" '%s' "$val"
}

prompt_password() {
	local var=$1 msg=$2
	if [[ -n "${!var:-}" ]]; then
		return
	fi
	[[ -t 0 ]] || die "Missing $var. Set PHPBB_ADMIN_USER / PHPBB_ADMIN_PASSWORD / PHPBB_ADMIN_EMAIL (or use ./run.sh)."
	local a b
	while true; do
		read -r -s -p "$msg: " a
		echo
		read -r -s -p "Confirm password: " b
		echo
		if [[ "$a" == "$b" && ${#a} -ge 6 && ${#a} -le 30 ]]; then
			printf -v "$var" '%s' "$a"
			unset a b
			return
		fi
		echo "Passwords must match and be 6–30 characters (phpBB’s limit)." >&2
	done
}

load_runtime() {
	local f=$DATA/grokboard/runtime.env
	if [[ -f "$f" ]]; then
		# shellcheck disable=SC1090
		source "$f"
	fi
}

save_runtime() {
	umask 022
	{
		declare -p SERVER_NAME SERVER_PORT SERVER_PROTOCOL BOARD_NAME PHPBB_ADMIN_USER 2>/dev/null || true
	} >"$DATA/grokboard/runtime.env"
	chmod 0644 "$DATA/grokboard/runtime.env"
}

apply_protocol() {
	SERVER_PROTOCOL=${SERVER_PROTOCOL:-http://}
	case "$SERVER_PROTOCOL" in
		http://|https://) ;;
		http) SERVER_PROTOCOL=http:// ;;
		https) SERVER_PROTOCOL=https:// ;;
		*) die "SERVER_PROTOCOL must be http:// or https://" ;;
	esac
	if [[ "$SERVER_PROTOCOL" == "https://" ]]; then
		COOKIE_SECURE=true
	else
		COOKIE_SECURE=false
	fi
	export SERVER_PROTOCOL COOKIE_SECURE
}

board_url() {
	local proto=${SERVER_PROTOCOL:-http://}
	local host=${SERVER_NAME:-localhost}
	local port=${SERVER_PORT:-8080}
	if [[ "$proto" == "https://" && "$port" == "443" ]] || [[ "$proto" == "http://" && "$port" == "80" ]]; then
		BOARD_URL="${proto}${host}/"
	else
		BOARD_URL="${proto}${host}:${port}/"
	fi
}

install_grok_cli() {
	log "Pulling and installing Grok Build CLI."
	curl -fsSL https://x.ai/cli/install.sh | GROK_INSTALL_DIR=/usr/local/bin bash
	if [[ -L /usr/local/bin/grok || -e /root/.grok/bin/grok ]]; then
		cp -L /usr/local/bin/grok /tmp/grok-binary 2>/dev/null || cp /root/.grok/bin/grok /tmp/grok-binary
		rm -f /usr/local/bin/grok /usr/local/bin/agent
		rm -rf /root/.grok
		install -m 0755 /tmp/grok-binary /usr/local/bin/grok
		rm -f /tmp/grok-binary
	fi
	[[ -x /usr/local/bin/grok ]] || die "Grok Build CLI install failed"
	/usr/local/bin/grok --version >&2 || true
}

ensure_grok_cli() {
	if [[ ! -x /usr/local/bin/grok ]]; then
		install_grok_cli
	fi
}

collect_setup() {
	log "First run: this image ships with no accounts or API keys."
	echo
	echo "Create YOUR phpBB admin (this is how you log into the board)."
	prompt_value PHPBB_ADMIN_USER "phpBB username"
	prompt_password PHPBB_ADMIN_PASSWORD "phpBB password"
	prompt_value PHPBB_ADMIN_EMAIL "Email"
	prompt_value BOARD_NAME "Board title" "${BOARD_NAME:-Grok Board}"
	prompt_value SERVER_NAME "Hostname others will type in the browser" "${SERVER_NAME:-localhost}"
	prompt_value SERVER_PORT "Public port (must match the public URL; 443 if HTTPS is terminated in front)" "${SERVER_PORT:-8080}"
	[[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || die "SERVER_PORT must be numeric"
	apply_protocol
	if [[ ${#PHPBB_ADMIN_PASSWORD} -lt 6 || ${#PHPBB_ADMIN_PASSWORD} -gt 30 ]]; then
		die "phpBB passwords must be 6–30 characters"
	fi
	export PHPBB_ADMIN_USER PHPBB_ADMIN_PASSWORD PHPBB_ADMIN_EMAIL BOARD_NAME SERVER_NAME SERVER_PORT SERVER_PROTOCOL COOKIE_SECURE
	export ADMIN_EMAIL="$PHPBB_ADMIN_EMAIL"
	export BOARD_EMAIL="$PHPBB_ADMIN_EMAIL"
	export BOARD_CONTACT="$PHPBB_ADMIN_EMAIL"
	export GROK_BOT_EMAIL="grok@localhost"
	export TZ="${TZ:-UTC}"
}

init_mysql() {
	if [[ ! -d "$DATA/mysql/mysql" ]]; then
		log "Initializing MariaDB datadir on the volume."
		mariadb-install-db --user=mysql --datadir="$DATA/mysql" --skip-test-db --auth-root-authentication-method=socket >/tmp/mysql-install.log
		rm -f /tmp/mysql-install.log
	fi
}

wait_for_mysql() {
	local i
	for i in $(seq 1 60); do
		if mariadb-admin --protocol=socket ping >/dev/null 2>&1; then
			return 0
		fi
		sleep 1
	done
	die "MariaDB did not become ready"
}

start_mysql() {
	mariadbd --user=mysql --datadir="$DATA/mysql" --socket=/run/mysqld/mysqld.sock --pid-file=/run/mysqld/mysqld.pid --log-error=/dev/stderr &
	MYSQL_PID=$!
	wait_for_mysql
}

stop_mysql() {
	if [[ -n "${MYSQL_PID:-}" ]] && kill -0 "$MYSQL_PID" 2>/dev/null; then
		kill "$MYSQL_PID" 2>/dev/null || true
		wait "$MYSQL_PID" 2>/dev/null || true
		MYSQL_PID=
	fi
}

phpbb_installed() {
	[[ -s "$DATA/phpbb/config.php" ]] && grep -q "dbname" "$DATA/phpbb/config.php"
}

seed_phpbb_tree() {
	if [[ ! -f "$DATA/phpbb/app.php" ]]; then
		log "Copying phpBB into the data volume."
		rsync -a "$PHPBB_DIST/" "$DATA/phpbb/"
	fi
	# Chown the real directory. PHPBB_ROOT is a symlink; chown -R on a
	# symlink does not traverse (GNU chown -P) so www-data would not own files.
	chown -R www-data:www-data "$DATA/phpbb"
	chmod 0777 "$DATA/phpbb/cache" "$DATA/phpbb/store" "$DATA/phpbb/files" "$DATA/phpbb/images/avatars/upload" 2>/dev/null || true
}

install_phpbb() {
	local db_pass yaml
	db_pass=$(openssl rand -hex 24)
	log "Creating database (password stays on the volume, not in the image)."
	mariadb --protocol=socket -u root <<SQL
CREATE DATABASE IF NOT EXISTS phpbb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'phpbb'@'localhost' IDENTIFIED BY '${db_pass}';
ALTER USER 'phpbb'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON phpbb.* TO 'phpbb'@'localhost';
FLUSH PRIVILEGES;
SQL

	chmod 0666 "$DATA/phpbb/config.php"
	yaml="$DATA/phpbb/install/install-config.yml"
	old_umask=$(umask)
	umask 077
	cat >"$yaml" <<YAML
installer:
    admin:
        name: $(q "$PHPBB_ADMIN_USER")
        password: $(q "$PHPBB_ADMIN_PASSWORD")
        email: $(q "$PHPBB_ADMIN_EMAIL")
    board:
        lang: en
        name: $(q "$BOARD_NAME")
        description: "Just you and Grok. Real phpBB. Actual threads."
    database:
        dbms: mysqli
        dbhost: localhost
        dbport: ~
        dbuser: phpbb
        dbpasswd: $(q "$db_pass")
        dbname: phpbb
        table_prefix: phpbb_
    email:
        enabled: false
        smtp_delivery: ~
        smtp_host: ~
        smtp_port: ~
        smtp_auth: ~
        smtp_user: ~
        smtp_pass: ~
    server:
        cookie_secure: ${COOKIE_SECURE:-false}
        server_protocol: $(q "${SERVER_PROTOCOL:-http://}")
        force_server_vars: true
        server_name: $(q "$SERVER_NAME")
        server_port: ${SERVER_PORT}
        script_path: /
    extensions: []
YAML
	chown www-data:www-data "$yaml"
	chmod 0600 "$yaml"

	log "Installing phpBB as admin '${PHPBB_ADMIN_USER}'."
	local logf=/tmp/phpbb-install.log
	if ! sudo -u www-data php "$DATA/phpbb/install/phpbbcli.php" install "$yaml" >"$logf" 2>&1; then
		rm -f "$yaml"
		grep -E 'ERROR|Error|error' "$logf" >&2 || tail -40 "$logf" >&2
		die "phpBB CLI installer failed"
	fi
	if grep -q '\[ERROR\]' "$logf"; then
		rm -f "$yaml"
		grep '\[ERROR\]' -A2 "$logf" >&2
		die "phpBB CLI installer reported errors"
	fi
	rm -f "$yaml" "$logf"
	umask "$old_umask"
	unset db_pass PHPBB_ADMIN_PASSWORD
	export -n PHPBB_ADMIN_PASSWORD 2>/dev/null || true

	grep -q "dbname" "$DATA/phpbb/config.php" || die "phpBB config.php was not written"
	chown www-data:www-data "$DATA/phpbb/config.php"
	chmod 0640 "$DATA/phpbb/config.php"
	rm -rf "$DATA/phpbb/install"
}

refresh_extension() {
	install -d -o www-data -g www-data "$DATA/phpbb/ext/grokboard"
	rm -rf "$DATA/phpbb/ext/grokboard/grok"
	cp -a /opt/grokboard/ext/grokboard/grok "$DATA/phpbb/ext/grokboard/grok"
	chown -R www-data:www-data "$DATA/phpbb/ext/grokboard"
	# Drop compiled templates so ACP/board events from the image are used.
	rm -rf "$DATA/phpbb/cache/twig" "$DATA/phpbb/cache/production"
	find "$DATA/phpbb/cache" -maxdepth 1 -type f -name '*.php' -delete 2>/dev/null || true
}

enable_extension() {
	sudo -u www-data php "$PHPBB_ROOT/bin/phpbbcli.php" ext:enable grokboard/grok >/tmp/phpbb-ext.log 2>&1 \
		|| sudo -u www-data php "$PHPBB_ROOT/bin/phpbbcli.php" db:migrate --safe-mode >/tmp/phpbb-ext.log 2>&1 \
		|| true
	rm -f /tmp/phpbb-ext.log
}

setup_board() {
	php /opt/grokboard/deploy/setup-board.php || die "setup-board.php failed"
	mariadb --protocol=socket phpbb -e "CREATE TABLE IF NOT EXISTS phpbb_grok_sessions (
		topic_id INT UNSIGNED NOT NULL PRIMARY KEY,
		session_id VARCHAR(80) NOT NULL DEFAULT '',
		workspace VARCHAR(255) NOT NULL DEFAULT ''
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"
}

have_grok_auth() {
	[[ -s /home/grokbuild/.grok/auth.json ]] || [[ -s "$GROKBOARD_DIR/xai.env" ]]
}

start_services() {
	log "Starting php-fpm and Caddy."
	php-fpm8.3 --nodaemonize &
	PHP_PID=$!
	caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
	CADDY_PID=$!
}

term() {
	log "Shutting down."
	kill -TERM "${CADDY_PID:-}" "${PHP_PID:-}" "${MYSQL_PID:-}" 2>/dev/null || true
	wait 2>/dev/null || true
}

cmd=${1:-}
case "$cmd" in
	login|grokboard-login)
		prepare_dirs
		exec /usr/local/sbin/grokboard-login.sh "${2:-}"
		;;
	bash|sh)
		prepare_dirs
		exec "$@"
		;;
esac

prepare_dirs
load_runtime
apply_protocol
warn_if_ephemeral
ensure_grok_cli

first_run=0
if ! phpbb_installed; then
	first_run=1
	collect_setup
fi

init_mysql
start_mysql
trap term SIGTERM SIGINT

seed_phpbb_tree

if [[ "$first_run" -eq 1 ]]; then
	install_phpbb
	refresh_extension
	enable_extension
	setup_board
	save_runtime
	log "Setup complete."
	if [[ "$SERVER_PROTOCOL" == "https://" ]]; then
		log "Open ${SERVER_PROTOCOL}${SERVER_NAME}/ and log in as ${PHPBB_ADMIN_USER}"
	else
		log "Open ${SERVER_PROTOCOL}${SERVER_NAME}:${SERVER_PORT}/ and log in as ${PHPBB_ADMIN_USER}"
	fi
	log "Grok is a separate board user and does not use your admin password."
	log "Sign Grok into Grok Build from phpBB ACP → Extensions → Grok Board (device code or API key). No docker exec."
	if [[ "${SERVER_NAME}" != "localhost" && "${SERVER_NAME}" != "127.0.0.1" ]]; then
		log "If this host has a firewall, allow TCP port ${SERVER_PORT} inbound (see README)."
	fi
else
	refresh_extension
	enable_extension
fi

/usr/local/sbin/grokboard-auth status >/dev/null || true
if ! have_grok_auth; then
	log "Grok Build is not signed in. ACP → Extensions → Grok Board."
fi

start_services
board_url
log "READY. Grok Board is running in the background as this container."
log "Open ${BOARD_URL}"
if [[ "$first_run" -eq 1 && -n "${PHPBB_ADMIN_USER:-}" ]]; then
	log "Log in as ${PHPBB_ADMIN_USER}. Sign Grok in from ACP → Extensions → Grok Board."
fi

wait -n
status=$?
term
exit "$status"
