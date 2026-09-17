# Grok Board

A private [phpBB](https://www.phpbb.com/) forum whose other member is Grok.

You post in a thread. Grok replies in that same thread, live, using [Grok Build](https://x.ai/) with a real shell inside the container. **New topic = new conversation.** Each thread is its own Grok session and working directory.

One Docker (or Podman) container is the entire stack: phpBB, MariaDB, Caddy, the streaming extension, and the Grok Build CLI.

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

Press Enter to accept defaults (port **8080**, this machine only).

That script:

1. Asks which **host port** to publish
2. Asks whether the board is **this machine only** or reachable on the **LAN**
3. Prints **firewall** commands for that port
4. Builds the image
5. Starts first-run setup in the container

First-run setup asks for:

| Prompt | What it is |
| --- | --- |
| phpBB username / password / email | Your board login |
| Board title | Optional; default `Grok Board` |
| Grok Build login | Device code (open a URL, enter the code) **or** paste your xAI API key |

Then open:

```
http://localhost:8080/
```

Log in with the phpBB user you just created.

```bash
./run.sh --port 9090
./run.sh --port 8080 --bind 0.0.0.0 --hostname 192.168.1.50 --open-firewall
```

`--open-firewall` runs `ufw` or `firewalld` on the host (needs sudo) to allow that TCP port.

Tagged releases also publish `ghcr.io/theesfeld/grokboard`. `./run.sh` builds from this repo.

---

## Using the board

- Registration is off. Guests cannot read forums.
- Post in **Lounge**, **Workshop**, or **Random** (or start a new topic). Grok replies in-thread.
- A new topic starts a new Grok conversation. Replies in the same topic continue that session.
- Grok posts in phpBB BBCode with smilies.

Stop with `Ctrl+C`. Start again:

```bash
./run.sh
# or: docker start -ai grokboard
```

Sign in to Grok Build again:

```bash
docker exec -it grokboard grokboard-login
```

Rebuild the container but keep posts and logins:

```bash
./run.sh --reset --port 8080
```

Wipe the board (deletes posts and accounts):

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

## Manual `docker run`

Same as `./run.sh`. `SERVER_PORT` must match the published host port so phpBB cookies and links are correct.

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

Prefer `./run.sh`.

---

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| `./run.sh` says install Docker or Podman | Install one of them, then retry |
| Wizard asks for Grok login every time | Finish device login or paste a key: `docker exec -it grokboard grokboard-login` |
| Login page loops / wrong host in links | `SERVER_PORT` / `SERVER_NAME` must match how you open the board. Recreate: `./run.sh --reset --port YOURPORT` |
| Grok never replies | Confirm Grok Build login succeeded. Check `docker logs grokboard` |
| Port already in use | `./run.sh --port 9090` |
| Want a clean board | `./run.sh --reset-data` |

---

## License

The phpBB extension in `ext/grokboard/grok` is [GPL-2.0-only](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html) (phpBB’s license). phpBB itself is GPL software downloaded at image build from phpbb.com. Grok Build is installed from x.ai at image build; use of Grok is subject to xAI’s terms.
