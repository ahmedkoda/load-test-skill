---
name: load-test
description: >-
  Run multi-user LOAD and STRESS tests against a web page, user journey, or API
  endpoint, then report latency percentiles (p50/p90/p99), throughput, and error
  rate with a pass/fail verdict against thresholds. Use this whenever the user
  wants to know how a target behaves under concurrent load — phrases like "load
  test", "stress test", "how many users can it handle", "test under concurrency",
  "hammer this endpoint", "find the breaking point", "soak test", or "spike test".
  This is the right skill when the question is about behavior under MANY simultaneous
  users. It is complementary to single-user performance timing: reach for a
  single-user perf tool when the user wants how fast ONE user's flow feels, and
  reach for load-test when they want how the system holds up under CONCURRENT users.
---

# Load & Stress Testing

Measure how a target holds up under **concurrent** load — not how one user experiences it. Single-user timing is a different question; this skill answers: *what happens when N users hit it at once, and where does it break?*

## Step 0 — Orient the user before doing anything

The first time this skill is invoked in a session, do **not** jump straight to running a test. Begin by showing the user how the skill works and what it needs, so they can decide and supply inputs. Present this orientation block (adapt the wording, keep the substance), then wait:

```
🚀 Load & Stress Testing — how this works

What it does: fires many concurrent requests at a target and reports how it
holds up — throughput, latency p50/p90/p99, error rate, and a PASS/FAIL verdict
(or a breaking point for stress runs).

How it runs: orient → (optional) exploratory tour → run via an auto-detected
tool → read results → verdict + report.

Optional first: an exploratory tour — I walk your journey once in a real
browser, confirm the steps with you, and harvest the real endpoints + auth
token so the load test hits exactly what the journey calls (not a guessed URL).

What I need from you:
  • Target        a URL, API endpoint, or journey you are AUTHORIZED to load-test
  • Profile       load (steady) · stress (ramp to breaking) · spike · soak   [default: load]
  • Concurrency   how many simultaneous users                                 [default: 10]
  • Duration      how long, or a fixed request count                          [default: 30s]
  • For APIs      method, body, and any auth token (so we don't just flood 401s)
  • Thresholds    pass/fail limits — or I'll use defaults (p99 ≤ 2s, errors ≤ 1%)

Readiness: a simple URL/API load test runs immediately if Node/npx is present
(autocannon, no install) or ApacheBench (ab) is installed. Stress/spike/soak
ramps and multi-step journeys need k6.

⚠️ Authorization: load testing looks like a denial-of-service attack to the
server. Only run against targets you are explicitly authorized to hit — your own
dev/staging is fine; never third-party domains or production without sign-off.

Tell me the target and any of the above you care about, and I'll run it.
```

Run the readiness line dynamically when useful — `scripts/run_load.sh --help` lists flags, and the tool-detection logic in the runner tells you which engine is available. Skip re-showing this block on later runs in the same session unless the user asks how it works again.

### Intake — ask for the two essentials, in order

After the orientation block, do not assume the target or the load size. **Ask the user explicitly, one at a time, and wait for each answer** — this keeps the run honest and authorized:

1. **The journey / target first.** Ask which journey or target to load-test — accept a named user journey (e.g. login → open dashboard → run a report), a single URL, or an API endpoint.

   **Offer an exploratory tour to confirm the journey and harvest its endpoints.** A named journey is not yet something you can load-test — you need the concrete HTTP calls behind it. So when the target is a journey (or the user is unsure of the exact endpoints), offer to walk it once and capture the real calls. If they accept, run the recon pass in `references/exploratory-tour.md`: drive the journey once live with browser automation (e.g. the Playwright MCP tools), confirm each step back to the user, and capture every network request that fires (method, URL, payload, and the auth token). The captured calls become the precise load-test targets, and the token is reused so the load run hits authenticated endpoints instead of a wall of 401s. If the user declines, fall back to a single URL/endpoint they provide.

   If it's a multi-step journey you intend to replay in sequence (not just one captured endpoint), note that this needs k6 (see step 2 and `references/tools.md`); offer to install it or to load-test the single most important endpoint the tour surfaced. Confirm the target back to the user before moving on.

2. **The number of concurrent users second — ALWAYS ask, every single run.** Once the target is set, ask how many concurrent users should drive the load — this is the `--concurrency` value. If the user is unsure, suggest a starting point (e.g. 10 for a sanity check, 50–100 for expected traffic) and note that a stress profile can ramp beyond it to find the breaking point.

   This question is **non-negotiable and non-skippable**. Ask it before *every* load run, even when:
   - the journey or target was described earlier, reused from a previous request, or carried over from an exploratory tour;
   - the user said something like "run the flow I asked for before" or "do it again";
   - you already ran a load test this session (do **not** silently reuse the previous concurrency — re-ask, even if you suggest the last value as the default).

   The concurrency is what makes this a *load* test rather than a single request, and it determines whether the run is safe and authorized — so it must come from the user each time, never inferred. If you ever find yourself about to run `run_load.sh` without having just asked the user for the user count in this exchange, stop and ask first.

Only after you have both — the journey/target and the user count, freshly confirmed this run — proceed to confirm the rest of the config (profile, duration, thresholds, auth for APIs) and run. Don't fire a load test with a guessed target or guessed concurrency; both directly shape what the numbers mean and whether the run is authorized.

