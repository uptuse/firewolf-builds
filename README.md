# firewolf-builds

**Public artefacts mirror for the private [`firewolf-game`](https://github.com/uptuse/firewolf-game) source repo.**

Compiled wasm bundle only; no game source code is published here.

## Contents

| File | Description |
|---|---|
| `dist/firewolf_client.js` | wasm-bindgen JS glue (~100 KB) |
| `dist/firewolf_client_bg.wasm` | Compiled Bevy/Rust wasm bundle (~44 MB) |
| `dist/firewolf_client.d.ts` | TypeScript declarations for the JS glue |
| `dist/firewolf_client_bg.wasm.d.ts` | TypeScript declarations for the wasm module |

## Why this exists

The Firewolf tracker dashboard (`firewolf-tracker`) serves its `/play` page from a
Manus-hosted domain. The Manus platform applies a Cloudflare/org-policy gateway to
every path on that domain, redirecting unauthenticated requests to `manus.im/app-auth`.
`WebAssembly.compileStreaming` cannot follow OAuth 302 redirects, so the wasm bundle
must be served from a public host outside Manus.

This repo is that host. GitHub Pages serves the `dist/` folder with correct MIME types
(`application/wasm` for `.wasm`, `application/javascript` for `.js`) and no auth gate.

## GitHub Pages URLs

- JS glue: `https://uptuse.github.io/firewolf-builds/firewolf_client.js`
- Wasm bundle: `https://uptuse.github.io/firewolf-builds/firewolf_client_bg.wasm`

## Automated updates

The private `firewolf-game` CI workflow (`.github/workflows/wasm-build.yml`) pushes new
builds here automatically on every successful push to `main`. The push uses a
fine-grained PAT stored as `BUILDS_MIRROR_TOKEN` in the private repo's secrets.

## Security note

The compiled wasm bundle is world-readable. The game source code (Rust, Bevy) remains
private in `uptuse/firewolf-game`. If the bundle's public availability is a concern,
the repo owner can delete this repo or make it private at any time; the artefacts are
recoverable from `firewolf-game`'s `gh-pages` branch.

---

*Authored 2026-05-18 by Worker BLDPUB1 per dispatch `builds-public-mirror.md`.*
