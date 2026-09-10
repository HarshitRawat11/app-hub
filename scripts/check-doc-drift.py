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
