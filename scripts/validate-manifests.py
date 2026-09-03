#!/usr/bin/env python3
"""Offline sanity checks for the Kubernetes manifests.

Runs without a cluster, so it is useful when everything is torn down. It checks
the invariants that are easy to break by hand and annoying to debug live:

  * every object declares a namespace
  * the Deployment's selector matches its pod template labels (a mismatch makes
    the Deployment create pods it does not recognise, forever)
  * securityContext is actually set, not just intended
  * resources are present, and reports the resulting QoS class

Usage:  python3 scripts/validate-manifests.py manifests/links-service
"""
import sys
import pathlib
import yaml

BAD = 0


def fail(msg: str) -> None:
    global BAD
    BAD += 1
    print(f"   FAIL  {msg}")


def check(directory: str) -> None:
    files = sorted(pathlib.Path(directory).glob("*.yaml"))
    if not files:
        fail(f"no yaml files in {directory}")
        return

    print(f"apply order in {directory} (kubectl sorts by filename):")
    for f in files:
        print(f"   {f.name}")
    print()

    for f in files:
        doc = yaml.safe_load(f.read_text(encoding="utf-8"))
        kind = doc["kind"]
        meta = doc["metadata"]
        ns = meta["name"] if kind == "Namespace" else meta.get("namespace")
        print(f"{f.name}  ->  {kind}  namespace={ns}")

        if kind != "Namespace" and not ns:
            fail(f"{f.name}: no namespace declared, would land in 'default'")

        if kind != "Deployment":
            continue

        spec = doc["spec"]
        pod = spec["template"]["spec"]
        container = pod["containers"][0]

        selector = spec["selector"]["matchLabels"]
        labels = spec["template"]["metadata"]["labels"]
        if selector != labels:
            fail(f"selector {selector} != template labels {labels}")
        else:
            print(f"   selector matches template labels: {selector}")

        print(f"   replicas: {spec['replicas']}")

        psc = pod.get("securityContext", {})
        csc = container.get("securityContext", {})
        if not psc.get("runAsNonRoot"):
            fail("pod securityContext.runAsNonRoot is not true")
        if not csc.get("readOnlyRootFilesystem"):
            fail("container securityContext.readOnlyRootFilesystem is not true")
        if csc.get("capabilities", {}).get("drop") != ["ALL"]:
            fail("container does not drop ALL capabilities")
        print(f"   runAsNonRoot={psc.get('runAsNonRoot')} uid={psc.get('runAsUser')} "
              f"readOnlyRootFS={csc.get('readOnlyRootFilesystem')} "
              f"drop={csc.get('capabilities', {}).get('drop')}")

        res = container.get("resources", {})
        req, lim = res.get("requests"), res.get("limits")
        if not req or not lim:
            fail("resources.requests or resources.limits missing (pod would be BestEffort)")
        else:
            qos = "Guaranteed" if req == lim else "Burstable"
            print(f"   requests={req} limits={lim} -> QoS {qos}")


if __name__ == "__main__":
    for target in sys.argv[1:] or ["manifests/links-service"]:
        check(target)
        print()
    if BAD:
        print(f"{BAD} problem(s) found")
        sys.exit(1)
    print("all checks passed")
