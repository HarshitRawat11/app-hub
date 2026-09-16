#!/usr/bin/env python3
"""Detect (and fix) documentation that quotes source files and has drifted.

The problem this solves, concretely: CONTEXT-BRIEF.md reproduces
links-service/app/main.py verbatim so that a Claude chat session with no
filesystem access can still see it. On 2026-09-10 the handlers were renamed to
snake_case and the brief was not updated -- so the file whose entire job is to
convey the current state was handing over code that no longer existed. Nothing
caught it, because nothing was looking.

Documentation that describes reality rots every time reality moves. Where the
fact is mechanical -- a verbatim copy of a file -- checking it should be
mechanical too.

USAGE
    python3 scripts/check-doc-drift.py            # check, exit 1 on drift
    python3 scripts/check-doc-drift.py --fix      # rewrite blocks from source

HOW TO EMBED A FILE
Put a marker immediately before a fenced code block. The path is relative to
the repo root:

    <!-- embed: links-service/app/main.py -->
    ```python
    ...contents...
    ```

Anything without a marker is ignored, so prose and illustrative snippets are
untouched. `--fix` replaces only the contents of marked blocks.

A NOTE ON WHAT THIS DELIBERATELY DOES NOT DO
It does not check prose claims ("replicas is 2", "no tests exist yet"). Those
rot just as readily, but the fix there is to stop asserting a fact that will
go stale rather than to write a checker for it -- prefer deleting the rotting
fact. This handles the case where the duplication is genuinely necessary.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Files scanned for embed markers. Add new ones here.
DOCS = ["CONTEXT-BRIEF.md"]

# WHOLE FILES vendored from one place to another, as (source, copy) pairs.
#
# The Netlify site (site/) serves the real dashboard so a visitor can use it
# rather than look at a screenshot. It cannot reference gateway's copy: the
# component directories are SEPARATE git repositories that the umbrella repo
# gitignores, so a Netlify checkout of app-hub contains no gateway/ at all.
#
# Copying is therefore forced by the polyrepo layout. Checking the copy is
# what stops it becoming a lie -- a portfolio page that claims to show the
# real dashboard, showing a version from three months ago, is worse than one
# that shows a screenshot and says so.
COPIES = [
    ("gateway/app/static/style.css", "site/static/style.css"),
    ("gateway/app/static/app.js", "site/static/app.js"),
]

# site/demo.html is NOT a byte copy of gateway's index.html -- it adds the
# demo banner and the stub script tag, so it cannot be. But app.js still
# looks its elements up by id, and an id that exists in one file and not the
# other breaks the demo silently: app.js gets `null`, throws on first use,
# and the page renders empty with nothing in the UI saying why.
#
# So the mechanical part is checked even though the files differ.
DOM_CONTRACT = ("site/static/app.js", "site/demo.html")

GET_BY_ID = re.compile(r"getElementById\(\s*[\"']([^\"']+)[\"']\s*\)")
HTML_ID = re.compile(r"\bid=[\"']([^\"']+)[\"']")


def check_copies(fix: bool) -> int:
    """Byte-compare vendored files. Returns the number of problems."""
    problems = 0
    for src_rel, copy_rel in COPIES:
        src, copy = ROOT / src_rel, ROOT / copy_rel
        if not src.exists():
            print(f"  MISSING source {src_rel}")
            problems += 1
            continue
        want = src.read_bytes()
        if not copy.exists():
            if fix:
                copy.parent.mkdir(parents=True, exist_ok=True)
                copy.write_bytes(want)
                print(f"  FIXED {copy_rel} created from {src_rel}")
            else:
                print(f"  MISSING copy {copy_rel}")
                problems += 1
            continue
        if copy.read_bytes() == want:
            print(f"  ok    {copy_rel}  <-  {src_rel}")
            continue
        if fix:
            copy.write_bytes(want)
            print(f"  FIXED {copy_rel} rewritten from {src_rel}")
        else:
            print(f"  DRIFT {copy_rel} differs from {src_rel}")
            problems += 1
    return problems


def check_dom_contract() -> int:
    """Every id app.js looks up must exist in the demo page."""
    js_rel, html_rel = DOM_CONTRACT
    js, html = ROOT / js_rel, ROOT / html_rel
    if not js.exists() or not html.exists():
        print(f"  SKIP  dom contract: {js_rel} or {html_rel} missing")
        return 0
    wanted = set(GET_BY_ID.findall(js.read_text(encoding="utf-8")))
    present = set(HTML_ID.findall(html.read_text(encoding="utf-8")))
    absent = sorted(wanted - present)
    if absent:
        print(f"  FAIL  {html_rel} is missing element id(s) app.js needs: {absent}")
        print("        app.js would get null and the demo would render empty,")
        print("        with nothing in the page saying why.")
        return 1
    print(f"  ok    {html_rel} has all {len(wanted)} element id(s) app.js looks up")
    return 0

MARKER = re.compile(
    r"<!--\s*embed:\s*(?P<path>[^\s>]+)\s*-->\n"
    r"```(?P<lang>[a-zA-Z0-9]*)\n"
    r"(?P<body>.*?)"
    r"```",
    re.DOTALL,
)


def main() -> int:
    fix = "--fix" in sys.argv
    drifted = 0
    checked = 0
    missing = 0

    copy_problems = check_copies(fix) + check_dom_contract()

    for doc_name in DOCS:
        doc_path = ROOT / doc_name
        if not doc_path.exists():
            print(f"  SKIP  {doc_name} does not exist")
            continue

        text = doc_path.read_text(encoding="utf-8")
        replacements = []

        for match in MARKER.finditer(text):
            rel = match.group("path")
            source = ROOT / rel
            checked += 1

            if not source.exists():
                print(f"  FAIL  {doc_name}: embeds {rel}, which does not exist")
                missing += 1
                continue

            want = source.read_text(encoding="utf-8").rstrip("\n") + "\n"
            have = match.group("body")

            if have == want:
                print(f"  ok    {doc_name}  <-  {rel}")
                continue

            drifted += 1
            print(f"  DRIFT {doc_name}  <-  {rel}")
            if not fix:
                # Show the first differing line, which is usually enough to
                # recognise what changed without dumping both files.
                hl, wl = have.splitlines(), want.splitlines()
                for i in range(max(len(hl), len(wl))):
                    h = hl[i] if i < len(hl) else "<end of block>"
                    w = wl[i] if i < len(wl) else "<end of file>"
                    if h != w:
                        print(f"          first difference at line {i + 1}")
                        print(f"            doc:    {h.strip()!r}")
                        print(f"            source: {w.strip()!r}")
                        break

            replacements.append((match.start("body"), match.end("body"), want))

        if fix and replacements:
            for start, end, want in reversed(replacements):
                text = text[:start] + want + text[end:]
            doc_path.write_text(text, encoding="utf-8", newline="")
            print(f"  FIXED {doc_name}: rewrote {len(replacements)} block(s) from source")

    print()
    if copy_problems:
        print(f"{copy_problems} vendored-copy problem(s).")
        print("Run: python3 scripts/check-doc-drift.py --fix")
        return 1
    if missing:
        print(f"{missing} embedded path(s) do not exist — fix the marker, not the block")
        return 1
    if drifted and not fix:
        print(f"{drifted} of {checked} embedded block(s) have drifted.")
        print("Run: python3 scripts/check-doc-drift.py --fix")
        return 1
    if drifted and fix:
        print(f"Rewrote {drifted} block(s). Review the diff before committing.")
        return 0

    print(f"{checked} embedded block(s), none drifted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
