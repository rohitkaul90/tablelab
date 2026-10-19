// deno test supabase/functions/_shared/apple.test.ts
// Proves the client_secret JWT is a well-formed ES256 JWS that Apple's public
// key check would accept: generate a P-256 key, export it as the same PKCS#8 PEM
// the developer portal hands out, sign, then verify with the public half.
import { appleClientSecret, idTokenSubject } from "./apple.ts";

Deno.test("idTokenSubject: reads sub from a base64url JWT payload, null on garbage", () => {
  const payload = btoa(JSON.stringify({ sub: "001234.abcdef.5678", aud: "x" }))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  if (idTokenSubject(`eyJhbGciOiJSUzI1NiJ9.${payload}.sig`) !== "001234.abcdef.5678") throw new Error("sub");
  if (idTokenSubject("not.a.jwt.at.all") !== null) throw new Error("expected null for 4 parts");
  if (idTokenSubject("a.b") !== null) throw new Error("expected null for 2 parts");
  if (idTokenSubject(`h.${btoa("{}")}.s`) !== null) throw new Error("expected null without sub");
});

function b64urlDecode(s: string): Uint8Array<ArrayBuffer> {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
  const out = new Uint8Array(new ArrayBuffer(bin.length));
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function toPem(der: ArrayBuffer): string {
  const b64 = btoa(String.fromCharCode(...new Uint8Array(der)));
  const lines = b64.match(/.{1,64}/g)!.join("\n");
  return `-----BEGIN PRIVATE KEY-----\n${lines}\n-----END PRIVATE KEY-----\n`;
}

Deno.test("appleClientSecret: ES256 JWS with Apple's claims, verifiable by the public key", async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pem = toPem(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const cfg = { keyId: "ABC123DEFG", privateKeyPem: pem, teamId: "TEAM567890", bundleId: "app.tablelab.ios" };
  const now = 1_800_000_000;

  const jwt = await appleClientSecret(cfg, now, 600);
  const [h, p, s] = jwt.split(".");
  const header = JSON.parse(new TextDecoder().decode(b64urlDecode(h)));
  const payload = JSON.parse(new TextDecoder().decode(b64urlDecode(p)));

  if (header.alg !== "ES256" || header.kid !== "ABC123DEFG") throw new Error(`bad header ${h}`);
  if (payload.iss !== "TEAM567890" || payload.sub !== cfg.bundleId) throw new Error("bad iss/sub");
  if (payload.aud !== "https://appleid.apple.com") throw new Error("bad aud");
  if (payload.iat !== now || payload.exp !== now + 600) throw new Error("bad iat/exp");

  const sig = b64urlDecode(s);
  if (sig.length !== 64) throw new Error(`ES256 signature must be raw r||s (64 bytes), got ${sig.length}`);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pair.publicKey,
    sig,
    new TextEncoder().encode(`${h}.${p}`),
  );
  if (!ok) throw new Error("signature did not verify");
});

Deno.test("appleClientSecret: accepts a \\n-escaped PEM (how a secret pasted on one line arrives)", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pem = toPem(await crypto.subtle.exportKey("pkcs8", pair.privateKey)).replace(/\n/g, "\\n");
  const jwt = await appleClientSecret(
    { keyId: "K", privateKeyPem: pem, teamId: "T", bundleId: "b" },
  );
  if (jwt.split(".").length !== 3) throw new Error("not a JWT");
});
