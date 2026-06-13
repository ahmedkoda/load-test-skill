#!/usr/bin/env bash
# run_load.sh — auto-detect a load tool, run it, and emit normalized JSON.
#
# Normalized output (stdout, last line is the JSON):
#   { "tool", "url", "method", "concurrency", "duration_s", "requests_total",
#     "requests_per_sec", "latency_ms": {"p50","p90","p99","max","mean"},
#     "non_2xx", "errors", "error_rate" }
#
# Tool preference: k6 > autocannon (via npx) > ab > hey.
# k6 is required for --profile stress|spike|soak ramps; others run steady load.

set -euo pipefail

URL=""; METHOD="GET"; CONCURRENCY=10; DURATION=30; REQUESTS=""; PROFILE="load"
BODY=""; OUT=""; HEADERS=()

usage() {
  cat <<EOF
Usage: run_load.sh --url <url> [options]
  --url <url>             Target URL (required)
  --method <M>            HTTP method (default GET)
  --concurrency <N>       Concurrent users/connections (default 10)
  --duration <sec>        Test duration in seconds (default 30)
  --requests <N>          Fixed request count instead of duration
  --body <json>           Request body
  --header "K: V"         Add a header (repeatable)
  --profile <p>           load|stress|spike|soak (ramps need k6; default load)
  --out <path>            Also write normalized JSON to this file
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="$2"; shift 2;;
    --method) METHOD="$2"; shift 2;;
    --concurrency) CONCURRENCY="$2"; shift 2;;
    --duration) DURATION="$2"; shift 2;;
    --requests) REQUESTS="$2"; shift 2;;
    --body) BODY="$2"; shift 2;;
    --header) HEADERS+=("$2"); shift 2;;
    --profile) PROFILE="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

[[ -z "$URL" ]] && { echo "ERROR: --url is required" >&2; usage; exit 2; }

have() { command -v "$1" >/dev/null 2>&1; }

# Pick tool. npx-autocannon counts if node is present even when not globally installed.
TOOL=""
if have k6; then TOOL="k6"
elif have autocannon; then TOOL="autocannon"
elif have npx && have node; then TOOL="autocannon-npx"
elif have ab; then TOOL="ab"
elif have hey; then TOOL="hey"
else echo "ERROR: no load tool found (need one of: k6, autocannon, ab, hey)" >&2; exit 3
fi

# Ramp profiles need k6.
case "$PROFILE" in
  stress|spike|soak)
    if [[ "$TOOL" != "k6" ]]; then
      echo "ERROR: --profile $PROFILE needs k6 (ramps/stages). Install with: brew install k6" >&2
      exit 4
    fi;;
esac

RAW="$(mktemp)"; trap 'rm -f "$RAW"' EXIT
emit() { # echoes normalized JSON; also writes --out if set
  local json="$1"
  [[ -n "$OUT" ]] && printf '%s\n' "$json" > "$OUT"
  printf '%s\n' "$json"
}

# ---- autocannon (global or npx): native JSON with percentiles ----
run_autocannon() {
  local bin=(autocannon); [[ "$TOOL" == "autocannon-npx" ]] && bin=(npx --yes autocannon)
  local args=(-c "$CONCURRENCY" -m "$METHOD" --json)
  if [[ -n "$REQUESTS" ]]; then args+=(-a "$REQUESTS"); else args+=(-d "$DURATION"); fi
  [[ -n "$BODY" ]] && args+=(-b "$BODY")
  for h in "${HEADERS[@]:-}"; do [[ -n "$h" ]] && args+=(-H "$h"); done
  "${bin[@]}" "${args[@]}" "$URL" > "$RAW" 2>/dev/null
  node -e '
    const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    const l=d.latency||{}, r=d.requests||{};
    const non2xx=(d.non2xx||0)+(d["1xx"]||0)+(d["3xx"]||0); // non-success buckets
    const errors=(d.errors||0)+(d.timeouts||0);
    const total=(r.total!=null?r.total:d.requests&&d.requests.total)||0;
    const dur=(d.duration!=null?d.duration:'"$DURATION"');
    const out={tool:"autocannon",url:process.argv[2],method:"'"$METHOD"'",
      concurrency:'"$CONCURRENCY"',duration_s:dur,requests_total:total,
      requests_per_sec:(d.throughput&&d.throughput.average!=null)?undefined:(r.average||0),
      latency_ms:{p50:l.p50,p90:l.p90,p99:l.p99,max:l.max,mean:l.average},
      non_2xx:non2xx,errors:errors,
      error_rate: total? +(((errors+ (d.non2xx||0))/(total||1))*100).toFixed(3):0};
    out.requests_per_sec = r.average!=null? r.average : (r.mean||0);
    console.log(JSON.stringify(out));
  ' "$RAW" "$URL"
}

