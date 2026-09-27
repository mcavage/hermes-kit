# hermes-kit: plan (rev 2)

A personal Hermes Agent, packaged as a Sandbox Kit v3 on DHI, running in Docker Agentic Platform (cloud sandboxes). You reach it over Signal from your own number, in Note to Self. It reads Fastmail and writes drafts but can't send, has push rights on GitHub, and keeps its own memory.

pix is the coding agent you sit in front of. This is the one that runs while you don't. We reuse pix's plumbing ideas (kit, egress, secrets posture, voice) but not its host-side pieces, because in the cloud there is no host.

## What changed from rev 1

| Rev 1 | Rev 2 | Why |
|---|---|---|
| sbx on the laptop | `sbx --cloud` (Agentic Platform) | Your call. |
| `op://` refs resolved at launch | Docker cloud secrets (`sbx --cloud secret`) | Your call. Nothing resolves on a laptop. |
| Dedicated Signal number | Linked device on your number, Note to Self only | Your call. Needs hardening (below). |
| Shared pix-memory over the gateway | Hermes built-in memory only | Your call. Also, host MCP doesn't exist in cloud. |
| gog / Gmail, Ollama on host | Fastmail official MCP; no Ollama | No host. You mostly use Fastmail. |
| `long-running@1`, one sandbox forever | `--on-timeout restart` at the 24h boundary | Cloud has a 24h lifecycle; restart carries the sandbox across it. |

## Platform facts that shape the design (2026-09-26)

**Lifetime**
- 24h lifecycle. Sandboxes **restart on the 24h boundary**: stop, then start immediately, with disk and state carried over.
- Cloud sandboxes don't stop when you disconnect.
- `long-running@1` isn't in the sbx 0.45.1 binary. Declare it `optional: true`, or a required entry gets the kit refused.
- **No volume.** The server refuses one today: `onTimeout 'restart' is not supported for a sandbox with a volume (it cannot be faithfully resumed yet)` (tested 2026-09-26). State lives on the sandbox disk across restarts, and `make upgrade` carries it to a new sandbox.
- **CLI bug:** creating with `--on-timeout restart` succeeds server-side, but every inspect/exec afterwards fails with `unknown on_timeout 4 (4)`. Seen on nightly 55b8dd3 and v0.46.0-rc5. Needs a CLI fix before we can operate the sandbox from the CLI.

**Secrets**
- `sbx --cloud secret` has account or per-sandbox scope, and is **a separate store from the Console's Secrets page**. We use the CLI store.
- Built-ins: anthropic, openai, google, github, xai, and others.
- Anything else is `set-custom --host H --env VAR`, which injects `Authorization: Bearer` on **every** request to H.
- Whether a kit's `credential@1` can declare an arbitrary new service in cloud is undocumented, so we use custom secrets for those.
- Plain values like `SIGNAL_ACCOUNT` go in via `-e`.

**MCP**
- `sbx --cloud mcp add` is unsupported.
- Remote servers are connected in the Console, with OAuth done there, then attached with `sbx --cloud mcp load` or `--static-mcp`.
- Only remote-URL servers work. No stdio.

**Network**
- Kit `network-policy@1` works. `@2` (method/path rules) is refused.
- Whether cloud TLS-intercepts hosts that have no credential injection is undocumented. That matters for Signal.

**Kit publishing**
- The 64 MiB registry cap applies to the kit's own layers, **not its base image**. The heavy parts (Python, Hermes, signal-cli) go in a base image we build and push separately; the kit layer is config, persona and skills.
- It must be pushed to a registry. Uploaded/imported kit images don't get kit credentials routed.
- Console launch needs a public kit; the CLI can launch private ones.

**Curated Hermes kit**
- Docker already ships one in the Console catalog. I couldn't find its Hub reference from the CLI.

**Hermes**
- Python 3.14, and it talks to signal-cli's native `daemon --http`.
- Own-number mode: other DMs you send are dropped. Your group posts count as inbound. Typing indicators and 👀 reactions can fire for strangers before the auth check.

**signal-cli**
- Open source (GPL-3.0, AsamK/signal-cli), so **we build it ourselves**.
- **arm64 only** (your call). The upstream native binary (v0.14.8) is amd64-only, so we build from source: GraalVM `nativeCompile`, plus libsignal-client's JNI lib built from Rust source for aarch64.
- It pins Signal's private CAs (`whisper.store`), but **Hermes + signal-cli has already run in a cloud sandbox** (your earlier setup), so the cloud proxy doesn't break it. No trust-store patch needed.
- It ignores `HTTPS_PROXY`, so it most likely takes the sandbox's transparent path, which locally does not terminate TLS.

