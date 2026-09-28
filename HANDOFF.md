# Handoff (2026-09-28)

Picking this up on another machine. Read this first, then `PLAN.md` (its "Status" and "Next up" sections are current; the rest is design history).

## What this is

An always-on personal Hermes agent, packaged as a Docker Sandbox Kit v3, running in a Docker cloud sandbox (Agentic Platform).

- **Base:** DHI `sbx-templates:shell`, arm64 only.
- **Transport:** Signal, as a linked device on your own number. Only Note to Self reaches it.
- **Reach:** reads mail and drafts replies, never sends. Pushes to GitHub.
- **Skills:** writing, brainstorming, coding and analysis, ported from pix.
- **Memory:** separate from pix.

## Where things are

| Thing | Location | State |
|---|---|---|
| Repo | github.com/mcavage/hermes-kit | public, `main` |
| Base image | `docker.io/mcavage/hermes-base:0.1.0` | pushed, public. Hermes `main@ca16be5` (the `v2026.9.24` tag caps Python <3.14), signal-cli 0.14.8 native, libsignal 0.102.1 built from source |
| Kit | `docker.io/mcavage/hermes-kit:0.1.2` | pushed, public, v3 descriptor accepted by `sandbox-kit 3.0.0-m.6` |
| Cloud secrets | `sbx --cloud secret ls` | anthropic, openai, google set. **github and fastmail missing** |
| Cloud sandbox | none | `make up` has never run |

## Verified vs not

- **Verified locally:**
  - The base image runs `hermes`, `signal-cli` and Python 3.14.7.
  - `hk-boot` is idempotent, and the gateway runs supervised.
  - Skills load from `/opt/hermes-kit/skills`.
  - It boots with no network.
- **Verified in cloud:**
  - A sandbox with `--on-timeout restart` keeps its disk across the timer restart (marker test).
  - The server **refuses** restart + volume ("not supported ... yet").
  - Your earlier Hermes + Signal setup worked in a cloud sandbox, so signal-cli gets through the cloud proxy.
- **Not verified:**
  - Proxy/CA env var names in the startup hook's `env:` list.
  - That Hermes accepts the proxy's sentinel `ANTHROPIC_API_KEY`.
  - That the Fastmail token is injected on `api.fastmail.com`.
  - The own-number acceptance test (a stranger DMs you and gets nothing back).

## Gotchas

- **sbx bug:** after `--on-timeout restart`, `sbx --cloud exec/cp/inspect` fail with `unknown on_timeout 4` (nightly 55b8dd3 and v0.46.0-rc5). Until it's fixed, run `link`/`doctor`/`logs` from the Console web terminal. `make upgrade` is blocked.
- **No automatic session reset on the gateway.** Send `/new` in Note to Self at natural boundaries so memory refreshes.
- **Rebuilding the base** needs `docker login dhi.io`, takes about 8 minutes (Rust + GraalVM), and needs an arm64 host.
- **Hermes SQLite:** Debian's 3.46.1 has the WAL bug, so Hermes uses `journal_mode=DELETE`. That's safe, just slower.

## Decided, not built (in order)

These are the prompt-injection hardening items; the full design is in `PLAN.md` under "Next up".

1. **Kernel probe** on a throwaway cloud shell sandbox: `uname -r`, `/sys/kernel/security/lsm`, `iptables -m owner` from a root hook, `unshare -n`. This decides the network wall: iptables by user in one sandbox, or a separate quarantine sandbox. Docker-in-sandbox would be the clean answer, but cloud Docker support is in progress.
2. **Signal send filter:**
   - signal-cli runs as a `signal` user on a Unix socket.
   - The filter allows only `send` to your own number, plus the read calls.
   - Typing, reactions and everything else are denied.
3. **Separate users** (`agent`/`quarantine`/`signal`), **no sudo** for `agent`.
4. **Deterministic guards:**
   - A `pre_tool_call` hook blocks force-push, pushes to default branches and repo/API deletes.
   - `skills.write_approval: true`.
   - Branch protection on `main` (a GitHub setting).
5. **Quarantine service** (HTTP, `quarantine` user):
   - Deterministic fetch, then a no-tool model answering with capped output. Optional Jev screen.
   - Remove Hermes's native web and mail-read tools from the main agent.

## Open decisions

- **Memory:** built-in only (current), your own pix-memory instance in the sandbox, or Hindsight local-embedded (restricted to user turns).
- **Work instance uses Google Workspace via gog, not Fastmail.** That isn't a config swap:
  - In pix, gog ran **host-side** as a stdio MCP server. Cloud sandboxes have no host, and `sbx --cloud mcp add` is unsupported.
  - Running gog inside the sandbox puts a Google refresh token on disk, where a turned agent can exfiltrate it. Proxy-injected keys don't have that problem.
  - Options to evaluate:
    - a Google Workspace remote MCP server connected through the Console MCP page;
    - Google OAuth via `credential@1` `oauth` (proxy-managed refresh);
    - gog in the sandbox as the `quarantine` user, accepting the token-on-disk risk.
  - Design direction: make the mail provider pluggable in the quarantine service (`fastmail` | `gworkspace`), selected by a kit arg, so the same kit serves home and work.

## First commands on a new machine

```sh
git clone https://github.com/mcavage/hermes-kit && cd hermes-kit
sbx --cloud secret ls          # check what's set
docker login dhi.io            # only if rebuilding images/base
```