## When to use which load profile

| Profile | Shape | Answers |
|---|---|---|
| **Load** (default) | Hold steady concurrency for a fixed duration | "Does it stay healthy at the expected traffic?" |
| **Stress** | Ramp concurrency up in steps until errors/latency blow past thresholds | "Where is the breaking point?" |
| **Spike** | Jump from low to very high concurrency suddenly, then drop | "Does a sudden surge knock it over / can it recover?" |
| **Soak** | Moderate concurrency held for a long time (15min+) | "Does it leak or degrade over time?" |

If the user doesn't say, default to **Load** and ask one quick question only if the target or numbers are ambiguous.

## Workflow

### 1. Establish the target and parameters

Pin down: **Target** (full URL — page or API); **Method + body + headers** (GET by default; for APIs capture the JSON body, `Content-Type`, and any `Authorization` bearer token — get a token first if the endpoint needs one); **Concurrency**; **Duration** (or request count) and, for stress/spike, the **ramp** stages; **Thresholds** for the verdict (propose defaults if the user has none).

> **Authorization gate.** Only load-test targets the user is authorized to hit. Load testing is indistinguishable from a denial-of-service attack from the server's side. Your own dev/staging is fair game; never point this at third-party domains or production without explicit confirmation.

### 2. Run the test

> **Precondition:** never invoke the runner unless you asked the user for the concurrency (user count) in this exchange and they answered. If you can't point to that answer, go back to intake step 2 and ask.

Use the bundled runner — it auto-detects the best available tool and normalizes output to one JSON shape. Reference it by this skill's directory (shown as the **Base directory** when the skill is invoked); e.g. `<skill-dir>/scripts/run_load.sh`:

```bash
"<skill-dir>/scripts/run_load.sh" \
  --url "https://api.example.com/health" \
  --concurrency 50 \
  --duration 30
```

Common flags: `--method POST`, `--body '{"key":"value"}'`, `--header "Content-Type: application/json"`, `--header "Authorization: Bearer <token>"`, `--requests <N>` (instead of duration), `--profile stress|spike|soak`, `--out <path.json>`.

The runner prefers **k6** (best for ramps and multi-step journeys) → **autocannon** (zero-install via `npx`, great JSON) → **ab** (preinstalled on macOS) → **hey**. If none beyond `ab` exist and the user wants stress ramps or journey steps, offer to install k6 — read `references/tools.md` for the per-tool capability matrix and install commands.

**Multi-step journeys** (login → navigate → act, not a single URL) need k6, because they require scripted sequencing and token extraction between steps. If the target is a journey and k6 isn't installed, say so and either offer to install it or fall back to the single most important endpoint in the flow — don't silently pretend a single-URL flood covers a journey.

### 3. Read the results

The runner emits normalized JSON: `requests_total`, `requests_per_sec`, `latency_ms` (`p50`,`p90`,`p99`,`max`), `errors`, `non_2xx`, `duration_s`. Always surface:

- **Throughput** — requests/sec actually sustained.
- **Latency percentiles** — lead with **p90 and p99**, not the mean. Averages hide the tail, and the tail is where users feel pain.
- **Error rate** — distinguish non-2xx responses (app broke, 500s) from connection failures (timeouts/resets — the server stopped accepting connections, often the real breaking point).

### 4. Verdict against thresholds

Give a clear **PASS / FAIL** call. Default thresholds when the user gives none (state they're defaults and tune-able): p99 ≤ 2000ms, error rate ≤ 1%, throughput meets any stated target. For a **stress** run the verdict is the **breaking point** — the concurrency level at which p99 or error rate first crossed the thresholds.

### 5. Report

```
## Load Test — <target>

**Profile:** <load|stress|spike|soak>  ·  **Tool:** <k6|autocannon|ab|hey>
**Config:** <N> concurrent, <duration|requests>, <ramp if any>

### Results
| Metric | Value |
|---|---|
| Throughput | <X> req/s |
| Latency p50 / p90 / p99 / max | <…> ms |
| Error rate | <X>% (<non-2xx> non-2xx, <conn errors> connection errors) |

### Verdict: ✅ PASS / ❌ FAIL  (or: breaking point ≈ <N> users)
<one-paragraph plain-language read: what holds, what hurts, and the single biggest risk>
```

If the run uncovers a real defect (the app 500s under load, leaks, or never recovers from a spike), that's a finding — offer to file it via whatever issue tracker the project uses.

If the user wants a **non-technical HTML report**, produce a self-contained single-file HTML with a traffic-light verdict, plain-language explanation (avoid p99/throughput jargon — translate to "typical wait" and "did it stay up"), and suggested next steps.

## Notes

- **Warm-up matters.** Cold caches and JIT make the first few seconds unrepresentative. For steady Load runs, prefer ≥30s; mention if a run was too short to trust.
- **You're measuring the whole path** — network, TLS, any CDN/proxy, and the DB all count. A slow p99 isn't automatically "the app is slow"; say what layer the evidence points to when you can.
- **Don't over-claim from one run.** Load numbers are noisy. For a verdict that matters, run twice and report whether they agree.
