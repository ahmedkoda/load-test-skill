# Load tool capability matrix & install

The runner (`scripts/run_load.sh`) auto-selects in this order. This file is for when you need to decide whether to install something or explain a limitation.

| Tool | Steady load | Ramp/stages (stress/spike/soak) | Multi-step journeys | Native percentiles | Install |
|---|---|---|---|---|---|
| **k6** | ✅ | ✅ | ✅ (scripted) | ✅ p90/p95/p99 | `brew install k6` (macOS) · [k6.io/docs/get-started/installation](https://k6.io/docs/get-started/installation) |
| **autocannon** | ✅ | ❌ (single phase) | ❌ | ✅ p50/p90/p99 | `npm i -g autocannon`, or zero-install via `npx autocannon` when Node is present |
| **ab** (ApacheBench) | ✅ | ❌ | ❌ | ✅ percentile table | preinstalled on macOS (`/usr/sbin/ab`); Linux: `apt install apache2-utils` |
| **hey** | ✅ | ❌ | partial | ✅ | `brew install hey` · `go install github.com/rakyll/hey@latest` |

## Picking a tool

- **Single URL / API, steady or simple stress** → autocannon (via `npx`, nothing to install when Node is available) gives clean JSON with percentiles — least friction.
- **`ab` is the guaranteed floor on macOS** — always present. Good enough for a quick steady-load percentile read; cannot ramp.
- **Ramps (stress/spike/soak) or multi-step journeys** → only **k6** can do these honestly. If it's not installed and the user wants a breaking-point or a login→act→logout flow under load, offer to install k6 rather than faking it with a single-URL flood.

To see what's installed on the current machine, the runner detects automatically; or check manually:

```bash
for t in k6 autocannon ab hey; do command -v "$t" >/dev/null && echo "✅ $t" || echo "❌ $t"; done
```

## k6 multi-step journey template

When a journey (not a single URL) must be load-tested, hand-write a k6 script instead of using the runner's single-request default. Skeleton:

```js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = { stages: [
  { duration: '30s', target: 50 },   // ramp up
  { duration: '1m',  target: 50 },   // hold
  { duration: '15s', target: 0 },    // ramp down
]};

export default function () {
  // 1. login — extract token
  const login = http.post('https://api.example.com/auth/login',
    JSON.stringify({ username: __ENV.USER, password: __ENV.PASS }),
    { headers: { 'Content-Type': 'application/json' } });
  check(login, { 'login 200': (r) => r.status === 200 });
  const token = login.json('token'); // adjust to the real response shape

  // 2. authenticated action under load
  const auth = { headers: { Authorization: `Bearer ${token}` } };
  const res = http.get('https://api.example.com/dashboard', auth);
  check(res, { 'action 200': (r) => r.status === 200 });
  sleep(1); // think-time between iterations — keeps the load realistic
}

export function handleSummary(data) { return { stdout: JSON.stringify(data) }; }
```

Note the **think-time** (`sleep`) — real users pause between actions. A journey load test with no think-time overstates pressure and understates how many real concurrent users the system actually serves. Pass secrets via env vars (`k6 run -e USER=... -e PASS=... script.js`) rather than hard-coding them, and use known-good credentials — don't fuzz logins under load, since many apps lock accounts after a few failed attempts.
