#!/usr/bin/env python3
"""Put the owner's other projects into the REAL links catalogue.

site/projects.json is the one source of truth for those four links. The landing
page renders from it and the demo catalogue merges from it; this is the third
reader, and the only one that writes to a live service.

USAGE
    # with a cluster up, through a port-forward:
    kubectl -n app-hub port-forward svc/gateway 8001:8001 &
    python3 scripts/seed-projects.py

    # or against anything else that speaks the same API:
    python3 scripts/seed-projects.py --base http://localhost:8001
    python3 scripts/seed-projects.py --dry-run

WHY THROUGH gateway AND NOT STRAIGHT AT links-service
gateway is the public entry point and the thing that will still exist after
E-06 makes links-service ClusterIP-only. Writing straight to links-service
would work today and break the moment that lands.

WHY NOT boto3 STRAIGHT INTO DynamoDB
It would be fewer moving parts and it would bypass the API's own validation and
id generation -- so a malformed record would land in the table and only fail
later, at read time, in a service that had no say in accepting it. Write
through the front door.

IDEMPOTENT BY NAME. Re-running adds nothing. Names are compared rather than
ids, because ids are server-generated UUIDs: this script cannot know in advance
what a record's id will be, so it has no other stable handle. The consequence
worth knowing is that RENAMING a project in projects.json makes the next run
create a second record rather than updating the first.

AND THAT IDEMPOTENCY HID A REAL DRIFT, on 2026-09-27. `projects.json` was
corrected on 2026-09-20 to move two projects off dead URLs. Re-running this
script afterwards printed `skip -- already in the catalogue` for both and exited
0, because the NAMES still matched. The catalogue went on serving a URL that
returns 404 for a week, and the script that exists to sync it reported success
every time.

So a name match is no longer sufficient. The URL is compared too:

  same name, same url   -> skip, as before
  same name, DIFFERENT  -> DRIFT. Reported loudly, and the script exits
     url                   NON-ZERO so it cannot pass in CI or be mistaken for
                           a clean run. Pass --sync to actually fix it.

--sync repairs drift by DELETE then POST, because the API has no update verb --
GET, POST and DELETE only. That is not a workaround for a missing feature; the
record genuinely gets a new id, and anything holding the old id will not find
it. Nothing does today, but say so rather than pretending it is an update.
"""

import argparse
import json
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECTS = ROOT / "site" / "projects.json"

# THE PRIVATE OVERLAY, and it is gitignored on purpose.
#
# `public:false` decides where an entry may APPEAR. It never decided whether
# the URL gets COMMITTED, and site/projects.json lives in a PUBLIC repo. Two
# links carried an account id and an org id in their paths, so the flag was
# protecting the page while the repository published the URL anyway.
#
# Splitting the file makes that protection structural rather than remembered.
# The browser never loads this one: the landing page and the demo both fetch
# projects.json only, and both additionally filter on public:true.
#
# ABSENT IS NORMAL, NOT AN ERROR. A fresh clone has no private links.
PROJECTS_LOCAL = ROOT / "site" / "projects.local.json"
# FALLBACK ONLY. Each entry in projects.json now carries its own category,
# which decides the column it appears under on the dashboard. This value is
# used for entries written before that field existed, so an old file still
# seeds rather than crashing.
CATEGORY = "projects"
DEFAULT_ICON = "\U0001F9F1"


