# VAL-03 — Yandex Cloud Function Results

**Tested:** 2026-05-11
**Tester:** operator (foreign network only so far)
**Function URL:** `https://functions.yandexcloud.net/d4engb6fl2nijjdfh98g`
**Function ID:** `d4engb6fl2nijjdfh98g` (folder `b1gamurq8prfsf4dso64`)
**Runtime:** nodejs22 (`yc serverless function runtime list` showed nodejs20 doesn't exist, only nodejs22)

## Verdict: PASS (operator side); RU side pending

## Operator-side test (foreign IP)

```bash
curl -sm 30 -X POST 'https://functions.yandexcloud.net/d4engb6fl2nijjdfh98g' \
     -H 'X-Maskanya-Token: <token>' \
     -d '{"url":"https://ifconfig.me"}'
```

**Response:** HTTP 200 with body containing ifconfig.me's full HTML; the IP visible in the returned page is **`185.206.167.220`** (a Yandex Cloud egress IP, AS200350 / AS13238 / Yandex CIDR). That's the goal — function reaches arbitrary foreign HTTPS and proxies the response.

Auth gate works:
- Bad token → `401 unauthorized` from our handler ✓
- No token → `401 unauthorized` from our handler ✓

## RU-side test
**Pending.** The same curl from a RU client is the actual bar for VAL-03. Function endpoint `functions.yandexcloud.net` is structurally on the YC whitelist; reachability under whitelist mode is the question.

Run from a RU device:
```bash
URL='https://functions.yandexcloud.net/d4engb6fl2nijjdfh98g'
TOKEN='<from .env BEARER_TOKEN>'
curl -X POST "$URL" \
     -H "X-Maskanya-Token: $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"url":"https://ifconfig.me"}'
```
Same expected response as operator test. If TLS RST or timeout — note carrier and abandon for that ISP.

## Empirical findings (recorded for v0.2 / production design)

1. **`Authorization: Bearer …` header is unusable** as our auth mechanism — YC API gateway intercepts it and tries to validate it as an IAM token. Custom token → 403 from YC platform before our handler runs. We use **`X-Maskanya-Token`** instead. Production Channel C (Phase 3) must keep this constraint in mind when designing JWT issuance.

2. **YC requires explicit `Public function` toggle** even when access binding `allUsers → functions.functionInvoker` is set via `add-access-binding`. The toggle in console UI is the canonical way; CLI `allow-unauthenticated-invoke` requires `iam.editor` role which `editor` role on folder doesn't include. Document for Phase 3 Terraform deployment.

3. **Runtime constraint:** YC has only `nodejs22` available (no `nodejs20`). PoC code uses standard Node fetch + AbortSignal + Buffer — works fine on 22. Future deployments pin to `nodejs22`.

4. **Service Account roles:** `editor` on folder is sufficient for: function CRUD, version create, env vars set. NOT sufficient for: `allow-unauthenticated-invoke` (needs `iam.editor`). For Phase 3 Terraform-driven multi-tenancy, give the deployer SA also `iam.editor` so deploy is fully scripted.

5. **Function logs require additional permission** — `yc serverless function logs` returns RPC error with `editor` role. Logs viewing needs `logging.viewer` or higher on the log group. Add for Phase 3.

## Recommendation

- PASS on operator side → Channel C is technically viable.
- PROCEED to RU-side test before declaring full PASS.
- Phase 3 production scope:
  - Replace fetch-relay with HTTP CONNECT tunnel to ZOV
  - Replace shared bearer token with per-user JWT signed by Marzban
  - Custom auth header (`X-Maskanya-Token` or similar) — DON'T use `Authorization`
  - Multi-tenancy: 2 YC accounts, each with editor + iam.editor SA, Terraform-managed
