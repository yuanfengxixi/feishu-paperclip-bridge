# Pitfalls

Every one of these cost me real hours. Read in order; later items assume earlier context.

## 1. Feishu API EOF behind Clash overseas proxy

**Symptom:** `cc-connect` logs `Get "https://open.feishu.cn/...": EOF` on every poll.

**Cause:** `HTTPS_PROXY=http://127.0.0.1:7890` (Clash) was set in the cc-connect environment. Clash routes the request through a HK/SG/JP node. Feishu's open platform refuses traffic from non-Chinese IPs for some endpoints, dropping the TLS connection mid-handshake.

**Fix:** `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy` immediately before launching `cc-connect`. See `start-all.sh`.

## 2. Clash TUN mode still grabs traffic even after unsetting env vars

**Symptom:** unset proxy + restart cc-connect → still EOF.

**Cause:** Clash's TUN mode operates at the kernel network layer, not via HTTP_PROXY env vars. Unsetting env vars only stops *direct HTTP proxy calls*; TUN sniffs every packet regardless.

**Fix:** add **static routes** that send Feishu CIDRs through the real adapter, bypassing the TUN device. See `wsl/feishu-routes.sh` (Linux side) and `windows/add-feishu-routes.ps1` (Windows side). Resolve current Feishu IPs via your LAN gateway DNS (not Clash's DNS), then route those /24s via `192.168.0.1 dev eth0` (or your equivalent).

## 3. fake-IP DNS mode makes GEOIP rules useless

**Symptom:** Clash config has `GEOIP,CN,DIRECT` as fallback, expecting Chinese sites to auto-route DIRECT. Doesn't work — Chinese sites still get pushed to overseas proxy.

**Cause:** under `dns.enhanced-mode: fake-ip`, every domain resolves to a `28.0.0.x` fake address at DNS time. When `GEOIP,CN` rule is evaluated, the IP is `28.0.0.x` — not in the CN geoip database — so the rule misses, falls through to `MATCH`.

**Fix options:**
- Explicit `DOMAIN-SUFFIX,xxx.com,DIRECT` for every CN site you care about (whack-a-mole, but reliable).
- Use `GEOSITE,CN,DIRECT` instead of `GEOIP,CN` (matches at the domain layer, before fake-IP resolves) — requires a Clash variant with geosite support and the database file present.
- Switch DNS mode to `redir-host` so DNS returns real IPs (slight latency hit, but `GEOIP` works correctly).

## 4. /etc/hosts gets wiped on every WSL boot

**Symptom:** Added Feishu IP pins to `/etc/hosts`, worked perfectly. Restarted WSL. Pins gone.

**Cause:** WSL2 regenerates `/etc/hosts` on every boot from a small built-in template.

**Fix:** `/etc/wsl.conf` → `[network] generateHosts = false`. Requires `wsl --shutdown` (from Windows PowerShell) to take effect.

## 5. Static routes don't persist on Windows reboot

**Symptom:** Added `route add` via cmd, worked. Restarted Windows. Routes gone.

**Cause:** `route add` without `-p` is volatile. PowerShell's `New-NetRoute` requires `-PolicyStore PersistentStore` for persistence (default is `ActiveStore` = volatile).

**Fix:** the script writes to **both** `PersistentStore` (survives reboot) AND `ActiveStore` (takes effect immediately without reboot).

## 6. PowerShell New-NetRoute denied (no UAC)

**Symptom:** Running `add-feishu-routes.ps1` from a normal PowerShell → "拒绝访问" / Access Denied.

**Cause:** `New-NetRoute` is a system-level operation. Standard user PowerShell can't do it.

**Fix:** launch elevated via `Start-Process powershell -Verb RunAs -ArgumentList '-File','C:\path\script.ps1'`. Triggers a UAC prompt; user clicks "是" once. Or right-click the .ps1 → "Run as administrator".

## 7. claude CLI blocked from Chinese IPs

**Symptom:** Removed proxy from cc-connect to fix Feishu (pitfall 1), now `claude` (called by cc-connect) returns `403 Request not allowed` from the Anthropic API.

**Cause:** Anthropic API geo-blocks Chinese direct IPs.

**Fix:** wrap `claude` in a shim that re-adds `HTTPS_PROXY` only for the `claude` subprocess. See `wsl/claude-wrapper`. Install at `~/.local/bin/claude` (chmod +x), ensure `~/.local/bin` precedes the real claude path on `$PATH`.

## 8. cc-connect --resume locks model

**Symptom:** Edited `ANTHROPIC_MODEL=claude-sonnet-4-6`, restarted cc-connect. Bot still uses Opus.

**Cause:** cc-connect persists per-thread session info at `~/.cc-connect/sessions/<project>_<hash>.json`. When resuming, it pins the original `agent_session_id` which is bound to the old model.

**Fix:** delete `agent_session_id` (or the whole sessions file) for the affected project. The next message starts a fresh session with the new model.

## 9. WSL restart kills everything in tmux

**Symptom:** Came back next day, paperclip / cc-connect / paperclip-mcp all dead. `tmux ls` shows no sessions.

**Cause:** WSL2 shuts down its VM aggressively when idle. tmux sessions don't survive.

**Fix:** make `start-all.sh` idempotent (skip-if-running pattern), then either (a) run it manually each day, (b) add to your Windows Task Scheduler to fire on WSL startup, or (c) use `wsl --exec bash ~/start-all.sh` from a Windows startup script. This repo's `start-all.sh` is idempotent.

## 10. apt-get stuck behind Clash TUN

**Symptom:** `sudo apt-get update` hangs for 10 minutes, no download progress.

**Cause:** apt's HTTP method goes through TUN → forwarded to overseas Clash node → ubuntu mirrors are slow/rate-limited from that path.

**Fix:** explicitly pass HTTP proxy to apt: `sudo http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890 apt-get -o Acquire::http::Proxy=http://127.0.0.1:7890 -o Acquire::https::Proxy=http://127.0.0.1:7890 update`. Going through Clash's HTTP proxy mode (not TUN) is more reliable.

## 11. Windows and Linux are *separate* claude logins

**Symptom:** Logged in `claude` on Windows. WSL still asks for OAuth login.

**Cause:** `claude` stores credentials per-OS-user-home. `C:\Users\X\.claude\credentials.json` is invisible to WSL's `/home/x/.claude/`.

**Fix:** log in once on each side. Or symlink — but symlinks across the WSL/Windows boundary are fragile; just log in twice.
