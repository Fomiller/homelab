// Self-hosted Renovate can't authenticate with a GitHub App key directly; it
// needs an installation token, which GitHub expires after an hour. Each run
// mints a fresh one from the App key and prints it for RENOVATE_TOKEN.
const crypto = require("node:crypto");

const { GITHUB_APP_CLIENT_ID, GITHUB_APP_INSTALLATION_ID, GITHUB_APP_PRIVATE_KEY } = process.env;

const b64url = (s) => Buffer.from(s).toString("base64url");
const now = Math.floor(Date.now() / 1000);
const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
// iat is backdated to absorb clock skew between the node and GitHub.
const payload = b64url(JSON.stringify({ iat: now - 60, exp: now + 540, iss: GITHUB_APP_CLIENT_ID }));
const signature = crypto.sign("RSA-SHA256", Buffer.from(`${header}.${payload}`), GITHUB_APP_PRIVATE_KEY).toString("base64url");

fetch(`https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens`, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${header}.${payload}.${signature}`,
    Accept: "application/vnd.github+json",
  },
})
  .then(async (res) => {
    const body = await res.json();
    if (!res.ok) throw new Error(`installation token request failed: ${res.status} ${body.message}`);
    process.stdout.write(body.token);
  })
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