**Fastmail**
- Official hosted MCP at `api.fastmail.com/mcp`, with OAuth consent levels Read / Make changes / Send.
- **Read + Make changes, no Send** gives read + drafts, enforced server-side. It also covers calendars and contacts.
- Caveat: "Make changes" also allows move and delete.
- **Docker's MCP gateway can't connect to it today.** `sbx mcp add fastmail --url https://api.fastmail.com/mcp` fails client registration: `DCR: registration endpoint returned status 400 ... too many dynamically registered clients`. The Console fails too (2026-09-26). Codex's OAuth flow against the same server works.
- **So we skip the gateway for Fastmail.** Use a Fastmail API token with MCP scopes Read data + Make changes (no Send email) as a cloud custom secret on `api.fastmail.com`. Hermes connects to `https://api.fastmail.com/mcp` directly through its own `mcp_servers`, and the cloud proxy injects the Bearer header. There's no OAuth, no refresh, and no dependency on the gateway.

## Architecture

```
You (phone, Note to Self)
      |
  Signal servers
      |  egress: chat/storage/cdn*/cdsi.signal.org, not intercepted (spike 1)
+-----v------------- cloud sandbox, linux/arm64, micro or small ------+
|  signal-cli daemon --http 127.0.0.1:8080   (startup hook, background)   |
|        ^ SSE / JSON-RPC                                                  |
|  hermes gateway run                        (entrypoint)                  |
|     terminal.backend: local   (the microVM is the boundary)             |
|     mcp: https://api.fastmail.com/mcp direct (token injected by proxy)  |
|     gh + git   (push, via github cloud secret)                          |
|  disk ~/state: ~/.hermes  ~/.local/share/signal-cli                    |
+-------------------------------------------------------------------------+
      |  cloud proxy injects: anthropic, openai, google, github, parallel, fastmail
```

## Keeping it alive

- Run with `--on-timeout restart`. The sandbox restarts at the 24h boundary, so there's no relay and no outside scheduler.
- **State stays on the sandbox disk** under `/home/agent/state`, with `~/.hermes` and `~/.local/share/signal-cli` symlinked into it. That keeps the migration a single directory.
- **`make upgrade`**, for when the kit changes:
  1. Create the new sandbox.
  2. Stop signal-cli and the gateway in the old one.
  3. `sbx --cloud cp old:/home/agent/state` to a temp dir (mode 700), then into the new sandbox.
  4. Start the new sandbox, run `doctor`, and delete the old one. Then shred the temp dir.

  The Signal keys transit your laptop briefly during an upgrade. If `sbx --cloud cp` ever supports sandbox-to-sandbox copies, use that instead.
- When restart and volumes become compatible, move `state/` onto a volume and delete the copy step.
- **Processes restart with it.** The signal-cli daemon and the gateway both come back through `lifecycle.startup` and the entrypoint. The spec promises no supervisor, so `startup` launches a small wrapper that restarts signal-cli if it dies.
- **Clean shutdown before the boundary.** A Hermes cron at T-5min stops signal-cli gracefully, so its ratchet state is flushed before the VM stops. It's cheap insurance even though the disk persists.

## Signal on your own number: hardening

The bot is a linked device, so it sees everything you send and receive, and anything it sends goes out as you. The adapter needs these settings. All of them are required, and each is tested in phase 2.

```bash
SIGNAL_ACCOUNT=+1XXXXXXXXXX          # plain env via -e, not a secret
SIGNAL_ALLOWED_USERS=+1XXXXXXXXXX    # yourself only => only Note to Self gets through; strangers => "ignore"
# SIGNAL_GROUP_ALLOWED_USERS         # leave UNSET, or your group posts become prompts answered as you
SIGNAL_REACTIONS=false               # 👀 fires before the auth gate
# never set SIGNAL_ALLOW_ALL_USERS / GATEWAY_ALLOW_ALL_USERS
```

Also:
- Turn typing indicators off in `config.yaml`. Typing currently starts before auth, so it could leak "typing…" to a stranger's DM.
- Leave `--send-read-receipts` off.
- Acceptance test: from another account, DM your number and post in a shared group. Nothing may come back: no reply, no reaction, no typing indicator.
- Upstream: file a Hermes issue to move typing/reactions behind the auth gate (`gateway/platforms/base.py` ~4471).
- The signal-cli store holds your account keys. It lives only on the sandbox disk (and briefly in the upgrade temp dir), never in a template save or a repo.
- Your phone must come online at least once every 30 days or Signal unlinks the device.

