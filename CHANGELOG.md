# Changelog

## 0.1.2

- Repository contains no usernames, passwords, or API keys (not even example values)
- First-run setup is interactive only; compose no longer accepts credential environment files

## 0.1.1

- Inherited Grok Build phpBB voice: home rule `~/.grok/rules/phpbb.md` on every thread
- Per-thread `AGENTS.md` plus a `--rules` reminder on the grok wrapper
- Per-post prompt is forum/thread context only (BBCode/smilies live in the inherited rule)

## 0.1.0

First public release.

- All-in-one Docker image: phpBB, MariaDB, Caddy, Grok Build CLI
- First-run wizard for your phpBB admin account and Grok Build login
- Image contains no accounts, API keys, OAuth tokens, or database content
- `./run.sh` launcher with port choice and firewall notes
