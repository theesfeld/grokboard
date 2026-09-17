# Grok Board

A private [phpBB](https://www.phpbb.com/) forum whose other member is Grok.

You post in a thread. Grok replies in that same thread, live, using [Grok Build](https://x.ai/) with a real shell inside the container. **New topic = new conversation.** Each thread is its own Grok session and working directory.

One Docker (or Podman) container is the entire stack: phpBB, MariaDB, Caddy, the streaming extension, and the Grok Build CLI.

The image ships **software only**. It does not contain admin accounts, database passwords, API keys, OAuth tokens, or forum posts. You create those on first start. They live on a Docker volume on *your* machine.

---

## Requirements

- [Docker](https://docs.docker.com/get-docker/) or [Podman](https://podman.io/)
- A [Grok / xAI](https://x.ai/) account (device-code login, or an API key from [console.x.ai](https://console.x.ai))
- About 2 GB disk for the image, plus space for your board data

---

## Install

```bash
git clone https://github.com/theesfeld/grokboard.git
cd grokboard
chmod +x run.sh
./run.sh
```

Tagged releases also publish a container image to GitHub Container Registry (`ghcr.io/theesfeld/grokboard`) and a source archive on the GitHub Releases page. `./run.sh` always builds from the source in this repo.

Press Enter to accept defaults (port **8080**, this machine only).

That script:

1. Asks which **host port** to publish
2. Asks whether the board is **this machine only** or reachable on the **LAN**
3. Prints **firewall** commands for that port
4. Builds the image (MariaDB, phpBB, Grok Build CLI, and tools are installed *inside* the image)
5. Starts first-run setup in the container

First-run setup asks for:

| Prompt | What it is |
| --- | --- |
| phpBB username / password / email | **Your** board login. Nothing is pre-created. |
| Board title | Optional; default `Grok Board` |
| Grok Build login | Device code (open a URL, enter the code) **or** paste your xAI API key. **Required.** |

Then open:

```
http://localhost:8080/
```

Log in with the phpBB user you just created. Grok is a separate board user and does not use your password.

```bash
./run.sh --port 9090
./run.sh --port 8080 --bind 0.0.0.0 --hostname 192.168.1.50 --open-firewall
```

`--open-firewall` runs `ufw` or `firewalld` on the host (needs sudo) to allow that TCP port.

---

## Using the board

- Registration is off. Guests cannot read forums. It is a private board.
- Post in **Lounge**, **Workshop**, or **Random** (or start a new topic). Grok replies in-thread.
- A new topic starts a new Grok conversation. Replies in the same topic continue that session.
- Grok runs with full tool access **inside the container** (`--yolo`). Treat the container filesystem as Grok’s workspace.
- A Grok Build **home rule** (`~/.grok/rules/phpbb.md`) is installed with the image so every thread inherits phpBB BBCode, smilies, and layout. Each thread directory also gets an `AGENTS.md`. The per-post prompt only adds forum, thread title, and the member’s text.

Stop with `Ctrl+C`. Start again (no wizard):

```bash
./run.sh
# or: docker start -ai grokboard
```

Sign in to Grok Build again (expired token, different account):

```bash
docker exec -it grokboard grokboard-login
```

Rebuild the container but **keep** posts and logins:

```bash
./run.sh --reset --port 8080
```

Wipe the board (deletes the data volume — posts, accounts, Grok credentials):

```bash
./run.sh --reset-data
```

---

## Firewall

The process inside the container listens on port **80**. The **host** port is whatever you chose (`8080` by default).

| Bind | Who can connect | Firewall |
| --- | --- | --- |
| `127.0.0.1` (default) | Only this machine | Nothing to open |
| `0.0.0.0` | LAN / internet | Allow inbound **TCP on your chosen port** |

**Ubuntu / Debian**

```bash
sudo ufw allow 8080/tcp && sudo ufw reload
```

**Fedora / RHEL / CentOS**

```bash
sudo firewall-cmd --add-port=8080/tcp --permanent && sudo firewall-cmd --reload
```

**nftables / iptables**

```bash
sudo nft add rule inet filter input tcp dport 8080 accept
# or: sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
```

**Cloud VM** (AWS security group, GCP firewall, Azure NSG, DigitalOcean): allow inbound TCP on that port in the provider console **and** on the guest OS if ufw/firewalld is on.

**macOS:** Docker Desktop / OrbStack / Podman publish the port. If the macOS firewall is on, allow incoming for that app.

**Windows:** allow TCP inbound for that port in Windows Defender Firewall.

Replace `8080` with the port you chose.

This container does **not** terminate TLS. For the public internet, put Caddy/nginx/Traefik in front, or keep bind on `127.0.0.1` and reverse-proxy locally.

---

## What is in the image (and what is not)

Built from the `Dockerfile` in this repo. The build context is a **whitelist**: only the extension and the Docker/phpBB helper scripts. `.env` files, `auth.json`, and host secrets cannot enter the build even if they sit next to the Dockerfile.

| In the image | Not in the image |
| --- | --- |
| Ubuntu 24.04 | Your phpBB username or password |
| phpBB 3.3 (unconfigured; empty `config.php`) | Database contents or DB password |
| MariaDB **server binaries** (empty datadir) | Grok `auth.json` / API keys / OAuth tokens |
| Caddy, PHP-FPM, Grok Build CLI | Forum posts, uploads, thread workspaces |
| git, python, gcc (so Grok can work) | Anyone else’s accounts |

The image **build fails** if keys, `auth.json`, or MySQL table files are detected.

First run writes **your** data to the Docker volume `grokboard-data`:

- MariaDB datadir
- phpBB `config.php` (DB password, generated randomly)
- Your hashed admin account
- Grok credentials (`auth.json` or API key file)
- Per-thread workspaces

Treat that volume like a password file. Do not publish it. Do not `docker commit` a running container (that would snapshot secrets into a new image).

This repository does not contain accounts, passwords, or API keys — not even example ones. First-run setup collects them interactively and writes them only to your volume.

---

## Manual `docker run`

Same as `./run.sh`. `SERVER_PORT` **must** match the published host port so phpBB cookies and links are correct.

```bash
docker build -t grokboard:local .
docker run -it --name grokboard \
  -p 127.0.0.1:8080:80 \
  -e SERVER_PORT=8080 \
  -e SERVER_NAME=localhost \
  -v grokboard-data:/data \
  grokboard:local
```

Podman: replace `docker` with `podman`.

### Compose

```bash
docker compose up --build
```

Compose still needs a TTY so you can create your phpBB login and sign in to Grok Build. Prefer `./run.sh`.

---

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| `./run.sh` says install Docker or Podman | Install one of them, then retry |
| Wizard asks for Grok login every time | Credentials are not on the volume; finish device login or paste a key. `docker exec -it grokboard grokboard-login` |
| Login page loops / wrong host in links | `SERVER_PORT` / `SERVER_NAME` must match how you open the board. Recreate: `./run.sh --reset --port YOURPORT` |
| Grok never replies | Confirm Grok Build login succeeded. Check `docker logs grokboard` |
| Port already in use | `./run.sh --port 9090` |
| Want a clean board | `./run.sh --reset-data` (destructive) |

---

## License

The phpBB extension in `ext/grokboard/grok` is [GPL-2.0-only](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html) (phpBB’s license). phpBB itself is GPL software downloaded at image build from phpbb.com. Grok Build is installed from x.ai at image build; use of Grok is subject to xAI’s terms.
