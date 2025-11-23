#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

kubectl create ns argocd || true

kubectl kustomize --enable-helm "$SCRIPT_DIR/../k8s/argocd/argocd" | kubectl apply -f -
kubectl kustomize --enable-helm "$SCRIPT_DIR/../k8s/argocd/argocd-apps" | kubectl apply -f -
