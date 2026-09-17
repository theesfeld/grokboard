#!/bin/bash
# Fail the image build if required software is missing or if any
# credentials / database content were accidentally copied in.
set -euo pipefail

missing=0
for c in mariadbd mariadb mariadb-install-db php-fpm8.3 php caddy grok git python3 gcc tini; do
	if ! command -v "$c" >/dev/null 2>&1; then
		echo "missing required binary: $c" >&2
		missing=1
	fi
done
[[ "$missing" -eq 0 ]]

[[ -f /opt/phpbb-dist/app.php ]]
[[ -f /opt/grokboard/ext/grokboard/grok/ext.php ]]
[[ -x /usr/local/sbin/grok-phpbb ]]
[[ -x /usr/local/bin/grok ]]

if find /var/lib/mysql -mindepth 1 2>/dev/null | grep -q .; then
	echo "MariaDB datadir in the image is not empty (would ship database content)" >&2
	find /var/lib/mysql -mindepth 1 >&2
	exit 1
fi

if [[ -s /opt/phpbb-dist/config.php ]]; then
	echo "phpBB dist config.php is not empty (would ship board credentials)" >&2
	exit 1
fi

leaks=$(find /root /home /opt /usr/local/sbin /etc/caddy /etc/grokboard /etc/mysql \
	-type f \( \
		-name 'auth.json' -o -name 'oauth.json' -o -name 'secrets.env' \
		-o -name 'xai.env' -o -name '.my.cnf' -o -name 'debian.cnf' \
		-o -name '*.pem' -o -name 'id_rsa*' \
	\) 2>/dev/null || true)
if [[ -n "$leaks" ]]; then
	echo "credential-like files in the image:" >&2
	echo "$leaks" >&2
	exit 1
fi

if [[ -d /root/.grok || -d /home/grokbuild/.grok ]]; then
	echo "a grok home directory is present; it must not ship" >&2
	exit 1
fi

if env | grep -Ei '^(XAI_API_KEY|PHPBB_ADMIN_PASSWORD|PHPBB_ADMIN_USER|DB_PASS)=' | grep -qv '=$'; then
	echo "secret-bearing environment variables are set in the image" >&2
	env | grep -Ei '^(XAI_API_KEY|PHPBB_ADMIN_PASSWORD|PHPBB_ADMIN_USER|DB_PASS)=' >&2
	exit 1
fi

echo "assert-clean: mariadb+php+caddy+grok present; no keys, accounts, or database files"
