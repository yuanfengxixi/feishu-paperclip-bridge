# feishu-paperclip-bridge

**Bridge Feishu (Lark) bots to a self-hosted [Paperclip](https://paperclip.ing) agent company via [cc-connect](https://github.com/JimLiu/cc-connect).**

End result: you `@` a bot in Feishu, a Claude-powered AI agent (CEO / engineer / designer / QA / whatever) wakes up, does the work, and replies back in the Feishu thread.

Tested on Windows 11 + WSL2 Ubuntu 22.04, behind a Chinese network with Clash/FlClash for overseas access.

## What's in this repo

```
feishu-paperclip-bridge/
├── wsl/                       # Linux/WSL side: paperclip + cc-connect launcher,
│                              # static routes, hosts pinning, claude proxy wrapper
├── windows/                   # Windows side: multi-bot cc-connect config,
│                              # persistent route script
└── docs/
    ├── architecture.md        # how the pieces fit together
    ├── pitfalls.md            # every trap I hit (read this first)
    └── setup.md               # fresh-install walkthrough
```

## Quick map

| Layer | Where | What |
|---|---|---|
| Feishu bot(s) | open.feishu.cn | The 用户-facing chat surface — one bot per "project" |
| cc-connect | WSL + Windows | Bridges Feishu webhooks ↔ headless `claude` CLI |
| Paperclip | WSL (Node + Postgres) | Multi-agent control plane (CEO + subordinates, issues, budget) |
| Claude Code | Per agent | The actual LLM execution, called via headless `claude --print` |

See **[docs/architecture.md](docs/architecture.md)** for the full picture.

## Why this exists

Two pain points solved:

1. **Feishu webhooks don't survive Chinese proxy chains.** If your dev box runs Clash/FlClash with TUN mode + fake-IP, Feishu API calls get routed overseas, time out, EOF. This repo's combination of `/etc/hosts` pinning + static routes via the real adapter fixes it permanently.
2. **Anthropic API is geo-blocked from China direct IPs, but cc-connect → Feishu is geo-blocked from overseas proxies.** Same `claude` binary needs `HTTPS_PROXY` set, but its parent (cc-connect) needs proxy *unset*. Solution: a per-process wrapper at `~/.local/bin/claude`.

The hard parts are in [docs/pitfalls.md](docs/pitfalls.md).

## Status

- WSL side: working, drives a 5-agent paperclip "company" (CEO + ArtDirector + FoundingEngineer + QA + Xiaohongshu Content Producer) for a game-dev studio
- Windows side: working, drives 3 separate Feishu bots (`default` / `knowledge-base` / `design-orders`) pointing at codex-style work directories
- Network plumbing: static routes persist across WSL restarts via `/etc/wsl.conf`'s boot command; Windows routes via `New-NetRoute -PolicyStore PersistentStore`

## License

MIT. Take what's useful.
