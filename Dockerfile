# Grok Board — phpBB + Grok Build CLI.
# This image contains software only. No admin accounts, DB passwords,
# API keys, or OAuth tokens are baked in. First run writes those to /data.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
	LANG=en_US.UTF-8 \
	LC_ALL=en_US.UTF-8 \
	TZ=UTC \
	HOME=/root

ARG PHPBB_VERSION=3.3.17
ARG PHPBB_SHA256_BZ2=b52fd231e612a099c0af1d2dcb73a79f7d03926a482842c4ee2830d12f461b67
ARG CADDY_VERSION=2.10.2
ARG TARGETARCH=amd64

RUN printf '#!/bin/sh\nexit 101\n' >/usr/sbin/policy-rc.d \
	&& chmod +x /usr/sbin/policy-rc.d \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		bash \
		build-essential \
		ca-certificates \
		curl \
		file \
		git \
		iputils-ping \
		jq \
		locales \
		mariadb-server \
		openssl \
		patch \
		procps \
		python3-pip \
		python3-venv \
		php8.3-bcmath \
		php8.3-cli \
		php8.3-curl \
		php8.3-fpm \
		php8.3-gd \
		php8.3-gmp \
		php8.3-intl \
		php8.3-mbstring \
		php8.3-mysql \
		php8.3-opcache \
		php8.3-xml \
		php8.3-zip \
		python3 \
		rsync \
		sudo \
		tini \
		tzdata \
		unzip \
		bzip2 \
	&& sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
	&& locale-gen \
	&& rm -rf /var/lib/apt/lists/* /var/lib/mysql/* \
	&& rm -f /etc/mysql/debian.cnf /root/.my.cnf /root/.mysql_history

RUN set -eux; \
	arch="${TARGETARCH}"; \
	case "$arch" in \
		amd64) caddy_arch=amd64 ;; \
		arm64) caddy_arch=arm64 ;; \
		*) echo "unsupported TARGETARCH=$arch" >&2; exit 1 ;; \
	esac; \
	curl -fsSL "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${caddy_arch}.tar.gz" \
		| tar -xz -C /usr/local/bin caddy; \
	chmod 755 /usr/local/bin/caddy; \
	caddy version

RUN set -eux; \
	curl -fsSL https://x.ai/cli/install.sh | GROK_INSTALL_DIR=/usr/local/bin bash; \
	# Installer leaves a symlink from /usr/local/bin/grok -> /root/.grok/bin/grok.
	# Copy the real binary out, then delete the installer home so the image
	# cannot ship a grok profile or credentials.
	cp -L /usr/local/bin/grok /tmp/grok-binary; \
	rm -f /usr/local/bin/grok /usr/local/bin/agent; \
	rm -rf /root/.grok; \
	install -m 0755 /tmp/grok-binary /usr/local/bin/grok; \
	rm -f /tmp/grok-binary; \
	sed -i '/\.grok\/bin/d' /root/.bashrc 2>/dev/null || true; \
	/usr/local/bin/grok --version

RUN set -eux; \
	curl -fsSL -o /tmp/phpbb.tar.bz2 "https://download.phpbb.com/pub/release/3.3/${PHPBB_VERSION}/phpBB-${PHPBB_VERSION}.tar.bz2"; \
	echo "${PHPBB_SHA256_BZ2}  /tmp/phpbb.tar.bz2" | sha256sum -c -; \
	mkdir -p /tmp/phpbb-src /opt/phpbb-dist; \
	tar -xjf /tmp/phpbb.tar.bz2 -C /tmp/phpbb-src; \
	src=$(find /tmp/phpbb-src -mindepth 1 -maxdepth 1 -type d | head -1); \
	rsync -a "$src"/ /opt/phpbb-dist/; \
	rm -f /opt/phpbb-dist/docs/install-config.sample.yml; \
	rm -rf /tmp/phpbb.tar.bz2 /tmp/phpbb-src

RUN useradd --system --create-home --home-dir /home/grokbuild --shell /usr/sbin/nologin grokbuild \
	&& usermod -aG grokbuild www-data \
	&& printf '%s\n' \
		'Defaults:www-data !requiretty' \
		'www-data ALL=(grokbuild) NOPASSWD: /usr/local/sbin/grok-phpbb' \
		'www-data ALL=(root) NOPASSWD: /usr/local/sbin/grokboard-auth' \
		>/etc/sudoers.d/grok-phpbb \
	&& chmod 440 /etc/sudoers.d/grok-phpbb \
	&& visudo -cf /etc/sudoers.d/grok-phpbb \
	&& rm -rf /home/grokbuild/.grok

COPY deploy/grok-phpbb /usr/local/sbin/grok-phpbb
COPY docker/entrypoint.sh /usr/local/sbin/entrypoint.sh
COPY docker/grokboard-login.sh /usr/local/sbin/grokboard-login.sh
COPY docker/grokboard-auth.py /usr/local/sbin/grokboard-auth
COPY docker/Caddyfile /etc/caddy/Caddyfile
COPY docker/mariadb.cnf /etc/mysql/mariadb.conf.d/99-grokboard.cnf
COPY docker/php-grokboard.ini /etc/php/8.3/fpm/conf.d/99-grokboard.ini
COPY docker/php-grokboard.ini /etc/php/8.3/cli/conf.d/99-grokboard.ini
COPY docker/assert-clean.sh /usr/local/sbin/assert-clean.sh
COPY deploy/setup-board.php /opt/grokboard/deploy/setup-board.php
COPY docker/grok-home /opt/grokboard/grok-home
COPY ext /opt/grokboard/ext

RUN chmod 755 /usr/local/sbin/grok-phpbb /usr/local/sbin/entrypoint.sh /usr/local/sbin/grokboard-login.sh /usr/local/sbin/grokboard-auth /usr/local/sbin/assert-clean.sh \
	&& ln -sf /usr/local/sbin/grokboard-login.sh /usr/local/sbin/grokboard-login \
	&& printf '\nphp_admin_value[output_buffering] = 0\nphp_admin_flag[zlib.output_compression] = off\nphp_admin_value[max_execution_time] = 3600\nrequest_terminate_timeout = 3600\n' \
		>>/etc/php/8.3/fpm/pool.d/www.conf \
	&& sed -i 's#^error_log = .*#error_log = /proc/self/fd/2#' /etc/php/8.3/fpm/php-fpm.conf \
	&& sed -i 's#^;daemonize = yes#daemonize = no#; s#^daemonize = yes#daemonize = no#' /etc/php/8.3/fpm/php-fpm.conf \
	&& rm -rf /root/.grok /home/grokbuild/.grok /var/lib/mysql/* \
	&& rm -f /etc/mysql/debian.cnf /root/.my.cnf /root/.mysql_history \
	&& find /opt/grokboard /opt/phpbb-dist /usr/local/sbin /etc/caddy -type f \( -name '*.env' -o -name 'auth.json' -o -name 'oauth.json' -o -name 'secrets.env' \) -delete \
	&& php-fpm8.3 -t \
	&& /usr/local/sbin/assert-clean.sh

VOLUME ["/data"]
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
	CMD curl -fsS -o /dev/null "http://127.0.0.1/ucp.php?mode=login" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/sbin/entrypoint.sh"]
