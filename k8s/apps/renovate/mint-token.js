// Self-hosted Renovate can't authenticate with a GitHub App key directly; it
// needs an installation token, which GitHub expires after an hour. An init
// container runs this each time, so the App key never reaches Renovate itself.
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const [appDir, tokenFile] = process.argv.slice(2);
const read = (name) => fs.readFileSync(path.join(appDir, name), "utf8").trim();
const clientId = read("GITHUB_APP_CLIENT_ID");
const installationId = read("GITHUB_APP_INSTALLATION_ID");
const privateKey = read("GITHUB_APP_PRIVATE_KEY");

const b64url = (s) => Buffer.from(s).toString("base64url");
const now = Math.floor(Date.now() / 1000);
const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
// iat is backdated to absorb clock skew between the node and GitHub.
const payload = b64url(JSON.stringify({ iat: now - 60, exp: now + 540, iss: clientId }));
const signature = crypto.sign("RSA-SHA256", Buffer.from(`${header}.${payload}`), privateKey).toString("base64url");

fetch(`https://api.github.com/app/installations/${installationId}/access_tokens`, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${header}.${payload}.${signature}`,
    Accept: "application/vnd.github+json",
  },
})
  .then(async (res) => {
    const body = await res.json();
    if (!res.ok) throw new Error(`installation token request failed: ${res.status} ${body.message}`);
    fs.writeFileSync(tokenFile, body.token, { mode: 0o400 });
  })
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
