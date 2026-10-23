#!/usr/bin/env node
// Minimal Happier API client for the template tests (Node >= 22 stdlib only: crypto, fetch, WebSocket).
// It speaks the same device-key protocol as the official apps: an Ed25519 key signs a challenge at POST /v1/auth.
// Secrets (key seeds, tokens) live in mode-600 files under the directory given as KEY_DIR and are never printed.
//
//   happier-client.mjs auth    <url> <name>            -> {"status":200,"accountId":"..."} or {"status":403,"error":"signup-disabled"}
//   happier-client.mjs write   <url> <name> <marker>   -> creates a session tagged <marker> with one message and a KV entry
//   happier-client.mjs verify  <url> <name> <marker>   -> reads them back
//   happier-client.mjs socket  <url> <name>            -> opens the realtime Socket.IO channel (/v1/updates) over WebSocket
//   happier-client.mjs pair    <url> <name> <machine>  -> terminal pairing: <machine> requests auth, <name> approves it
import { createPrivateKey, createPublicKey, generateKeyPairSync, randomBytes, sign } from "node:crypto";
import { chmodSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [cmd, base, name, arg] = process.argv.slice(2);
const KEY_DIR = process.env.KEY_DIR;
if (!cmd || !base || !name || !KEY_DIR) {
    console.error("usage: KEY_DIR=dir happier-client.mjs <auth|write|verify|socket|pair> <url> <name> [arg]");
    process.exit(2);
}
const url = base.replace(/\/+$/, "");
const b64 = (buf) => Buffer.from(buf).toString("base64");
const out = (obj) => console.log(JSON.stringify(obj));

function secretFile(file, value) {
    writeFileSync(file, value, { mode: 0o600 });
    chmodSync(file, 0o600);
}

// Ed25519 identity, persisted as PKCS#8 PEM so the same "device" can sign in again later.
function identity(id) {
    const file = join(KEY_DIR, `${id}.key.pem`);
    if (!existsSync(file)) {
        const { privateKey } = generateKeyPairSync("ed25519");
        secretFile(file, privateKey.export({ type: "pkcs8", format: "pem" }));
    }
    const privateKey = createPrivateKey(readFileSync(file));
    const raw = Buffer.from(createPublicKey(privateKey).export({ format: "jwk" }).x, "base64url");
    return { privateKey, publicKey: b64(raw) };
}

async function api(method, path, { token, body } = {}) {
    const headers = {};
    if (token) headers.authorization = `Bearer ${token}`;
    if (body !== undefined) headers["content-type"] = "application/json";
    const res = await fetch(url + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* not JSON */ }
    return { status: res.status, json, text };
}

async function authenticate(id) {
    const { privateKey, publicKey } = identity(id);
    const challenge = randomBytes(32);
    const signature = sign(null, challenge, privateKey);
    const res = await api("POST", "/v1/auth", { body: { publicKey, challenge: b64(challenge), signature: b64(signature) } });
    if (res.status === 200 && res.json?.token) {
        secretFile(join(KEY_DIR, `${id}.token`), res.json.token);
        return { status: 200, token: res.json.token };
    }
    return { status: res.status, error: res.json?.error ?? res.text.slice(0, 200) };
}

async function login(id) {
    const r = await authenticate(id);
    if (r.status !== 200) { out({ ok: false, step: "auth", ...r }); process.exit(1); }
    return r.token;
}

// The template's sign-up lock restarts the server right after the first account is created, so retry briefly
// across that gap (connection errors and 5xx) instead of reporting it as a failed read.
async function profileId(token) {
    const deadline = Date.now() + 60000;
    for (;;) {
        try {
            const r = await api("GET", "/v1/account/profile", { token });
            if (r.status < 500 || Date.now() > deadline) return { status: r.status, id: r.json?.id ?? null };
        } catch (error) {
            if (Date.now() > deadline) throw error;
        }
        await new Promise((resolve) => setTimeout(resolve, 1000));
    }
}

const commands = {
    async auth() {
        const r = await authenticate(name);
        if (r.status !== 200) return out(r);
        const p = await profileId(r.token);
        out({ status: 200, profileStatus: p.status, accountId: p.id });
    },

    async write() {
        const token = await login(name);
        const metadata = b64(Buffer.from(JSON.stringify({ marker: arg, path: "/workspace/demo" })));
        const s = await api("POST", "/v1/sessions", { token, body: { tag: arg, metadata } });
        const sessionId = s.json?.session?.id ?? null;
        const m = sessionId
            ? await api("POST", `/v2/sessions/${sessionId}/messages`, { token, body: { ciphertext: b64(Buffer.from(`hello ${arg}`)), localId: `local-${arg}` } })
            : { status: 0, json: null };
        const kv = await api("POST", "/v1/kv", { token, body: { mutations: [{ key: `railway-test-${arg}`, value: b64(Buffer.from(arg)), version: -1 }] } });
        out({ sessionStatus: s.status, sessionId, messageStatus: m.status, messageSeq: m.json?.message?.seq ?? null, kvStatus: kv.status, kvVersion: kv.json?.results?.[0]?.version ?? null });
    },

    async verify() {
        const token = await login(name);
        const list = await api("GET", "/v1/sessions", { token });
        const sessions = list.json?.sessions ?? [];
        const session = sessions.find((s) => s.metadata === b64(Buffer.from(JSON.stringify({ marker: arg, path: "/workspace/demo" }))));
        let messageFound = false, messagesStatus = 0;
        if (session) {
            const msgs = await api("GET", `/v1/sessions/${session.id}/messages`, { token });
            messagesStatus = msgs.status;
            messageFound = msgs.text.includes(b64(Buffer.from(`hello ${arg}`)));
        }
        const kv = await api("GET", `/v1/kv/railway-test-${arg}`, { token });
        out({ listStatus: list.status, sessionFound: Boolean(session), messagesStatus, messageFound, kvStatus: kv.status, kvValueMatches: kv.json?.value === b64(Buffer.from(arg)) });
    },

    async socket() {
        const token = await login(name);
        const ws = new WebSocket(`${url.replace(/^http/, "ws")}/v1/updates/?EIO=4&transport=websocket`);
        const result = await new Promise((resolve) => {
            const timer = setTimeout(() => resolve({ connected: false, reason: "timeout" }), 15000);
            ws.onmessage = (ev) => {
                const data = String(ev.data);
                if (data.startsWith("0")) ws.send(`40${JSON.stringify({ token, clientType: "user-scoped" })}`);
                else if (data === "2") ws.send("3");
                else if (data.startsWith("40")) { clearTimeout(timer); resolve({ connected: true }); }
                else if (data.startsWith("44") || data.startsWith("41")) { clearTimeout(timer); resolve({ connected: false, reason: data.slice(0, 120) }); }
            };
            ws.onerror = () => { clearTimeout(timer); resolve({ connected: false, reason: "websocket error" }); };
        });
        try { ws.close(); } catch { /* already closed */ }
        out(result);
    },

    // Terminal pairing (what `happier auth login` does): the machine posts a public key, the signed-in account
    // posts an (encrypted, opaque to the server) response for it, and the machine's next poll receives a token.
    async pair() {
        const token = await login(name);
        const machineKey = b64(randomBytes(32));
        const first = await api("POST", "/v1/auth/request", { body: { publicKey: machineKey, supportsV2: true } });
        const approve = await api("POST", "/v1/auth/response", { token, body: { publicKey: machineKey, response: b64(randomBytes(64)) } });
        const second = await api("POST", "/v1/auth/request", { body: { publicKey: machineKey, supportsV2: true } });
        let machineTokenWorks = false;
        if (second.json?.token) {
            secretFile(join(KEY_DIR, `${arg}.token`), second.json.token);
            const p = await profileId(second.json.token);
            const owner = await profileId(token);
            machineTokenWorks = p.status === 200 && p.id !== null && p.id === owner.id;
        }
        out({ requestState: first.json?.state ?? first.status, responseStatus: approve.status, pairedState: second.json?.state ?? second.status, machineTokenWorks });
    },
};

if (!commands[cmd]) { console.error(`unknown command ${cmd}`); process.exit(2); }
await commands[cmd]();
