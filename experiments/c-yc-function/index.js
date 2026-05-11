// Maskanya Channel C PoC — fetch-relay function for Yandex Cloud Functions.
//
// Stateless: client POSTs { url, method?, headers?, body? }, function fetches
// and returns { status, headers, body } as JSON. Body is base64 if not utf-8.
//
// Auth: shared bearer token in Authorization header. Set BEARER_TOKEN env var
// at function-create time.

const BEARER_TOKEN = process.env.BEARER_TOKEN;
const MAX_BODY_BYTES = 5 * 1024 * 1024;  // 5 MB — YC has a 10 MB response cap

exports.handler = async function (event) {
    // Auth gate — using a custom header because `Authorization: Bearer …`
    // is intercepted by YC's API gateway, which tries to validate as IAM
    // token and 403s before our handler ever runs.
    const headers = event.headers || {};
    const token = headers['X-Maskanya-Token'] || headers['x-maskanya-token'] || '';
    if (!BEARER_TOKEN || token !== BEARER_TOKEN) {
        return { statusCode: 401, body: 'unauthorized' };
    }

    let req;
    try {
        req = JSON.parse(event.body || '{}');
    } catch (e) {
        return { statusCode: 400, body: 'invalid json' };
    }
    if (!req.url) {
        return { statusCode: 400, body: 'missing url' };
    }

    let resp;
    try {
        resp = await fetch(req.url, {
            method: req.method || 'GET',
            headers: req.headers || {},
            body: req.body,
            signal: AbortSignal.timeout(30_000),
        });
    } catch (e) {
        return { statusCode: 502, body: `upstream: ${e.message}` };
    }

    const buf = Buffer.from(await resp.arrayBuffer());
    if (buf.length > MAX_BODY_BYTES) {
        return { statusCode: 413, body: 'upstream body too large' };
    }
    const ct = resp.headers.get('content-type') || '';
    const isText = /^text\/|json|xml|javascript/i.test(ct);

    return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            status: resp.status,
            headers: Object.fromEntries(resp.headers.entries()),
            body: isText ? buf.toString('utf-8') : buf.toString('base64'),
            body_encoding: isText ? 'utf-8' : 'base64',
        }),
    };
};
