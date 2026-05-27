# Architecture

## The data flow, end to end

```
┌─────────────────┐                    ┌──────────────────┐
│  Human in       │   @ mentions       │   Feishu open    │
│  Feishu chat    │ ─────────────────► │   platform       │
└─────────────────┘                    │  open.feishu.cn  │
                                       └────────┬─────────┘
                                                │ webhook
                                                ▼
                                    ┌───────────────────────┐
                                    │  cc-connect           │
                                    │  (Node, on WSL OR     │
                                    │   Windows, polling +  │
                                    │   long-poll mode)     │
                                    └───────────┬───────────┘
                                                │ spawns headless
                                                ▼
                                    ┌───────────────────────┐
                                    │  claude (the wrapper) │
                                    │  → injects HTTPS_PROXY│
                                    │  → exec real claude   │
                                    └───────────┬───────────┘
                                                │ HTTPS via Clash
                                                ▼
                                    ┌───────────────────────┐
                                    │  api.anthropic.com    │
                                    └───────────────────────┘

If claude is acting as a Paperclip agent, it also talks to:

claude  ─►  Paperclip HTTP API (localhost:3100)
        │     - checks inbox
        │     - claims issue (checkout)
        │     - updates status, comments
        │     - delegates to subordinates
        ▼
   Paperclip server (pnpm dev on WSL)
     ├── stores issues, agents, runs, budgets in embedded Postgres (:54329)
     ├── exposes Web UI at :3100
     └── routes wake-events back to claude via PAPERCLIP_* env vars
```

## Why two execution sites (WSL + Windows)

| | WSL | Windows |
|---|---|---|
| Paperclip server | ✅ runs here | ❌ |
| cc-connect | ✅ for the "main" Feishu bot tied to Paperclip's CEO | ✅ for 3 separate Feishu bots that don't need Paperclip |
| Why split | Paperclip + Postgres + Node monorepo are happier on Linux | Bot work directories live on `D:\` Windows partition (boss's docs/work) |

The two sides are **completely independent** — different `~/.cc-connect/config.toml`, different Feishu apps, different work directories. If one dies, the other keeps running.

## The cc-connect ↔ claude contract

cc-connect spawns `claude --print --output-format=stream-json` per message and feeds it the Feishu thread context. claude's stdout (newline-delimited JSON) streams back into the Feishu thread as a card.

This means:
- **Every Feishu message = a fresh claude process**. State persists only through:
  - Paperclip's database (for paperclip-aware agents)
  - The `--resume <session-id>` flag (for short-lived continuation)
  - Files on disk in the agent's `work_dir`
- claude must be **headless-friendly**: no interactive permission prompts (`--dangerously-skip-permissions` or cc-connect's `mode = "bypassPermissions"`)
- Model selection: cc-connect picks based on `model = ` in config.toml OR `ANTHROPIC_MODEL` env var on the cc-connect process

## Paperclip agent topology

A Paperclip "company" is one Postgres database holding:
- 1 `companies` row (e.g. `小狗工作室`)
- N `agents` rows, each with a `reportsTo` foreign key — forms a tree:

```
CEO (root, reportsTo = NULL)
├── ArtDirector (designer)
├── FoundingEngineer (engineer)
├── QA (qa)
└── 小红书助手 (cmo)
```

Only the CEO is connected to Feishu (one bot, one `cc-connect` project). When you `@CEO`:
1. cc-connect wakes the CEO's `claude` process with the message
2. CEO reads its `AGENTS.md` instructions (says: delegate, don't IC)
3. CEO calls Paperclip HTTP API to create a child issue, assigning to e.g. FoundingEngineer
4. Subordinates run via **heartbeat** — Paperclip wakes them by spawning their `claude` adapter in a separate process, with `PAPERCLIP_AGENT_ID` + `PAPERCLIP_API_KEY` env vars injected
5. Results bubble back up via issue comments → CEO sees them next heartbeat → CEO summarizes in Feishu

This means **subordinates never touch Feishu directly**. They speak Paperclip API, the CEO is the translator.

## Network plumbing (the painful part)

The host's outbound network on a typical China dev box:

```
WSL apps ──► WSL eth0 ──► (DNS via 10.255.255.254 → Windows DNS)
                              │
                          ┌───┴────────────────────────┐
                          │                            │
                          ▼                            ▼
                  FlClash TUN adapter           Real WLAN adapter
                  (fake-IP, all traffic         (only if static
                   intercepted)                  routes redirect)
                          │
                          ▼
                  Clash rule engine ──► overseas proxy node
                                         OR (rare) DIRECT
```

**Two failure modes:**

1. **Feishu API calls** (open.feishu.cn, msg-frontier.feishu.cn, …) sent through overseas proxy → Feishu refuses (sees foreign IP for what it thinks is a domestic-only endpoint) → EOF / ERR_CONNECTION_CLOSED.
   - Fix: static routes (`feishu-routes.sh` / `add-feishu-routes.ps1`) push these CIDRs to the real adapter, skipping Clash entirely.
   - Belt: `/etc/hosts` + Windows `hosts` pin the hostnames to known IPs, so even if Clash's DNS layer intercepts, the resolved IP is correct and routes via the static rules.

2. **Anthropic API** (api.anthropic.com) called *without* proxy from a Chinese IP → blocked.
   - Fix: `claude-wrapper` re-injects `HTTPS_PROXY=Clash` only for the `claude` subprocess. cc-connect's parent process still has proxy unset (so Feishu side keeps working).

See [pitfalls.md](pitfalls.md) for the war stories.
