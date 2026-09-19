# 36 — Secrets that have to outlive the cluster  ·  *delegated, short note*

## What it does

Adds two Makefile targets that split Jenkins' credentials along the line that
actually matters — whether a thing needs a cluster.

`make jenkins-password` generates a 32-character random admin password once,
writes it to `~/.app-hub/jenkins-admin.env` at mode `600`, and never prints it.
No cluster required. Re-running refuses to overwrite.

`make jenkins-secrets` needs a live cluster, and creates **both** in-cluster
Secrets — `jenkins-admin` from that file, and `jenkins-deploy-key` from
`~/.ssh/app-hub-manifests-deploy`. It then verifies each against its source and
exits non-zero if either fails.

## Why it is this way

**A Kubernetes Secret is an in-cluster object, so it dies with every
`make down`.** That is the whole design constraint. Creating the password
*inside* the cluster would mean regenerating it on every rebuild — so it would
change nightly, which `manifests/jenkins/values.yaml` already names as the thing
to avoid, because a credential that changes on every reinstall defeats
reproducibility. So the source of truth has to live outside the cluster, and
`jenkins-secrets` becomes a routine post-`make up` step rather than one-time
setup.

**Where it lives outside the cluster is also constrained, and not by taste.**
Not in any of the eight git repositories — that is obvious. Less obvious: not
under `/mnt/c` either, because a Windows-mounted file cannot hold Unix `0600`.
`chmod` there **reports success and changes nothing**, which is the same class of
silent lie as every other trap in `CLAUDE.md § 9`. WSL home is ext4, so the mode
is real and verifiable. That is why the deploy key already lives in `~/.ssh`, and
the password now lives beside it in `~/.app-hub`.

**Verification compares against the source, not against existence.** After a
password change, a Secret that *exists* and a Secret that is *correct* are
different facts, and `kubectl get secret` cannot distinguish them. The target
compares 12-character sha256 prefixes of the cluster value and the disk value —
which proves equality and reveals nothing.

## The one thing to know

**`make jenkins-secrets` is not setup you do once — it is part of bringing the
cluster up.** Both Secrets are destroyed by every teardown, so the sequence is
`make up` → `make jenkins-secrets` → `make jenkins`. Skipping the middle step
does not fail quietly: `make jenkins` guards on both Secrets and refuses to
install, deliberately, because a Jenkins that installs without them comes up
reachable, with the job present, and fails every build at the git push — a much
more expensive way to discover the same thing.
