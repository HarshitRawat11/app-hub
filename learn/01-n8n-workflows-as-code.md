# 01 — n8n workflows as code, and how to handle a secret you never see

## What we did

Added a fourth component to app-hub: `n8n/`, its own git repo, holding the workflow definitions from your self-hosted n8n instance as version-controlled JSON. Along with it, a script to pull workflows from the n8n API, and a set of rules for using an API key without that key ever appearing in a chat transcript or terminal.

Nothing was pulled from the live instance yet — Docker Desktop wasn't running. That's task `N-04`.

## Why

Two separate problems, worth keeping apart in your head.

**Problem one: workflows built in a GUI have no history.** You drag nodes around in the n8n editor and the result lives in n8n's database. There's no diff, no "what changed last Tuesday", no way to review a change before it goes live, and no recovery if the instance dies. Exporting the JSON into git gives you all four. This is the same instinct behind your `infra/` directory: the cluster isn't the source of truth, the Terraform is. Here, the n8n instance isn't the source of truth — `n8n/workflows/` is.

**Problem two: the API key.** To automate this, something needs credentials to your n8n instance. The naive move is to paste the key into chat so I can use it. That's bad for reasons worth being precise about:

- Chat transcripts are stored and retained. A key pasted once is in that record permanently.
- I might quote it back while explaining something, multiplying the copies.
- Rotating it later means finding every place it landed — and you can't edit a transcript.

The fix isn't "be careful." It's an arrangement where **I can use the key without ever being able to see it.** That's what `n8n/.env` plus shell variable references achieves, and it generalises to every credential this project will ever need.

## Key concepts

**1. Workflows as code.** The GUI is an editing surface; the JSON is the artefact. Once the JSON is in git you get review, history, rollback, and disaster recovery for free. The tradeoff is a sync step — the editor and the repo can drift apart, and you have to remember to pull. That's the cost of a GUI tool that owns its own storage.

**2. n8n separates workflows from credentials, and this is the load-bearing detail.** A workflow export contains credential *references* — an id and a name like `"Google Sheets account"` — but never the secret values. Those are encrypted in n8n's database under a key in `~/.n8n`. That separation is exactly what makes committing workflow JSON safe.

The gap: a secret you typed straight into a node parameter — an API key in an HTTP Request header field, a token in a URL — isn't a credential as far as n8n is concerned. It's just a parameter, and parameters get exported. Hence the grep before every commit. **The rule to internalise: secrets belong in n8n credentials, never in node parameters.**

**3. Environment variables as a privacy boundary.** When a command reads `$N8N_API_KEY`, the shell substitutes the value at execution time, inside the process. What gets written down — in the transcript, in the terminal scrollback, in your shell history — is the literal string `$N8N_API_KEY`. The secret is in the process's memory for the duration of the call and nowhere else.

This is why the rules against `cat .env`, `echo $N8N_API_KEY`, and `curl -v` matter so much. Each of those *defeats the arrangement* — they take the value out of process memory and print it into exactly the durable record we were avoiding. `curl -v` is the sneaky one: it looks like a debugging flag, but it prints every request header, and the API key is a request header.

**4. Least-privilege and revocability.** An n8n API key is all-or-nothing: full read, write, and execute across every workflow. There's no read-only variant. So the mitigations available are an expiry date and fast revocation. Revoking in **Settings → n8n API** is instant and costs you one re-paste into `.env`. If you ever *suspect* exposure, revoke — the cost of being wrong in that direction is trivial.

## Walkthrough

### The scaffold

```
n8n/
├── .gitattributes      # Forces LF line endings
├── .gitignore          # Blocks .env and credential exports
├── .env.example        # Template, committed
├── .env                # Real key, NOT committed
├── workflows/          # One JSON file per workflow
└── scripts/
    └── pull-workflows.sh
```

### `.gitignore`, and why the negation matters

```gitignore
.env
.env.*
!.env.example
```

Line 1 blocks the real file. Line 2 blocks variants (`.env.local`, `.env.prod`). Line 3 is a **negation** — `!` re-includes a file an earlier rule excluded — because `.env.example` matches `.env.*` and we *do* want the template committed. Order matters: a later rule overrides an earlier one, so the negation has to come after the pattern it's undoing.

Also blocked:

```gitignore
credentials/
*credentials*.json
```

`n8n export:credentials` writes actual secrets, and with `--decrypted` writes them in plain text. That command's output must never be near git.

### Verifying the ignore rule *before* trusting it

```bash
git check-ignore -v .env
```

```
.gitignore:2:.env	.env
```

It reports which file, which line number, and which pattern caused the match. That's proof, not hope. Run it before you paste a real key into any new gitignored file — a typo in `.gitignore` is silent, and you'd only find out when the secret was already in a commit.

### The CRLF trap

When first staging the files, git warned:

```
warning: in the working copy of 'scripts/pull-workflows.sh', LF will be replaced by CRLF the next time Git touches it
```

Worth understanding, because it produces one of the most misleading error messages in cross-platform development. Windows ends lines with `\r\n` (CRLF); Linux uses `\n` (LF). Git on Windows often auto-converts. If that happens to a shell script, its first line becomes:

```
#!/usr/bin/env bash\r
```

