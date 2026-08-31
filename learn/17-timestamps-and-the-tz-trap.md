# 17 — Timestamping the project, and the timezone bug that broke it twice

## What we did

Added `TIMELINE.md`, generated from git history across all five repositories by `scripts/timeline.sh`, so the project's chronology is *derived* rather than typed. Corrected a one-day drift in `PROGRESS.md`, and recorded a timestamp convention in `CLAUDE.md § 7`.

Along the way the timestamp system itself produced wrong timestamps — twice — which is most of the lesson.

## Why

The request was to track *when* decisions and tasks happened. The naive approach is to type dates into `PROGRESS.md`. The problem with that showed up immediately:

**`PROGRESS.md` said `2026-08-29` in 36 places. Git said the work happened on `2026-08-30`.** A full day out, written from memory across several sessions, never noticed.

That is the argument for the whole design: **anything hand-typed drifts. Git already records the truth for free.**

## Key concepts

### 1. Derive, don't duplicate

Git stamps every commit with an absolute instant. A timestamp scheme that re-records that by hand is not adding information — it is adding a second source that can disagree with the first.

So the design is three layers, and only the middle one is written by a human:

| Layer | What | Maintained by |
|---|---|---|
| Git commits | The truth | Automatic |
| `TIMELINE.md` | Chronology across all 5 repos | `scripts/timeline.sh` |
| `PROGRESS.md` | Narrative, status, reasoning | Human, anchored to git |

The rule that falls out: **`TIMELINE.md` is authoritative; `PROGRESS.md` carries the story. If they disagree, the timeline wins.**

### 2. `%at` is an instant; local time is a rendering

Git stores two things per commit: an absolute UTC epoch (`%at`) and the committer's offset at the time.

That distinction matters because commits here come from two shells with different clocks. The epoch is unambiguous; the *displayed* time depends entirely on who is rendering it. So the generator reads `%at` and converts once, to a single chosen zone — rather than trusting whatever `--date=local` happens to produce.

### 3. The bug: Git Bash silently ignores `TZ`

The first version used `TZ=Asia/Kolkata date -d "@$epoch"`. Reasonable, and correct on Linux. On this machine:

```
=== Git Bash ===
  bare date:        2026-08-31 16:17 IST
  TZ=Asia/Kolkata:  2026-08-31 10:47 GMT      ← ignored the request, fell back to GMT
  TZ=UTC:           2026-08-31 10:47 GMT

=== WSL ===
  bare date:        2026-08-31 10:47 UTC
  TZ=Asia/Kolkata:  2026-08-31 16:17 IST      ← correct
```

Git Bash's bare `date` knows it is IST. Ask it for `Asia/Kolkata` explicitly and it **silently gives you GMT instead** — no error, no warning.

I ran the generator from Git Bash. Every timestamp in `TIMELINE.md` was **UTC wearing an "IST" label — 5.5 hours wrong.** Then I derived the `PROGRESS.md` session headers from that output, propagating the error into a second file.

**The failure mode to internalise: a silent fallback is worse than an error.** A missing tz database that *failed* would have been caught in seconds. One that quietly substitutes GMT produces plausible-looking output that is simply wrong.

### 4. The fix: arithmetic beats lookup

IST is UTC+05:30 and **never observes DST**, so the offset is a constant. Shift the epoch and format as UTC — which both shells handle identically:

```bash
IST_OFFSET=19800   # 5.5 * 3600
to_ist() { TZ=UTC date -d "@$(( $1 + IST_OFFSET ))" '+%Y-%m-%d %H:%M'; }
```

This depends on no tz database and no shell-specific behaviour.

The trade-off is honest: it is only correct for zones without DST. For a zone that observes it, you *need* the tz database and must ensure the shell honours it. IST does not, so a constant is exactly right here.

### 5. A self-check turns a silent bug into a loud one

The real fix is not the arithmetic — it is refusing to run when the conversion is wrong:

```bash
_expect="2023-11-15 03:43"
_check=$(to_ist 1700000000)
if [[ "$_check" != "$_expect" ]]; then
  echo "error: timezone conversion is broken (got '$_check', expected '$_expect')" >&2
  exit 1
fi
```

