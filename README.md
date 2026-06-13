# load-test — a Claude Code skill

Run multi-user **LOAD** and **STRESS** tests against a web page, user journey, or API endpoint — then get latency percentiles (p50/p90/p99), throughput, error rate, and a clear **PASS/FAIL** verdict. Complementary to single-user performance timing: this answers *"how does it hold up when many users hit it at once, and where does it break?"*

It can also run an optional **exploratory tour** first — walk a named journey once in a real browser (via the Playwright MCP), confirm the steps, and harvest the real endpoints + auth token so the load test hits exactly what the journey calls instead of a guessed URL.

## What's inside

```
load-test/
├── SKILL.md                      # the skill (orientation → intake → run → verdict → report)
├── scripts/run_load.sh           # auto-detects k6 / autocannon / ab / hey, normalizes output to JSON
└── references/
    ├── tools.md                  # tool capability matrix + install commands
    └── exploratory-tour.md       # how to walk a journey and harvest its endpoints
```

## Install

Skills live in `~/.claude/skills/` (available in **every** project on your machine) or in a project's `.claude/skills/` (that project only, shared with the team via git).

**Quick install (personal, all projects):**

```bash
git clone https://github.com/<your-username>/load-test-skill.git
cp -R load-test-skill/load-test ~/.claude/skills/
```

**Or use the helper:**

```bash
git clone https://github.com/<your-username>/load-test-skill.git
cd load-test-skill && ./install.sh            # installs to ~/.claude/skills/
./install.sh /path/to/project/.claude/skills  # or into a specific project
```

Re-open Claude Code afterward so it picks up the new skill.

## Use

Type **`/load-test`** in Claude Code, or just describe the task and it triggers automatically:

> "load test this endpoint with 50 users" · "stress test the login API until it breaks" · "how many concurrent users can the dashboard handle?" · "soak test this for 15 minutes"

The skill walks you through it: it explains how it works, asks which journey/target and how many concurrent users, optionally runs the exploratory tour, fires the test, and reports a verdict. Ask for a **non-technical HTML report** and it produces a traffic-light, plain-language summary.

## Requirements

- A simple URL/API load test runs immediately if **Node/npx** is present (uses `npx autocannon`, no install) or **ApacheBench** (`ab`) is installed.
- **Stress/spike/soak ramps** and **multi-step journey replay** need **k6** (`brew install k6`).
- The exploratory tour needs browser automation (the Playwright MCP tools).

See [`load-test/references/tools.md`](load-test/references/tools.md) for the full tool matrix.

## Authorization

Load testing is indistinguishable from a denial-of-service attack from the server's side. Only run it against targets you are explicitly authorized to hit — your own dev/staging, never third-party domains or production without sign-off. The skill enforces this as a gate before firing.

## License

MIT