def request(method, url, body=None, timeout=10):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url, data=data, method=method,
        headers={"Content-Type": "application/json"} if data else {},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
        return resp.status, (json.loads(raw) if raw else None)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", default="http://localhost:8001",
                    help="gateway base URL (default: %(default)s)")
    ap.add_argument("--dry-run", action="store_true",
                    help="show what would be created, write nothing")
    ap.add_argument("--sync", action="store_true",
                    help="repair drift: when a name exists with a different URL, "
                         "DELETE the record and re-create it. Without this, drift "
                         "is reported and the script exits non-zero.")
    args = ap.parse_args()
    base = args.base.rstrip("/")

    if not PROJECTS.exists():
        print(f"ERROR: {PROJECTS} does not exist")
        return 1

    data = json.loads(PROJECTS.read_text(encoding="utf-8"))

    # Merge the private overlay, if it exists. Reported either way -- a silent
    # zero here would look exactly like a file that failed to parse.
    if PROJECTS_LOCAL.exists():
        local = json.loads(PROJECTS_LOCAL.read_text(encoding="utf-8"))
        extra = local.get("projects", [])
        leaked = [x["name"] for x in extra if x.get("public")]
        if leaked:
            # Refuse rather than repair. A public:true entry in the private
            # file would render on the portfolio page while living in a file
            # nobody else has -- so the site would differ per machine.
            print(f"ERROR: {PROJECTS_LOCAL.name} contains public:true entries: {leaked}")
            print("       Those belong in site/projects.json. Nothing was written.")
            return 1
        data["projects"] = data.get("projects", []) + extra
        print(f"  merged {len(extra)} private entr(ies) from {PROJECTS_LOCAL.name}")
    else:
        print(f"  no {PROJECTS_LOCAL.name} -- public entries only")
    entries = data.get("projects", [])

    # NOTE THIS DOES NOT FILTER ON `public`, and that is deliberate.
    #
    # The landing page and the demo catalogue both skip non-public entries,
    # because both are served to strangers. This one writes into the OWNER'S
    # OWN start page, where a localhost dev server or a personal notes account
    # is exactly the kind of link that belongs -- that is what a start page is
    # for. Filtering here would strip out three of the four and quietly defeat
    # the point.
    #
    # A project with no URL is still not ready. Reported rather than skipped in
    # silence -- "nothing happened" and "nothing was ready" are different
    # facts, and a seeder that prints neither is one you stop trusting.
    ready = [p for p in entries if p.get("url")]
    pending = [p["name"] for p in entries if not p.get("url")]
    if pending:
        print(f"  pending (no url in projects.json): {', '.join(pending)}")
    if not ready:
        print("  nothing to seed -- every project is still waiting for a URL")
        return 0

    try:
        status, existing = request("GET", f"{base}/links")
    except urllib.error.URLError as e:
        print(f"ERROR: cannot reach {base}/links -- {e}")
        print("       Is the cluster up and the port-forward running?")
        print("       kubectl -n app-hub port-forward svc/gateway 8001:8001")
        return 1
    if status != 200:
        print(f"ERROR: GET /links returned {status}")
        return 1

    # name -> the whole record, not just the name, so the URL can be compared.
    # Comparing only names is what let a dead URL sit in the catalogue for a
    # week while this script reported success -- see the module docstring.
    have = {link["name"]: link for link in existing}
    created = skipped = drifted = repaired = 0

    for p in ready:
        current = have.get(p["name"])
        if current is not None:
            want_cat = p.get("category") or CATEGORY
            if current.get("url") == p["url"] and current.get("category") == want_cat:
                print(f"  skip   {p['name']} -- already in the catalogue")
                skipped += 1
                continue

            # Same name, different URL. THIS IS THE CASE THAT USED TO BE
            # SILENT.
            # Report BOTH fields, not just the one that differs. Printing only
            # the URL when the category moved would show two identical lines and
            # read as a bug in the checker rather than a category change.
            print(f"  DRIFT  {p['name']}")
            print(f"           catalogue:     url={current.get('url')} category={current.get('category')}")
            print(f"           projects.json: url={p['url']} category={want_cat}")
            if not args.sync:
                drifted += 1
                continue
            if args.dry_run:
                print(f"         would delete {current['id']} and re-create")
                repaired += 1
                continue
            try:
                status, _ = request("DELETE", f"{base}/links/{current['id']}")
            except urllib.error.HTTPError as e:
                print(f"  FAIL   {p['name']} -- DELETE HTTP {e.code}")
                return 1
            if status not in (200, 204):
                print(f"  FAIL   {p['name']} -- DELETE returned {status}")
                return 1
            print(f"         deleted {current['id']}")
            repaired += 1
            # fall through to the create below
        record = {
            "name": p["name"],
            "url": p["url"],
            "category": p.get("category") or CATEGORY,
            "icon": p.get("icon") or DEFAULT_ICON,
        }
        if args.dry_run:
            print(f"  would create  {record['name']} -> {record['url']}")
            created += 1
            continue
        try:
            status, body = request("POST", f"{base}/links", record)
        except urllib.error.HTTPError as e:
            print(f"  FAIL   {p['name']} -- HTTP {e.code} {e.read()[:200]!r}")
            return 1
        if status != 201:
            print(f"  FAIL   {p['name']} -- expected 201, got {status}")
            return 1
        print(f"  create {p['name']} -> {body['id']}")
        created += 1

    if drifted:
        print()
        print(f"DRIFT: {drifted} record(s) differ from projects.json and were NOT fixed.")
        print("Re-run with --sync to repair them. Exiting non-zero so this cannot")
        print("be mistaken for a clean run -- which is exactly how a dead URL sat")
        print("in the catalogue from 2026-09-20 to 2026-09-27.")
        return 1

    # Report repairs separately. A summary reading "created 0" while a record
    # was in fact replaced is the same misleading-report pattern this script was
    # just fixed for -- a clean-looking line over a real change.
    if repaired:
        rverb = "would repair" if args.dry_run else "repaired"
        print(f"  {rverb} {repaired} drifted record(s)")

    verb = "would create" if args.dry_run else "created"
    print(f"\n{verb} {created}, skipped {skipped} already present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
