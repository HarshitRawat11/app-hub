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
"""

import argparse
import json
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECTS = ROOT / "site" / "projects.json"
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
    args = ap.parse_args()
    base = args.base.rstrip("/")

    if not PROJECTS.exists():
        print(f"ERROR: {PROJECTS} does not exist")
        return 1

    data = json.loads(PROJECTS.read_text(encoding="utf-8"))
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

    have = {link["name"] for link in existing}
    created = skipped = 0

    for p in ready:
        if p["name"] in have:
            print(f"  skip   {p['name']} -- already in the catalogue")
            skipped += 1
            continue
        record = {
            "name": p["name"],
            "url": p["url"],
            "category": CATEGORY,
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

    verb = "would create" if args.dry_run else "created"
    print(f"\n{verb} {created}, skipped {skipped} already present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