# ---- ab (ApacheBench): parse text output ----
run_ab() {
  local n="${REQUESTS:-}"
  if [[ -z "$n" ]]; then n=$(( CONCURRENCY * DURATION * 5 )); fi  # estimate when only duration given
  local args=(-n "$n" -c "$CONCURRENCY" -m "$METHOD" -l)
  local bodyfile=""
  if [[ -n "$BODY" ]]; then bodyfile="$(mktemp)"; printf '%s' "$BODY" > "$bodyfile"; args+=(-p "$bodyfile"); fi
  for h in "${HEADERS[@]:-}"; do [[ -n "$h" ]] && args+=(-H "$h"); done
  ab "${args[@]}" "$URL" > "$RAW" 2>/dev/null || true
  [[ -n "$bodyfile" ]] && rm -f "$bodyfile"
  awk -v url="$URL" -v conc="$CONCURRENCY" -v meth="$METHOD" '
    /Complete requests:/      {total=$3}
    /Failed requests:/        {failed=$3}
    /Non-2xx responses:/      {non2xx=$3}
    /Requests per second:/    {rps=$4}
    /Time taken for tests:/   {dur=$5}
    /^  50%/ {p50=$2} /^  90%/ {p90=$2} /^  99%/ {p99=$2} /^ 100%/ {max=$2}
    /Total:/ {if($2=="" ){} }
    END{
      if(non2xx=="")non2xx=0; if(failed=="")failed=0;
      er=(total>0)?( (failed+non2xx)/total*100 ):0;
      printf "{\"tool\":\"ab\",\"url\":\"%s\",\"method\":\"%s\",\"concurrency\":%s,\"duration_s\":%s,\"requests_total\":%s,\"requests_per_sec\":%s,\"latency_ms\":{\"p50\":%s,\"p90\":%s,\"p99\":%s,\"max\":%s,\"mean\":null},\"non_2xx\":%s,\"errors\":%s,\"error_rate\":%.3f}\n",
        url,meth,conc,(dur==""?0:dur),(total==""?0:total),(rps==""?0:rps),(p50==""?0:p50),(p90==""?0:p90),(p99==""?0:p99),(max==""?0:max),non2xx,failed,er;
    }' "$RAW"
}

# ---- hey: parse text output ----
run_hey() {
  local args=(-c "$CONCURRENCY" -m "$METHOD")
  if [[ -n "$REQUESTS" ]]; then args+=(-n "$REQUESTS"); else args+=(-z "${DURATION}s"); fi
  [[ -n "$BODY" ]] && args+=(-d "$BODY")
  for h in "${HEADERS[@]:-}"; do [[ -n "$h" ]] && args+=(-H "$h"); done
  hey "${args[@]}" "$URL" > "$RAW" 2>/dev/null || true
  awk -v url="$URL" -v conc="$CONCURRENCY" -v meth="$METHOD" '
    /Requests\/sec:/ {rps=$2}
    /Total:/ {if(dur==""){dur=$2}}
    /\[200\]/ {ok=$1}
    /50% in/ {p50=$3*1000} /90% in/ {p90=$3*1000} /99% in/ {p99=$3*1000}
    /responses:/ {total=$1}
    END{
      printf "{\"tool\":\"hey\",\"url\":\"%s\",\"method\":\"%s\",\"concurrency\":%s,\"duration_s\":%s,\"requests_total\":%s,\"requests_per_sec\":%s,\"latency_ms\":{\"p50\":%s,\"p90\":%s,\"p99\":%s,\"max\":null,\"mean\":null},\"non_2xx\":null,\"errors\":null,\"error_rate\":null}\n",
        url,meth,conc,(dur==""?0:dur),(total==""?0:total),(rps==""?0:rps),(p50==""?0:p50),(p90==""?0:p90),(p99==""?0:p99);
    }' "$RAW"
}

