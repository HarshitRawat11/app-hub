# 38 — Migrating a volume that holds an encryption key  ·  *delegated, short note*

## What it does

Moves the running n8n instance from a standalone `docker run` container onto the
Compose stack (`N-06` / `G5`), keeping the same `n8n_data` volume. Closes the
`0.0.0.0:5678` publish — the automation admin UI, holding every credential on the
instance, was reachable from anything on the local network. Under Compose it
publishes nothing and is reached only through Tailscale, tailnet-only on `:8443`.

## Why it is this way

**The whole risk is one line: `external: true`.** Without it Compose creates a
*new, empty* volume named `compose_n8n_data`. n8n starts, finds no config,
generates a **fresh encryption key**, and every stored credential in the old
volume becomes permanently undecryptable. The workflows would still be there and
every credential inside them would be rubble.

So the order was chosen to make that failure impossible rather than unlikely:

1. **Prove Compose attaches the SAME volume, before stopping anything.** The
   running container used `n8n_data`; `docker compose config` resolves to
   `name: n8n_data, external: true`. Checking this afterwards would be checking
   it too late.
2. **Stop first, then back up.** Tarring a live SQLite database copies a file
   mid-write. Stopping the container quiesces it.
3. **Open the backup.** `./config` and `database.sqlite` were confirmed present
   by listing the archive. A backup nobody has looked inside is not a backup.
4. **`docker rm` — never `-v`.** That flag deletes the volume, which is the one
   irreversible mistake available here.

## The one thing to know

**"It started" is not the test, and it is the test people use.** A blank n8n
starts perfectly, serves a healthy UI, and shows your workflows — because the
workflow rows are not encrypted. Only the credentials are. So the instance looks
fine and is quietly ruined.

**The decisive check is the key file's mtime.**

```
config   56 bytes   mode 600   mtime 2026-08-07 06:41:44
```

Seven weeks old, unchanged across the migration. A blank start writes a **new**
key file with **today's** timestamp. Nothing else distinguishes the two cases so
cheaply — not counts, not a healthy UI, not the absence of errors in a log.

Two corroborating signals, neither sufficient alone: n8n **activated both
workflows on boot**, which requires decrypting their credentials; and the row
counts matched the baseline captured beforehand.

**A footnote that cost time.** Verifying through the n8n API reported *"0
workflows"* while the database plainly held 2. The response was `401
Unauthorized`, and a parser doing `.get("data", [])` turned a rejected request
into an empty result. **Check the HTTP status before parsing the body** — the
container logs were the better source the whole time.
