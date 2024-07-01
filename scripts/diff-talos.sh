#!/usr/bin/env bash

CLUSTER=talos

set -eu pipefail

echo "Diffing flux-system"
flux diff kustomization flux-system --path ./clusters/"$CLUSTER"

echo "Diffing infrastructure"
flux diff kustomization infrastructure --path ./infrastructure/"$CLUSTER"

echo "Diffing apps"
flux diff kustomization apps --path ./apps/"$CLUSTER"