# ---- k6: generate a script for the chosen profile, run, parse summary JSON ----
run_k6() {
  local k6script summary
  k6script="$(mktemp /tmp/k6_XXXX.js)"; summary="$(mktemp)"
  local stages
  case "$PROFILE" in
    stress) stages="{duration:'30s',target:$CONCURRENCY},{duration:'30s',target:$((CONCURRENCY*2))},{duration:'30s',target:$((CONCURRENCY*4))},{duration:'15s',target:0}";;
    spike)  stages="{duration:'10s',target:5},{duration:'10s',target:$CONCURRENCY},{duration:'30s',target:$CONCURRENCY},{duration:'10s',target:5}";;
    soak)   stages="{duration:'1m',target:$CONCURRENCY},{duration:'15m',target:$CONCURRENCY},{duration:'1m',target:0}";;
    *)      stages="{duration:'${DURATION}s',target:$CONCURRENCY}";;
  esac
  # Build headers/body literals
  local hjson="{" first=1
  for h in "${HEADERS[@]:-}"; do
    [[ -z "$h" ]] && continue
    local k="${h%%:*}" v="${h#*: }"
    [[ $first -eq 0 ]] && hjson+=","; hjson+="\"$k\":\"$v\""; first=0
  done
  hjson+="}"
  local bodyjs="null"; [[ -n "$BODY" ]] && bodyjs="$(printf '%s' "$BODY" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify(s)))')"
  cat > "$k6script" <<JS
import http from 'k6/http';
export const options = { stages: [ $stages ] };
export default function () {
  const params = { headers: $hjson };
  http.request('$METHOD', '$URL', $bodyjs, params);
}
export function handleSummary(data){ return { 'stdout': JSON.stringify(data) }; }
JS
  k6 run "$k6script" > "$summary" 2>/dev/null || true
  node -e '
    const fs=require("fs"); let d; try{d=JSON.parse(fs.readFileSync(process.argv[1],"utf8"))}catch(e){console.log("{}");process.exit(0)}
    const m=d.metrics||{}; const dur=m.http_req_duration&&m.http_req_duration.values||{};
    const reqs=m.http_reqs&&m.http_reqs.values||{}; const failed=m.http_req_failed&&m.http_req_failed.values||{};
    const total=reqs.count||0; const rate=failed.rate!=null?failed.rate:0;
    const out={tool:"k6",url:process.argv[2],method:"'"$METHOD"'",concurrency:'"$CONCURRENCY"',
      duration_s:Math.round((reqs.count&&reqs.rate)?reqs.count/reqs.rate:0),
      requests_total:total,requests_per_sec:+(reqs.rate||0).toFixed(2),
      latency_ms:{p50:dur.med,p90:dur["p(90)"],p99:dur["p(99)"],max:dur.max,mean:dur.avg},
      non_2xx:Math.round(total*rate),errors:Math.round(total*rate),error_rate:+(rate*100).toFixed(3)};
    console.log(JSON.stringify(out));
  ' "$summary" "$URL"
  rm -f "$k6script" "$summary"
}

case "$TOOL" in
  k6) emit "$(run_k6)";;
  autocannon|autocannon-npx) emit "$(run_autocannon)";;
  ab) emit "$(run_ab)";;
  hey) emit "$(run_hey)";;
esac
