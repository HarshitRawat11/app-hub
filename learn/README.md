# learn/

The learning record for app-hub. One file per step we perform, written so you can redo that step yourself without help.

## Why this exists

This project began as a manual, step-by-step learning exercise with Claude chat. Moving to Claude Code was a decision about **speed**, not about handing over the understanding. So every step taken here gets written up: what we did, why, the concepts underneath it, and how to verify it yourself.

If a file here leaves you unable to explain the step to someone else, it has failed — say so and it gets rewritten.

## How to read this folder

Files are numbered in the order the steps were performed, so reading top to bottom retraces the project. Each one is self-contained enough to read on its own, but later files assume the concepts from earlier ones.

Every file follows the same shape:

| Section | What it gives you |
|---|---|
| **What we did** | The change, in plain terms |
| **Why** | The problem it solves; what breaks without it |
| **Key concepts** | The 2–5 ideas you need to understand it |
| **Walkthrough** | The real code and commands, explained piece by piece |
| **Gotchas** | What bit us, what would bite you next time |
| **Verify it yourself** | Commands to prove it actually works |
| **Going deeper** | Where to read more, if curious |

## Index

| # | File | Covers |
|---|------|--------|
| 00 | [00-project-setup-and-governance.md](00-project-setup-and-governance.md) | Why a project needs CLAUDE.md / README.md / PROGRESS.md, what each is for, and how the three-repo layout and WSL/Windows split shape everything else |
| 01 | [01-n8n-workflows-as-code.md](01-n8n-workflows-as-code.md) | Version-controlling GUI-built workflows; how n8n separates workflows from credentials; using an API key without ever seeing it; the CRLF/`bad interpreter` trap |
| 02 | [02-first-defect-fixes.md](02-first-defect-fixes.md) | A write bug hiding behind a correct response; why `uv` papers over a wrong base image; build-time vs container-start work; Docker layer-cache ordering; per-repo git identity |

*Steps 03 onward get added as we do them.*

## Not yet written up

These were built earlier, by hand with Claude chat, before this folder existed. They can be backfilled on request:

- Terraform project scaffolding and the S3 remote state backend
- The VPC: subnets, internet gateway, NAT gateway
- The EKS cluster and its managed node group
- The ECR repository
- The FastAPI service and its CRUD endpoints
- Containerising with Docker and `uv`
- The Kubernetes Deployment and Service manifests
