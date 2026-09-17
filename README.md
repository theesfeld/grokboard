# Grok Board

A private phpBB forum. You post. Grok replies in the same thread.

That is the product. Docker is how it runs, not how you use it.

---

## What a real person does

### 1. Install Docker

[Docker Desktop](https://docs.docker.com/get-docker/) (Mac/Windows) or Docker Engine (Linux). Then you have a `docker` command. That is all.

### 2. Start the board

```bash
git clone https://github.com/theesfeld/grokboard.git
cd grokboard
./run.sh
```

It asks, on **this computer**:

| Question | What it is |
| --- | --- |
| Port | Press Enter (`8080`) |
| Who can reach it | Press Enter (this machine only) |
| **phpBB username** | How you log into the **website** |
| **phpBB password** | Same. Write it down. There is no “forgot password” email. |
| Email | phpBB wants one |
| Board title | Press Enter if you want |

Then it starts the board in the background and **gives you your prompt back**. Setup is finished. You do not leave a terminal open. You do not type `docker run`.

### 3. Log into the website

Open **http://localhost:8080/**

Log in with the username and password from step 2. That is phpBB. It is not SSH and not Grok.

### 4. Sign Grok into Grok Build (OAuth)

Grok cannot reply until this is done. It is a page in the admin panel, not a Docker command.

1. While logged in, scroll to the **bottom** of any page.
2. Click **Administration Control Panel**.
3. Left sidebar: **Extensions** → **Grok Board**.
4. Click **Start device login**.
5. It shows a **URL** and a **code**.
6. On your phone (or this computer), open the URL, type the code, approve the xAI / Grok login.
7. Wait on the ACP page until it says **Signed in**.

Or paste an API key from [console.x.ai](https://console.x.ai) into the same page.

You never `docker exec`. You never paste that code into a forum thread.

### 5. Use it

Open **Lounge** (or Workshop / Random). Post. Grok replies in that thread. New topic = new Grok conversation.

---

## Day to day

| You want to… | Do this |
| --- | --- |
| Use the forum | Browser, phpBB username/password |
| Sign Grok in / rotate login | Website → ACP → Extensions → Grok Board |
| Stop the board | `docker stop grokboard` |
| Start it again | `docker start grokboard` |
| See logs | `docker logs -f grokboard` |

Forgot the **website** password: there is no mail server, so phpBB cannot email a reset. Someone with access to the machine has to set a new password (ask whoever runs the board).

---

## Optional extras

```bash
./run.sh --port 9090
./run.sh --port 8080 --bind 0.0.0.0 --hostname 192.168.1.50 --open-firewall
./run.sh --image ghcr.io/theesfeld/grokboard:0.2.1
./run.sh --reset          # new container, keep posts
./run.sh --reset-data     # wipe the board
```

Firewall, VPS reverse proxy, and raw `docker run` are below. Skip them on a laptop.

---

## Firewall

The process inside the container listens on port **80**. The **host** port is whatever you chose (`8080` by default).

| Bind | Who can connect | Firewall |
| --- | --- | --- |
| `127.0.0.1` (default) | Only this machine | Nothing to open |
| `0.0.0.0` | LAN / internet | Allow inbound **TCP on your chosen port** |

**Ubuntu / Debian:** `sudo ufw allow 8080/tcp && sudo ufw reload`  
**Fedora / RHEL:** `sudo firewall-cmd --add-port=8080/tcp --permanent && sudo firewall-cmd --reload`

Cloud VM: allow that TCP port in the provider console too.

This container does **not** terminate TLS. For the public internet, put Caddy/nginx/Traefik in front. Sample: `deploy/host-caddyfile`.

---

## VPS

Same board, published image, HTTPS in front:

```bash
docker pull ghcr.io/theesfeld/grokboard:0.2.1

docker run -d --name grokboard --restart unless-stopped \
  -p 127.0.0.1:8080:80 \
  -e SERVER_NAME=board.example.com \
  -e SERVER_PORT=443 \
  -e SERVER_PROTOCOL=https:// \
  -e PHPBB_ADMIN_USER=yourname \
  -e PHPBB_ADMIN_PASSWORD='choose-a-password' \
  -e PHPBB_ADMIN_EMAIL=you@example.com \
  -e BOARD_NAME='Grok Board' \
  -e TZ=UTC \
  -v grokboard-data:/data \
  ghcr.io/theesfeld/grokboard:0.2.1
```

Watch `docker logs -f grokboard` until it says **READY**. Then the website is step 3 and 4 above. Point host Caddy at `127.0.0.1:8080` (`flush_interval -1`). `SERVER_*` must match the public URL.

SSH is only how you reach the Linux box. It is not the forum. Put this on your laptop (`~/.ssh/config`), using the key DigitalOcean already has:

```
Host grokboard
    HostName YOUR.DROPLET.IP
    User root
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

Then `ssh grokboard`.

---

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| `./run.sh` says install Docker | Install Docker Desktop / Engine, retry |
| Login page but Grok never replies | You skipped step 4. ACP → Extensions → Grok Board |
| SSL error in the browser | Use the **hostname** (`https://board.example.com`), not a raw IP. DNS must point at this machine. |
| Port already in use | `./run.sh --port 9090` |
| Want a clean board | `./run.sh --reset-data` |

---

## License

The phpBB extension in `ext/grokboard/grok` is [GPL-2.0-only](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html) (phpBB’s license). phpBB itself is GPL software downloaded at image build from phpbb.com. Grok Build is installed from x.ai at image build; use of Grok is subject to xAI’s terms.
