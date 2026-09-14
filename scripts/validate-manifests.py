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
import re
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

    service_accounts = {}   # name -> does it carry a role-arn annotation
    deployments = []        # (filename, pod spec, first container)

    for f in files:
        doc = yaml.safe_load(f.read_text(encoding="utf-8"))
        kind = doc["kind"]
        meta = doc["metadata"]
        ns = meta["name"] if kind == "Namespace" else meta.get("namespace")
        print(f"{f.name}  ->  {kind}  namespace={ns}")

        if kind != "Namespace" and not ns:
            fail(f"{f.name}: no namespace declared, would land in 'default'")

        if kind == "ServiceAccount":
            role = (meta.get("annotations") or {}).get("eks.amazonaws.com/role-arn")
            service_accounts[meta["name"]] = bool(role)
            if role:
                print(f"   IRSA role: {role.rsplit('/', 1)[-1]}")
            else:
                # Not automatically a failure -- a plain ServiceAccount is a
                # legitimate object. But in this project every one exists FOR
                # IRSA, and a missing annotation fails silently: the pod
                # starts, both probes pass, and every AWS call returns
                # NoCredentialsError.
                print("   no eks.amazonaws.com/role-arn "
                      "(fine for a plain SA; useless for IRSA)")

        if kind != "Deployment":
            continue

        spec = doc["spec"]
        pod = spec["template"]["spec"]
        container = pod["containers"][0]
        deployments.append((f.name, pod, container))

        # Informational, not a failure. A placeholder tag is the CORRECT resting
        # state for a manifest that has not been deployed since its last change --
        # `make deploy` rewrites it. But it is worth saying out loud, because
        # ArgoCD (R-07) applies this repo verbatim and would try to pull it.
        image = container.get("image", "")
        if image.endswith(":PLACEHOLDER"):
            print("   image tag is a PLACEHOLDER — `make deploy` rewrites it; "
                  "ArgoCD would fail on it as-is")
        elif image.endswith(":latest"):
            # A real failure, not a note. The ECR repositories are IMMUTABLE
            # (R-03), so `:latest` cannot be repushed -- the first push wins
            # and every later one fails. Worse, if one ever did land, "which
            # build is running?" stops having an answer, which is the exact
            # property IMMUTABLE was chosen to guarantee.
            #
            # `:PLACEHOLDER` is the correct resting state; `make deploy`
            # rewrites it to the git SHA. Caught here because the alternative
            # is finding out during a deploy, with the cluster billing.
            fail("image tag is `latest` — ECR repos are IMMUTABLE (R-03), "
                 "so it can never be repushed. Use :PLACEHOLDER instead.")
        elif ":" in image:
            print(f"   image tag: {image.rsplit(':', 1)[1]}")

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

    cross_checks(service_accounts, deployments)
    localhost_default_checks(directory, deployments)


