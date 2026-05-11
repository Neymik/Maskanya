# Channel C PoC — Yandex Cloud Function

**What this tests:** Two questions, neither of which has a confident a priori answer:
1. Can a Russian client reach `*.functions.yandexcloud.net` reliably (yes, structurally — but verify in your specific RU ISP).
2. Can a YC function reach foreign internet (in particular, `103.137.249.134` / ZOV) — and can it do that without falling foul of YC's egress policies or causing the function account to be ToS-flagged within minutes?

This is NOT a real tunnel yet. It's a **fetch-relay**: client sends a URL, function fetches it, returns the body. If this works, we know the channel is viable and we can later replace fetch-relay with proper HTTP CONNECT tunneling.

## Prerequisites

- Yandex Cloud account (free tier is fine — `1M invocations + 10 GB-s/month`).
- `yc` CLI configured (`yc init`).
- A folder ID and service account ID. Get them via `yc resource-manager folder list` and `yc iam service-account list`.

## Files

- `index.js` — the function source. ~50 lines. Node.js 20.
- `package.json` — declares dependencies (none beyond Node built-ins).
- `deploy.sh` — `yc serverless function ...` invocations to create + version + make-public.

## Step-by-step

### 1. Configure deploy

```bash
cp .env.example .env
# edit .env to set FOLDER_ID, SERVICE_ACCOUNT_ID, FUNCTION_NAME, BEARER_TOKEN
```

`BEARER_TOKEN` is just a random shared secret for this PoC — generate via `openssl rand -hex 32`.

### 2. Deploy

```bash
./deploy.sh
```

Outputs the public function URL, looks like:
```
https://functions.yandexcloud.net/d4e3xxxxxxxxxxxxxxxx
```

### 3. Test from your laptop (anywhere)

```bash
export FUNC_URL='https://functions.yandexcloud.net/d4e3xxx'
export TOKEN='whatever-bearer-token-you-set'

curl -X POST "$FUNC_URL" \
     -H "X-Maskanya-Token: $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"url":"https://ifconfig.me"}'
```

(Note: header is `X-Maskanya-Token`, NOT `Authorization`. YC API gateway intercepts `Authorization: Bearer ...` as IAM token validation and rejects with 403 before our handler runs. Empirically discovered during PoC; documented here so the next person doesn't re-hit it.)

Expect: a YC-resident IP (the function's egress, e.g. `185.206.*`) — that's good. It means YC functions can fetch external HTTPS.

### 4. Test from a Russian network

Same `curl` from a RU IP (with `X-Maskanya-Token`, not `Authorization`). Expect: same response. If it fails:
- TLS handshake failure → some RU mobile carriers do TLS interception that breaks YC's cert chain. Test on multiple ISPs.
- Connection timeout → unlikely (YC is whitelist-resident) but possible if your specific carrier has a buggy whitelist deployment.

### 5. Test reaching ZOV through the function

```bash
curl -X POST "$FUNC_URL" \
     -H "X-Maskanya-Token: $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"url":"http://103.137.249.134/"}'
```

Expect: ZOV's nginx welcome / 404 / whatever it serves on `:80`. If this works, we know the function can talk to NL.

## What success means

- Step 3 from anywhere: passes → function logic + deploy work.
- Step 4 from RU: passes → channel is alive against current RU regime.
- Step 5: passes → the function can be turned into a proper tunnel later.

## What failure means

- 502/504 from YC: function timing out (default timeout is 5 sec; bump to 60 in `deploy.sh` if needed).
- 451/403 from YC: function got flagged or rate-limited. Try a different YC account or wait it out.
- TCP RST from RU side: rare; means RU carrier broke YC TLS on this route. Try another ISP.

## Tear down

```bash
./teardown.sh
```

`yc serverless function delete --name $FUNCTION_NAME`.

## Beyond PoC

If this works, the real Channel C in the spec replaces the fetch-relay with HTTP CONNECT tunneling: client opens a CONNECT to the function, function relays bytes to ZOV's `xray_yc_bridge` inbound, ZOV routes to internet. That's Phase 3 in the design spec — not in scope here.
