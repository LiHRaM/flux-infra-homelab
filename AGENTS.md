# flux-infra-homelab

Flux GitOps for the home Kubernetes cluster on the Talos `main` branch.

## How apps are structured (read before adding one)

Monorepo layout (`apps/` + `clusters/` + `infrastructure/` + `secrets/`), per
Flux's "repository structure" guide.

- **`apps/base/<app>/`** — namespace-agnostic manifests: `deployment.yaml`,
  `service.yaml`, `kustomization.yaml`.
- **`apps/talos/<app>/`** — cluster overlay:
  - its own `kustomization.yaml` (namespace, PVCs, ts-ingress, patches, the
    `../../base/<app>` reference)
  - exactly **one** app may own a `namespace.yaml` (a duplicate `Namespace` id
    across overlays fails the flux build with "already registered id")
  - a `PersistentVolumeClaim` with `storageClassName: longhorn-trusty`
  - an `Ingress` for tailnet exposure (see below)
  - `ImageRepository` + `ImagePolicy` live **at `apps/talos/` root**
    (`apps/talos/<app>-image-repository.yaml` / `-image-policy.yaml`), wired
    into the deployment via the image-policy marker comment.

## App aggregation / validation (the non-obvious part)

Flux's `Kustomization` `apps` (in `clusters/talos/apps.yaml`) points its
`spec.path` at **`./apps/talos`**, yet there is **no root `kustomization.yaml`
at `apps/talos/`**. The flux CLI's own builder renders every `<app>/` subdir
kustomization automatically — so a **new subdir app is picked up with zero
changes to any aggregator**. Do not add a root kustomization to "list" apps.

- `kubectl kustomize apps/talos` fails ("unable to find kustomization") — that's
  expected and does **not** mean the structure is broken. **Use `flux` for
  local validation instead**:

  ```sh
  flux build kustomization apps --path ./apps/talos   # pure local render
  flux diff kustomization apps --path ./apps/talos    # against live cluster
  ```

- **`scripts/diff-talos.sh` aborts early** with non-zero exit on pre-existing
  `infrastructure/talos/nfd-*` ConfigMap drift (CRLF line-ending diffs) before
  reaching the apps section, because it runs under `set -eu`. It's `flux diff`
  per path, so to check only apps, run the `flux diff kustomization apps` line
  directly — don't treat `diff-talos.sh`'s non-zero as a failure in apps.

## Tailnet exposure (ts-ingress)

An app is exposed over the tailnet via an `Ingress` with:

```yaml
labels:
  hilmargustafs.com/group: internal   # required; Flux patch below stamps tags
spec:
  ingressClassName: tailscale
  tls: [{ hosts: [<hostname>] }]
```

`clusters/talos/apps.yaml` patches any `Ingress` with that label selector, adding
`tailscale.com/tags: tag:k8s,tag:internal` — the node is then reachable at
`<hostname>.tyrannosaurus-turtle.ts.net`. (The router ACL was extended to let
`tag:router` peer with those cluster tags for LAN↔tailnet relay.)

## Secrets

SOPS-encrypted via age key (`.sops.yaml`). Cluster-level secrets under
`secrets/talos/*.yaml` (decrypted by the `secrets` Kustomization); app-level
`*-secret.yaml` are decrypted by the `apps` Kustomization. Never commit plaintext
creds.
