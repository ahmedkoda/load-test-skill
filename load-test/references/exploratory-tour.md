# Exploratory tour — confirm a journey & harvest its endpoints

Goal: turn a *named* journey ("login → open dashboard → run a report") into the **concrete HTTP calls** a load test can actually fire. You walk the journey once, live, in a real browser, confirm each step with the user, and record every network request that the steps trigger. Those recorded calls — with their real auth token — become the load-test targets.

This is recon, run **once at low volume**. It is not the load test. Be gentle: a single pass, real user pace.

## Tools

Use whatever browser automation is available — e.g. the Playwright MCP tools (`browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, `browser_fill_form`, `browser_network_requests`, `browser_network_request`, `browser_evaluate`). The network capture is the payload of this whole exercise.

## Procedure

1. **Restate the journey and get sign-off.** Write the steps back to the user as a numbered list and confirm before driving anything. Correct the list until the user agrees. This is the journey you'll later claim the load test covers, so it must be right.

2. **Drive it once, narrating each step.** Navigate and act step by step. After each step, take a snapshot and tell the user what happened. Use the credentials the user provides — never fuzz or guess credentials; many apps lock an account after a few wrong attempts.

3. **Capture the network traffic.** After completing the journey (or after each meaningful step), pull the request log. For every request that belongs to the journey, record:
   - **method + URL** (the load-test target)
   - **request body** (for POST/PUT — the load test must send the same shape)
   - **auth** — the `Authorization: Bearer <token>` header (capture the token to reuse under load), or session cookie if that's the scheme
   - **status** + **response time** of this single call (your single-user baseline — load p99 will be compared against it)

   Filter out noise: static assets (`.js`, `.css`, images, fonts), analytics, and third-party beacons are not the journey. Keep the XHR/fetch calls to the app's own API origins.

4. **Present the harvested endpoints and pick the target(s).** Show the user a short table of the captured calls and let them choose what to load-test:

   ```
   Endpoints captured on this journey:
   #  Method  Endpoint                         Status  Baseline
   1  POST    api.example.com/auth/login       200     180ms
   2  GET     api.example.com/dashboard        200     90ms
   3  POST    api.example.com/reports/run      201     240ms   ← the write, usually the one that matters
   ```

   Guide the choice: the **write/expensive call** is usually the most revealing under load; read endpoints are cheaper and less likely to break. The user may pick one endpoint (simplest, runs on any tool) or the full sequence (needs k6 to replay in order with the token threaded between steps).

5. **Hand the result to the load run.** Produce the exact `run_load.sh` invocation (or k6 script for a full sequence) pre-filled with the chosen endpoint, method, body, and the freshly-captured token. Then return to the intake's second question — *how many concurrent users* — and run.

## Why bother

Without the tour, a "journey load test" is really just guessing a URL and hoping it represents the flow. The tour removes the guess: you load-test the calls the journey **actually makes**, with **valid auth**, and you have a **single-user baseline** to judge the load percentiles against. It also doubles as a quick smoke test — if the journey can't even be walked once by hand, there's no point load-testing it yet.

## Token freshness

Tokens expire. Capture the token as late as possible before the load run, and if a long setup happens between the tour and the run, re-authenticate to refresh it. A load test that 401s halfway because the token expired wastes the run and looks like a fake error spike.
