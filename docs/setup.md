# Fresh setup walkthrough

This assumes Windows 11 + WSL2 Ubuntu 22.04 + Clash Verge or FlClash with TUN mode, behind a Chinese network. Adjust paths/usernames to your machine.

## Prerequisites

| | Where | How |
|---|---|---|
| WSL2 + Ubuntu 22.04 | Windows | `wsl --install -d Ubuntu-22.04` |
| Node 20.x via nvm | WSL | `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh \| bash` then `nvm install 20` |
| pnpm | WSL | `npm i -g pnpm` |
| Python 3.10+ | WSL | comes with 22.04 |
| tmux | WSL | `sudo apt install tmux` |
| Clash/FlClash | Windows | install + set TUN mode |
| Feishu开放平台 bot | Web | create at open.feishu.cn → 应用管理 → 创建应用 |

## Step 1 — install Paperclip + paperclip-mcp + cc-connect

```bash
mkdir -p ~/work && cd ~/work
git clone https://github.com/paperclipai/paperclip.git
git clone https://github.com/paperclipai/paperclip-mcp.git
cd paperclip && pnpm install
cd ../paperclip-mcp && python3 -m venv venv && source venv/bin/activate && pip install -e .
npm i -g cc-connect
```

## Step 2 — create the Feishu bot

1. Go to **open.feishu.cn → 应用管理 → 创建企业自建应用**
2. Bot tab → 开启机器人
3. Permissions tab → add scopes: `im:message`, `im:message:send_as_bot`, `im:resource`, `im:message.group_at_msg`
4. **凭证与基础信息** tab → copy `App ID` and `App Secret`
5. Add the bot to a Feishu group (or @-mention in a 1-1)

## Step 3 — drop config files into place

```bash
# Linux side
mkdir -p ~/.cc-connect ~/.local/bin
cp wsl/cc-connect.config.toml.example ~/.cc-connect/config.toml
cp wsl/claude-wrapper ~/.local/bin/claude
chmod +x ~/.local/bin/claude
cp wsl/start-all.sh ~/start-all.sh
chmod +x ~/start-all.sh

sudo cp wsl/feishu-routes.sh /usr/local/sbin/feishu-routes.sh
sudo chmod +x /usr/local/sbin/feishu-routes.sh
sudo cp wsl/wsl.conf /etc/wsl.conf
# Edit /etc/wsl.conf — set [user] default to your username
# Edit ~/.cc-connect/config.toml — fill in app_id / app_secret / work_dir
# Edit ~/start-all.sh — set PAPERCLIP_AGENT_JWT_SECRET (or read from env file)
```

## Step 4 — verify the routes work

```bash
# Re-resolve Feishu IPs (in case they've shifted since this repo was written)
nslookup open.feishu.cn 192.168.0.1
nslookup msg-frontier.feishu.cn 192.168.0.1
nslookup open-callback-ws.feishu.cn 192.168.0.1
nslookup lark-msg-frontier.feishu.cn 192.168.0.1

# Update the CIDRs in feishu-routes.sh if needed (cover all IPs returned above)

# Restart WSL from Windows PowerShell so /etc/wsl.conf takes effect
# (Windows side): wsl --shutdown
# then re-open WSL

# Verify routes installed
ip route | grep -E '111.1.166|112.13|223.95|39.173'
# Should show each via 192.168.0.1 dev eth0

# Verify Feishu is reachable
curl -s -o /dev/null -w '%{http_code}\n' https://open.feishu.cn
# Should return 200 (or 403, but NOT 000/EOF)
```

## Step 5 — generate paperclip JWT secret + start

```bash
echo "export PAPERCLIP_AGENT_JWT_SECRET=$(openssl rand -hex 32)" >> ~/.paperclip.env
echo 'source ~/.paperclip.env' >> ~/.bashrc
source ~/.paperclip.env

~/start-all.sh
# tmux ls should show: paperclip, paperclip-mcp, cc-connect
# Wait ~30s for paperclip pnpm dev to compile, then check:
curl -s --noproxy '*' http://127.0.0.1:3100/api/companies | head -c 200
# Should return JSON
```

## Step 6 — create a paperclip company + CEO agent

Open `http://127.0.0.1:3100` in your browser. Walk through the onboarding to create a company and a CEO agent. The CEO agent's `adapterType` should be `claude_local`, with a `cwd` pointing at a real directory.

## Step 7 — smoke test the bridge

In Feishu, message the bot: `你好`

Within ~5s you should see a Feishu card showing the bot's reply, sourced from the CEO agent. Check `~/cc-connect.log` if it doesn't respond — the message poll cycle should appear in the log.

## Step 8 (optional) — Windows side for additional bots

```powershell
# In Windows PowerShell as Administrator
New-Item -ItemType Directory C:\Users\$env:USERNAME\.cc-connect -Force
Copy-Item windows\cc-connect.config.toml.example C:\Users\$env:USERNAME\.cc-connect\config.toml
# Edit that file — fill in your bot credentials

# Run routes (one-time, persists)
Start-Process powershell -Verb RunAs -ArgumentList '-File', "$PWD\windows\add-feishu-routes.ps1"

# Start cc-connect (you'll want to add this to startup folder)
cc-connect --config "$env:USERPROFILE\.cc-connect\config.toml"
```

## Troubleshooting

When something breaks, read [pitfalls.md](pitfalls.md) — it lists 11 known traps with the actual error message each one produces. Match the error → find the fix.
