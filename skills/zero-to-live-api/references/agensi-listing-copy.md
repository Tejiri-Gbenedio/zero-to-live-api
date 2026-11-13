# Agensi Marketplace Listing Copy: Zero-to-Live API Architect

Use this complete copy directly in your Agensi Creator Dashboard when publishing the skill.

---

## Quick Metadata

* **Product Title:** Zero-to-Live API Architect
* **Slug / Handle:** `zero-to-live-api`
* **Author / Creator:** Chijioke Elvis Anonize
* **Tagline:** Turn Plain English & UI Mockups into Bulletproof, Self-Healing Serverless Backends.
* **Suggested Price:** **$29** (One-Time) or **$9/month**
* **Category:** Developer Tools / Backend Development
* **Compatible Runtimes:** Claude Code, OpenAI Codex CLI, Cursor, Antigravity

### Search Tags (Comma-separated)
`api-builder`, `serverless`, `hono`, `nextjs`, `rest-api`, `zod-validation`, `self-healing`, `vibe-coding`, `backend-agent`, `claude-code`, `antigravity`, `cursor`

---

## Short Description (Under 200 Characters)
> Turn any AI coding agent into an autonomous senior backend architect. Builds, tests, secures, and verifies serverless APIs in plain English with zero backend code required.

---

## Full Marketplace Markdown Description

# Stop Letting Backend Setup Stall Your Vibe-Coding Momentum

You just built a stunning frontend in React, Next.js, or HTML using AI. But the moment you need to **save form submissions, process user orders, secure webhooks, or store data**, everything screeches to a halt:
- AI hallucinating broken endpoints and mismatched JSON schemas.
- Silent failures when forms submit because of missing CORS headers.
- Zero input validation leaving your backend open to garbage data or security exploits.
- Hours spent wrestling with port conflicts, serverless config files, and deployment errors.

**Meet Zero-to-Live API Architect (`zero-to-live-api`).**

The industry's first autonomous backend protocol with a **Self-Healing Verification Loop**. It discovers your data needs without technical jargon, scaffolds edge-ready TypeScript endpoints, validates its own code with automated test scripts, and hands you a one-line frontend bridge.

---

## How It Works (The 4-Step Protocol)

```
[Plain-English Discovery] ──▶ [Auto-Scaffolding] ──▶ [Self-Healing Tests] ──▶ [1-Line Client Bridge]
  (Zero Jargon, 3 Qs Max)       (Hono / Next.js)       (verify-api.sh)          (api.records.create)
```

1. **Jargon-Free Discovery:** It scans your existing UI or asks at most 3 human questions ("What information do you want to save? Who should see it?").
2. **Production Scaffolding:** Generates production-grade Hono (Vercel Edge / Cloudflare Workers) or Next.js App Router API routes equipped with strict Zod validation, rate limiting, and CORS.
3. **Autonomous Self-Healing Loop:** The agent boots a local test server, runs `verify-api.sh` and `security-check.sh`, captures error logs, and automatically patches its own route handlers until 100% of tests pass.
4. **Zero-Config Frontend Bridge:** Generates an `api-client.ts` file so your frontend can submit and query data with a single line of code (`await api.records.create(data)`).

---

## Before & After

| Challenge | Without `zero-to-live-api` | With `zero-to-live-api` |
| :--- | :--- | :--- |
| **Discovery** | Confusing queries about ORMs, DB relations, and verbs. | Inspects your UI or asks 3 plain-English questions. |
| **Validation** | Missing or hand-waved payload parsing. | Strict, type-safe Zod schema validation with clear 400 errors. |
| **Testing** | "I wrote the code, you test it yourself." | Autonomous loop with bash scripts fixing bugs until 100% green. |
| **Security** | Unsafe `*` CORS, exposed `.env` files, no rate limits. | Automated `security-check.sh` pre-flight audit enforcing best practices. |
| **Frontend Hookup** | Messy, repetitive `fetch()` boilerplate in UI files. | Single typed `api.<entity>.<action>()` client ready to import. |

---

## What’s Included in the Bundle

- **`SKILL.md` Core Instructions:** Lean, deterministic operational rules conforming to the `agentskills.io` standard.
- **`scripts/verify-api.sh`:** POSIX-compliant automated testing engine verifying GET, POST, validation rejections (400), and CORS preflights.
- **`scripts/security-check.sh`:** Secret scanner and CORS/Zod enforcement script.
- **`references/hono-vercel-blueprint.md`:** Serverless edge backend pattern with Hono & Vercel.
- **`references/nextjs-api-blueprint.md`:** Next.js 14/15 App Router route handler pattern.
- **`references/frontend-bridge-template.md`:** Zero-dependency, isomorphic TypeScript & JavaScript client bridges.

---

## Compatibility

Works out-of-the-box with all leading AI agent environments:
- **Claude Code** (`~/.claude/skills/zero-to-live-api`)
- **OpenAI Codex CLI** (`~/.agents/skills/zero-to-live-api`)
- **Antigravity** (`~/.gemini/config/skills/zero-to-live-api`)
- **Cursor** (`.cursorrules` & skill folder)

---

## FAQ

**Q: Do I need to know TypeScript or backend architecture?**
No. The skill is specifically designed for non-technical creators and vibe-coders. It asks you questions in plain English and writes production-grade code for you.

**Q: Can I use this with an existing frontend?**
Yes! The skill prioritizes scanning your existing UI components, forms, and fetch calls to automatically deduce and generate the exact endpoints your frontend needs.

**Q: How does the self-healing loop work?**
The agent executes the bundled `verify-api.sh` script against a local server instance. If an endpoint throws an error or fails validation, the agent reads the terminal output, patches the code, and re-tests until all endpoints return 200/201 or 400 as expected.