## Secrets (Docker cloud secrets, account scope)

| What | Command | Seen in sandbox as |
|---|---|---|
| Anthropic | `sbx --cloud secret set anthropic` | sentinel `ANTHROPIC_API_KEY` |
| OpenAI (fallback / review) | `sbx --cloud secret set openai` | sentinel `OPENAI_API_KEY` |
| Google (vision, cheap aux) | `sbx --cloud secret set google` | sentinel `GEMINI_API_KEY` |
| GitHub (push) | `sbx --cloud secret set github` | sentinel `GH_TOKEN` |
| Parallel (web search) | `sbx --cloud secret set-custom --name parallel --host api.parallel.ai --env PARALLEL_API_KEY --header x-api-key` | sentinel |
| Fastmail | `sbx --cloud secret set-custom --name fastmail --host api.fastmail.com --env FASTMAIL_API_TOKEN` (default `Authorization: Bearer %s`). Token MCP scopes: Read data + Make changes, never Send | sentinel; Hermes `mcp_servers.fastmail.url: https://api.fastmail.com/mcp` |

- **GitHub token:** all-repos (your call). It reads untrusted email and has a shell, so the egress allowlist, the Signal allowlist and the approval hooks on force-push and branch deletion are what stand between a prompt injection and your repos.
- **Verify in spike 3:** does Hermes accept a sentinel `ANTHROPIC_API_KEY` from process env when there's no `.env` entry? It should, since env is in its precedence chain.

## Repo layout

```
hermes-kit/
  images/base/Dockerfile            # dhi.io/sbx-templates:shell + Hermes + signal-cli (from source); no size cap
  hermes.yaml / hermes.dockerfile   # workload kit: FROM hermes-base, adds config/context/skills + hooks
  context/SOUL.md                   # persona
  context/AGENTS.md                 # agent-context: invariants
  config/config.yaml                # seeded on first boot only
  skills/                           # ported from pix + new fastmail skills
  Makefile                          # build, push, secrets, up, link, logs, doctor
  docs/signal.md, docs/upstream.md
```

**Building signal-cli.** It's built in stages inside `images/base/Dockerfile`:
1. Build `libsignal_jni` from the pinned libsignal tag signal-cli expects, in a `dhi.io/rust:*-dev` stage.
2. Compile signal-cli with GraalVM `./gradlew nativeCompile` against that lib. DHI may not ship GraalVM; if not, the builder stage uses the upstream GraalVM image. Only the output binary lands in the kit, so the runtime layers stay DHI.
3. Copy the single binary into the base image's final stage.

Pin the signal-cli tag and libsignal version, and build for `linux/arm64` only. This also frees us from waiting on upstream releases.

**Two images.** `images/base/` is `FROM dhi.io/sbx-templates:shell`, which is DHI and already provides the sandbox floor: agent uid 1000, Python 3.14.7, uv, gh, git, rg and jq, with no Docker engine. On top go Hermes, pinned to `v2026.9.24`, and signal-cli `v0.14.8` built from source. It is pushed as `mcavage/hermes-base:<ver>`, and rebuilt only when a pin moves. The kit's `hermes.dockerfile` is `FROM mcavage/hermes-base:<ver>@sha256:...`, adding `config/`, `context/` and `skills/`. So iterating on persona or skills is a tiny push, well under the cap.

**One kit.** Signal's egress hosts and the signal-cli startup hook live in `hermes.yaml`, so there's no mixin. That means `sbx --cloud run` needs no `--kit`, and a public build could also launch from the Console.

**The curated Hermes kit.** Still worth a look for how it wires Hermes (Console > Kits > Hub link), but we don't depend on it.

## config.yaml

```yaml
model:
  provider: anthropic
  default: claude-opus-5-5
fallback_providers:
  - {provider: openai, model: gpt-6-astra}
auxiliary:
  compression:      {provider: anthropic, model: claude-haiku-4-5-20251001}
  title_generation: {provider: anthropic, model: claude-haiku-4-5-20251001}
  vision:           {provider: gemini, model: gemini-3.8-flash}
cron:
  model: claude-sonnet-5
terminal:
  backend: local
memory:
  memory_enabled: true
  user_profile_enabled: true
skills:
  auto_load: [writing-voice, anti-slop]
platform_toolsets:
  signal: [hermes-signal]
```

