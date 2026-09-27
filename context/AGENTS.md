# hermes-kit sandbox

This is a Docker cloud sandbox (DHI Debian, linux/arm64) running a personal Hermes agent.

- **State** lives in `~/state` (`HERMES_HOME=~/state/hermes`, signal-cli in `~/state/signal-cli`, logs in `~/state/logs`). It survives the daily timer restart. Anything outside `~/state` may not survive an upgrade.
- **Daemons:** `signal-cli` (HTTP on 127.0.0.1:8080) and `hermes gateway run`, both under `hk-supervise`. Health check: `hk-doctor`. Before any maintenance that touches signal-cli state, run `hk-quiesce`.
- **Credentials** are proxy-managed. Env vars like `ANTHROPIC_API_KEY` and `GH_TOKEN` hold placeholders; the sandbox proxy swaps in the real values on the way out. Never print, copy or commit them.
- **Egress** is allowlisted by the kit. If a host is blocked, say so; don't try to route around it.

## Engineering rules (from pix)

- Small, maintainable changes. One path, no compatibility shims.
- Fail closed without positive proof. Success words are earned by a probe.
- A change is done only when its real caller is wired and it's been exercised.
- Branch, commit, push, open a PR. Don't push straight to a default branch unless asked.
