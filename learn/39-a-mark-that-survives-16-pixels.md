# 39 — A mark that survives 16 pixels  ·  *delegated, short note*

## What it does

app-hub has a real logo now, replacing the inline data-URI emoji (`🗂️`) that
had been standing in as a favicon on all four pages — the dashboard, the
landing page, the demo and the 404.

The mark is a **hub with four spokes** — the name, drawn — with its core in the
accent green. It ships in four forms, all generated from one geometry defined
once in a script:

| File | What it is for |
|---|---|
| `logo.svg` | Display cut. Hairline spokes, half opacity. For 24px and up |
| `icon.svg` | Favicon cut. Thicker spokes, full opacity. Survives 16px |
| `icon-32.png` | Safari, which does not support SVG favicons at all |
| `icon-180.png` | `apple-touch-icon` — the phone home-screen icon over the tailnet |

Both copies live in `gateway/app/static/` and `site/static/`, byte-identical.
The visible mark in the dashboard header and the site hero is **inline SVG in
the markup**, not an `<img>`.

## Why it is this way

**The core is the accent green on purpose.** It is the same `--accent` token as
the liveness dot on every row of the dashboard, so the thing in the middle of
the mark is the thing the page is actually about. Not decoration — the one
colour decision carries the meaning.

**Two cuts, because one geometry cannot serve both ends of the scale.** The
display cut's spokes are 1.9 units in a 32-unit box at 50% opacity. At a 16px
favicon that is **under one device pixel**, and it renders as grey mush. The
icon cut thickens them to 2.4 at full opacity. Same four nodes, same core,
different weight — a logo that needs a separate small-size cut is normal, not a
design failure.

**Inline rather than `<img src="logo.svg">`** so the header mark inherits
`currentColor` and `var(--accent)` from the tokens already in the stylesheet.
An `<img>` is an opaque document: it would need its own hardcoded palette plus a
second copy of the dark-mode rules, and those two copies would drift. Inline,
light and dark work with no extra code at all. The **standalone** files cannot
inherit anything, so they carry their own `prefers-color-scheme` block with both
palettes written out.

**The size was set by looking, not by matching numbers.** At `1.15rem` — equal
to the wordmark's font-size — the mark read noticeably *smaller*, because a
sparse shape of dots and gaps carries less optical weight than solid letterforms
in the same box. `1.4rem` balances it. There is no formula; it needed a
screenshot.

## The one thing to know

**The page was rendered once with its stylesheet failing to load, by accident —
and that accident found two bugs that reading the markup never would have.**

1. **`fill="var(--accent)"` with no value defined falls back to BLACK.** The one
   meaningful colour in the mark silently disappeared, and the result still
   looked like a deliberate logo — a plain black graphic, no error, nothing in
   the console. It is now `var(--accent, #2f6f4f)`.

2. **An SVG with no `width`/`height` attributes and no CSS expands to fill its
   container.** The mark took the entire viewport. The attributes are now a
   floor; the stylesheet still wins whenever it loads.

Both are the project's recurring disease in a new costume: **a failure that
renders as something plausible instead of as an error.** The same family as a
`401` parsed into *"0 workflows"* (`learn/38`), a wrong `--query` returning
`None` rather than erroring, and a `/health` endpoint that reported healthy
through a two-week data-path outage.

So: **render the degraded case on purpose.** For a stylesheet that is one
missing file away from happening in production, "it looks right when everything
loads" is not the test.

A smaller note in the same spirit — the standalone SVGs are asserted to contain
**no `var(` at all**, because a CSS variable in a file that has no page context
is exactly the bug above, permanently.