Linux now looks for an interpreter literally named `bash\r`, doesn't find it, and reports:

```
bash: ./scripts/pull-workflows.sh: /usr/bin/env: bad interpreter: No such file or directory
```

Which points at `/usr/bin/env` — a file that exists and is perfectly fine. People lose real time to this. The fix is one line in `.gitattributes`:

```gitattributes
* text=auto eol=lf
```

Because your project straddles Windows and WSL (`CLAUDE.md § 5`), this will keep coming up. Any repo here containing shell scripts wants this file.

### The pull script, in pieces

```bash
set -a
. ./.env
set +a
```

`set -a` means "automatically export every variable defined from here on." `. ./.env` sources the file — running it in the *current* shell rather than a subshell, so the variables persist. `set +a` turns auto-export off. Net effect: `.env`'s contents become environment variables available to child processes like `curl`. Without `set -a` they'd be shell-local and `curl` wouldn't inherit them.

```bash
: "${N8N_API_KEY:?not set in .env}"
```

Compact and worth knowing. `:` is the no-op builtin. `${VAR:?message}` expands to `$VAR`, but exits with `message` if it's unset or empty. So this asserts the variable exists and fails fast with a clear error otherwise — instead of sending an empty header and getting a confusing 401.

```bash
response=$(curl -sS --fail -H "X-N8N-API-KEY: ${N8N_API_KEY}" "${N8N_BASE_URL}/api/v1/workflows?limit=250")
```

`-s` silences the progress meter, `-S` keeps error messages visible (the two are almost always used together), and `--fail` makes curl exit non-zero on an HTTP error rather than handing back an error page we'd try to parse as workflow JSON. Combined with `set -e` at the top, a failed request stops the script instead of writing garbage.

Note the path: **`/api/v1/`**. n8n also serves `/rest/` — that's the internal API the editor UI talks to. You'll see it in forum answers. Don't build on it: it's not the documented public interface and changes between versions without notice.

```bash
jq 'del(.createdAt, .updatedAt, .versionId)' <<<"$wf" > "$file"
```

This is a small thing with a large payoff. Those three fields change on the server every time a workflow is touched, even when nothing meaningful changed. Left in, every pull produces a diff, and real changes drown in noise. Stripped, an unchanged workflow re-pulls to a byte-identical file and `git status` stays quiet. **Making no-op operations produce no diff is what keeps a generated-file repo reviewable.**

## Gotchas

- **`curl -v` leaks the key.** It prints request headers. So does `curl --trace`. If you need to debug a request, print the *response*, never the request.
- **`git check-ignore` before pasting any secret.** A `.gitignore` typo fails silently and you find out too late.
- **`.env` is not backed up.** It's gitignored by design, which means a fresh clone has no credentials. That's correct — but it also means `.env` is yours to recreate. Keep the key in a password manager, not only on disk.
- **The n8n encryption key is the real single point of failure.** It lives in `~/.n8n`, not in this repo. Lose it and every stored credential becomes undecryptable — the workflows survive, but every connection has to be re-authorised by hand. Back it up somewhere outside the project (`N-05`).
- **Renaming a workflow renames its file.** The script names files `slug-id.json`, so a rename produces a delete plus an add rather than a clean rename in the diff. The id suffix at least keeps the mapping unambiguous.
- **Pull before you edit.** If you change a workflow in the n8n UI and then edit the JSON in the repo, one of the two wins and the other is silently lost. The instance and the repo can always drift; pulling first is the habit that prevents it.

## Verify it yourself

Confirm `.env` is genuinely ignored (should name the rule that catches it):

```bash
cd n8n && printf 'N8N_BASE_URL=x\nN8N_API_KEY=y\n' > .env && git check-ignore -v .env && git status --short && rm .env
```

Check the script parses without running it — `-n` is bash's syntax-only mode, useful for any script you're about to trust:

```bash
bash -n n8n/scripts/pull-workflows.sh && echo "syntax OK"
```

Once `.env` is filled in, confirm the key loads *without printing it*:

```bash
set -a && . ./n8n/.env && set +a && [ -n "$N8N_API_KEY" ] && echo "key is set (${#N8N_API_KEY} chars)"
```

`${#VAR}` gives the length of a variable — enough to confirm it loaded and looks plausible, without revealing the value. A good habit for any secret check.

## Going deeper

- [n8n API authentication](https://docs.n8n.io/api/authentication/) — the `X-N8N-API-KEY` header
- [n8n public API reference](https://docs.n8n.io/api/) — full endpoint list
- [Export and import workflows](https://docs.n8n.io/workflows/export-import/) — including the note that exports carry credential names and IDs
- [n8n CLI commands](https://docs.n8n.io/hosting/cli-commands/) — `export:workflow --all --separate`
- [Custom encryption key](https://docs.n8n.io/hosting/configuration/configuration-examples/encryption-key/) — worth reading before you ever move or rebuild the instance
- [gitattributes and line endings](https://git-scm.com/docs/gitattributes#_end_of_line_conversion) — the CRLF mechanism in detail

---

**Next step:** `N-02` (create the GitHub remote — needs the web UI, since `gh` isn't installed), `N-03` (fill in `.env`), then `N-04` to pull your existing workflow in.