def localhost_default_checks(directory: str, deployments: list) -> None:
    """Every env var the service defaults to localhost MUST be set in its Deployment.

    THIS EXISTS BECAUSE THE SAME BUG HAPPENED TWICE.

      - 2026-09-10: gateway's LINKS_SERVICE_URL was set to port 8000 -- the
        CONTAINER's port -- when the Service exposes 80. Symptom was
        ConnectTimeout, not ConnectError, because the ClusterIP resolves and
        DNS works but no rule exists for that port, so packets are dropped
        rather than refused.
      - 2026-09-13: gateway's AGGREGATOR_URL was added to the code with a
        localhost:8002 default and never added to the Deployment at all, so
        in-cluster gateway dialled ITSELF and answered 503 for every /status.

    Both are one pattern: a sensible local default, a Deployment that forgot to
    override it, and a value nothing consumed until the day something finally
    read it. **A config variable whose default is localhost is a landmine
    unless the Deployment overrides it** -- in a pod, localhost is the pod.

    A regex over the source rather than an import, deliberately: this script
    must run with no service venv, no dependencies and no cluster. It reads
    `os.getenv("NAME", "...localhost...")` and nothing cleverer, which is
    exactly the shape all three services use. If a service starts reading
    config some other way, this check goes quiet -- so it is a floor, not a
    guarantee.
    """
    svc = pathlib.Path(directory).name
    source = pathlib.Path(svc) / "app" / "main.py"
    if not source.exists():
        return  # not a service directory (e.g. manifests/ itself)

    text = source.read_text(encoding="utf-8")
    # os.getenv("NAME", "anything-with-localhost-in-it")
    pattern = r'os\.getenv\(\s*["\'](\w+)["\']\s*,\s*["\']([^"\']*localhost[^"\']*)["\']'
    localhost_vars = dict(re.findall(pattern, text))
    if not localhost_vars:
        return

    for fname, pod, container in deployments:
        declared = {e["name"] for e in (container.get("env") or [])}
        for var, default in sorted(localhost_vars.items()):
            if var in declared:
                value = next(e.get("value") for e in container["env"] if e["name"] == var)
                print(f"   {var} overridden -> {value}")
                if "localhost" in str(value):
                    fail(f"{fname}: {var} is set to {value!r} -- localhost in a pod IS "
                         f"the pod, so this points the service at itself.")
            else:
                fail(f"{fname}: {source} defaults {var} to {default!r}, but the "
                     f"Deployment does not set it. In a pod localhost is the pod, so "
                     f"the service would call ITSELF. This is the D-21 / LINKS_SERVICE_URL "
                     f"bug; it has happened twice.")


def cross_checks(service_accounts: dict, deployments: list) -> None:
    """Checks spanning more than one file, so they cannot live in the loop.

    These encode rules that were previously PROSE in PROGRESS.md's defect
    table, and prose rules rot. D-18 especially is a rule about two lines that
    must ship together -- exactly the thing a human forgets and a checker
    does not.
    """
    for fname, pod, container in deployments:
        sa = pod.get("serviceAccountName")
        env = {e["name"]: e.get("value") for e in (container.get("env") or [])}

        if sa:
            if sa not in service_accounts:
                fail(f"{fname}: serviceAccountName '{sa}' has no ServiceAccount "
                     f"in this directory -- the pod would get no AWS identity "
                     f"at all, and would still start.")
            elif not service_accounts[sa]:
                fail(f"{fname}: serviceAccountName '{sa}' exists but has no "
                     f"eks.amazonaws.com/role-arn annotation, so nothing "
                     f"injects credentials.")
            else:
                print(f"{fname}: serviceAccountName '{sa}' -> annotated SA  OK")

        # -------------------------------------------------------------
        # D-18, made mechanical.
        #
        # LINKS_TABLE_NAME without an IRSA ServiceAccount gives a pod that is
        # healthy by every probe and broken for every request:
        # build_repository() only constructs a boto3 resource, so startup
        # succeeds; /health never touches storage, so liveness and readiness
        # both pass and the pod sits there Running and Ready; then every
        # /links call fails with NoCredentialsError.
        #
        # Nothing about that looks like a failure from outside, which is
        # exactly why it deserves a check rather than a note in a table.
        # -------------------------------------------------------------
        if "LINKS_TABLE_NAME" in env and not sa:
            fail(f"{fname}: sets LINKS_TABLE_NAME but no serviceAccountName "
                 f"(D-18) -- pod would be Running and Ready and 500 on every "
                 f"request with NoCredentialsError.")

        # A container has no ~/.aws/config, so an unset region raises
        # NoRegionError, which reads like a credentials fault and is not.
        if "LINKS_TABLE_NAME" in env and "AWS_REGION" not in env:
            fail(f"{fname}: sets LINKS_TABLE_NAME but not AWS_REGION -- boto3 "
                 f"raises NoRegionError, which looks like a credentials "
                 f"problem and is not.")


if __name__ == "__main__":
    for target in sys.argv[1:] or ["manifests/links-service"]:
        check(target)
        print()
    if BAD:
        print(f"{BAD} problem(s) found")
        sys.exit(1)
    print("all checks passed")