For the Fastmail MCP server, exclude destructive tools (delete, move-to-trash) if Hermes's MCP config supports per-tool filtering. Check `mcp-config-reference.md` in phase 3. If it doesn't, add a guard skill plus a Hermes approval hook on those tool names.

## Skills

| Keep | New / adapted | Drop (pix does these) |
|---|---|---|
| writing-voice, anti-slop, draft-email, analyze, challenge, one-pager, brainstorm, competitive, debug, verify, ingest, promote | **fastmail-triage** (summarize the inbox, flag what needs you), **fastmail-draft** (write a reply as a draft, never send, tell you the draft's subject). **weekly-wrap** now reads Fastmail calendar + gh and delivers to Signal. **guard** becomes Hermes approval hooks for delete/force-push. **signal-voice**: short replies, no tables, attach long output rather than paste. | pix-dev, environments, healthcheck, onboarding, conventions, ship, build, deliver, tdd, qa, design-review, repo-healthcheck, slide-deck, docs-*, gtm-launch, plan, gworkspace, capability-routing, peer-review |

Starter cron jobs, all `deliver: signal`, i.e. to your Note to Self:
- 07:30 weekdays: today's Fastmail calendar, plus mail that needs you.
- Fri 16:00: weekly-wrap.
- Hourly, silent unless non-empty: PRs waiting on your review.

## Phases

**Phase 0: spikes (throwaway, Shell kit in cloud). Each one can kill a part of the design.**
1. ~~**Signal through the cloud proxy.**~~ Done: your earlier Hermes + Signal setup ran in a cloud sandbox.
2. ~~**Restart on disk.**~~ Done: a marker file survived the timer restart (2026-09-26). Volume + restart is refused by the server, so state stays on disk. Still to test: `make upgrade` end to end without relinking.
3. **Hermes in cloud.** Start the curated Hermes kit, and confirm sentinel-key auth, Hermes reaching `api.fastmail.com/mcp` with the injected token (and `tools/list` showing no send tool), and `gh` push with the github secret.
4. **Build path.** Build a v3 hello kit on DHI with buildx, push it private, and launch with `sbx --cloud run`. The signal-cli arm64 source build is the long pole here.

**Phase 1: agent in the cloud.** `hermes.yaml`/`.dockerfile`, config seed, and `make up` (create with secrets, MCP, env). Talk to it with `sbx --cloud attach`.

**Phase 2: Signal.** Add the signal egress + startup hook to `hermes.yaml`. `make link` runs `sbx --cloud exec -it ... signal-cli link` and you scan the QR. Apply the hardening settings and pass the acceptance test (no leaks to strangers or groups). Survive one lifecycle rotation without relinking.

**Phase 3: make it yours.** SOUL.md, skills, Fastmail tool filtering, cron jobs. Add `make doctor`, which probes each model backend, the MCP gateway, gh auth and signal-cli health, and reports failures honestly.

**Phase 4: operate.** Write down upgrades: bump pins (Hermes, signal-cli, libsignal), push, then `make upgrade`. Back up with a periodic `sbx --cloud cp` of `state/`, encrypted at rest. Losing it means relinking Signal and losing Hermes memory. Also write down the recovery path, which is relinking, and a cost note. Press-reported pricing is micro $0.07/h ≈ $51/mo and small $0.14/h ≈ $102/mo if on 24/7; Hermes idles light, so start on micro.

## Open items

1. ~~**GitHub scope.**~~ All repos.
2. **Fastmail deletes.** Is it OK for "Make changes" to include move/delete until we confirm tool filtering, or do you want to start on Read only and add drafts after phase 3?

## Risks

- **Everything here is experimental** (Agentic Platform, kit v3). Pin the frontend `docker/sandbox-kit:3.0.0-m.3` and sbx versions, and keep `docs/upstream.md` current.
- **Own-number blast radius.** The bot reads all your Signal traffic and speaks as you. Hardening plus the acceptance test are gates, not nice-to-haves.
- **Prompt injection via email → shell with push rights.** Contained by the scoped PAT, the egress allowlist, and approval hooks on destructive git ops.
- **No volume yet.** State is only as durable as the sandbox disk. If the sandbox is lost, you relink Signal and Hermes starts from the last backup.
- **The CLI can't operate restart sandboxes** until `unknown on_timeout 4` is fixed. File it against sbx-releases.
