# Graylight NewAPI Audit Skill

OpenClaw skill for Graylight NewAPI audit queries and Volcengine Billing balance checks.

Start with [`SKILL.md`](./SKILL.md). It contains the skill description, required OpenClaw secrets, NewAPI audit endpoints, Volcengine Billing API usage, daily cron guidance, and interactive query examples.

This repository intentionally contains only generic request helpers:

- `scripts/newapi-request.sh` — env-driven NewAPI GET helper returning JSON
- `scripts/volc-billing.py` — env-driven Volcengine Billing GET helper with V4 signing
- `scripts/mint-audit-token.sh` — mint an audit token with the NewAPI admin token

It does **not** include fixed daily report or audit aggregation scripts. Report logic is assembled by OpenClaw at runtime from `SKILL.md`.