A known epoch must render as a known time, or the script exits. If it ever runs somewhere with different date semantics, it fails loudly rather than emitting confident nonsense.

**This immediately caught a second bug — my own.** The first constant I wrote was `03:40`, off by three minutes, and the guard refused to run. I had guessed the expected value instead of computing it:

```
error: timezone conversion is broken (got '2023-11-15 03:43', expected '2023-11-15 03:40')
```

The guard worked exactly as intended — on its author. Cross-checking against WSL's tz database confirmed `03:43:20` was right and my expectation was wrong.

**When you write an assertion, derive the expected value. Do not guess it.** A wrong assertion is worse than none: it either blocks correct code or, if you "fix" the code to match, enshrines the error.

### 6. The real portability test: same input, two shells, same output

```bash
./scripts/timeline.sh                   # Git Bash
cp TIMELINE.md /tmp/tl-gitbash.md
wsl -e bash -lc "./scripts/timeline.sh" # WSL
diff -q /tmp/tl-gitbash.md TIMELINE.md
```

Byte-identical output from both shells is the proof that the conversion no longer depends on its environment. Before the fix, the same script produced files 5.5 hours apart depending on who ran it.

## Walkthrough — the convention

**Format:** `YYYY-MM-DD HH:MM IST` in prose and table cells. Session headers use `### YYYY-MM-DD · HH:MM–HH:MM IST — title`.

**Always name the zone.** A bare `14:53` in this project is genuinely ambiguous — Windows would read it as IST, WSL as UTC.

**Prefix estimates with `~`** when there is no commit to anchor to, rather than inventing precision. Three of the earliest session headers use `~` because they predate the umbrella repo.

**Never type a date from memory.** Look it up:

```bash
git log --pretty='%h %ad %s' --date=format:'%Y-%m-%d %H:%M' -1 <sha>
```

**Regenerate after every session:**

```bash
./scripts/timeline.sh
```

## Gotchas

- **Git Bash ignores `TZ` and falls back to GMT.** Silently. Do not trust `TZ=<zone>` in scripts that might run there.
- **Correcting derived data means correcting everything downstream.** The bad timeline had already been copied into eight `PROGRESS.md` session headers, which all needed the same +5:30 shift — and two of them moved into the *next day*.
- **`#` is a terrible sed delimiter for markdown.** `sed 's#.*#### heading#'` collides with `###` headings and blanked four lines before I noticed. Use `|`.
- **Backticks in shell command substitution eat markdown.** Passing a line containing `` `D-05` `` through `$(...)` executed it as a command and produced an empty cell. Round-trip such text through a file, or use a tool that does not go via the shell.
- **The offset trick is DST-unsafe.** Correct for IST; wrong for any zone that shifts.

## Verify it yourself

Confirm your shell's `TZ` handling before trusting any timestamp it produces:

```bash
echo "bare: $(date '+%H:%M %Z')  |  TZ=Asia/Kolkata: $(TZ=Asia/Kolkata date '+%H:%M %Z')"
```

If those disagree about the zone name, `TZ` is not being honoured.

Prove the generator is shell-independent:

```bash
./scripts/timeline.sh && cp TIMELINE.md /tmp/a.md && wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub && ./scripts/timeline.sh" && diff -q /tmp/a.md TIMELINE.md && echo IDENTICAL
```

Check the self-check actually fires by breaking it deliberately — change `IST_OFFSET` to `0` and run it. It should refuse.

## Going deeper

- [`gitattributes` and `git log` date formats](https://git-scm.com/docs/git-log#Documentation/git-log.txt---dateltformatgt) — `%at`, `%ad`, `--date=format-local`
- [tzdata and DST](https://www.iana.org/time-zones) — why zones needing DST cannot use a constant offset
- [Falsehoods programmers believe about time](https://gist.github.com/timvisee/fcda9bbdff88d45cc9061606b4b923ca) — a long list, several of which this file hit

---

**The meta-lesson:** the system built to stop timestamps drifting produced drifted timestamps on its first two runs. It only became trustworthy once it could **check itself and refuse to run when wrong**. Generated data is not automatically correct — it is correct only when something verifies it.
