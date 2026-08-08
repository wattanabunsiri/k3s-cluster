#!/usr/bin/env python3
"""Render every ArgoCD Application in argocd-apps/ through `helm template`.

ArgoCD auto-syncs argocd-apps/stack/ on push to main, so a manifest that only
fails at render time would land straight on the live cluster. This catches that
in the PR instead.

For each Helm-sourced Application we run the same render ArgoCD would:
chart + version + inline values, with CRDs included. Plain (non-Application)
manifests are structurally validated instead.

Usage: validate_argocd_apps.py [root_dir]      # default: argocd-apps
"""

import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

# Matches the k3s cluster so chart capability checks resolve the same way.
KUBE_VERSION = "v1.36.2"


class RenderLoader(yaml.SafeLoader):
    """SafeLoader that tolerates rendered-chart quirks.

    kube-prometheus-stack emits bare `=` values inside its PromQL/dashboard
    payloads. That is YAML 1.1's "default value" tag, which SafeLoader refuses
    to construct. We only parse rendered output to count resources, so mapping
    it to a plain string is enough.
    """


RenderLoader.add_constructor(
    "tag:yaml.org,2002:value", lambda loader, node: loader.construct_scalar(node)
)

GREEN, RED, YELLOW, DIM, RESET = (
    "\033[32m",
    "\033[31m",
    "\033[33m",
    "\033[2m",
    "\033[0m",
)


def render_helm_app(path: Path, doc: dict, source: dict) -> list[str]:
    """helm template one Helm-sourced Application. Returns a list of errors."""
    name = doc["metadata"]["name"]
    chart = source["chart"]
    repo = source["repoURL"]
    version = source.get("targetRevision")
    helm = source.get("helm") or {}
    values = helm.get("values", "")
    release = helm.get("releaseName", name)
    namespace = (doc["spec"].get("destination") or {}).get("namespace", "default")

    if not version:
        return [f"{path}: app '{name}' has no targetRevision — chart version must be pinned"]

    # Values must be valid YAML on their own before helm ever sees them.
    try:
        yaml.safe_load(values)
    except yaml.YAMLError as exc:
        return [f"{path}: app '{name}' has malformed inline helm values:\n{exc}"]

    with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as fh:
        fh.write(values)
        values_file = fh.name

    cmd = [
        "helm", "template", release, chart,
        "--repo", repo,
        "--version", version,
        "--namespace", namespace,
        "--kube-version", KUBE_VERSION,
        "--include-crds",
        "-f", values_file,
    ]

    print(f"  {DIM}$ helm template {release} {chart} --version {version}{RESET}")
    proc = subprocess.run(cmd, capture_output=True, text=True)

    if proc.returncode != 0:
        return [f"{path}: app '{name}' failed to render:\n{proc.stdout}\n{proc.stderr}"]

    # A chart that renders to nothing is almost always a values typo that
    # disabled every component.
    try:
        rendered = [d for d in yaml.load_all(proc.stdout, Loader=RenderLoader) if d]
    except yaml.YAMLError as exc:
        return [f"{path}: app '{name}' rendered output is not parseable YAML:\n{exc}"]

    if not rendered:
        return [f"{path}: app '{name}' rendered zero resources — check the values"]

    print(f"    {GREEN}ok{RESET} — {len(rendered)} resources")
    return []


def check_plain_manifest(path: Path, doc: dict) -> list[str]:
    """Structural check for non-Application manifests the root app applies."""
    errors = []
    kind = doc.get("kind")
    if not doc.get("apiVersion"):
        errors.append(f"{path}: manifest is missing apiVersion")
    if not kind:
        errors.append(f"{path}: manifest is missing kind")
    if not (doc.get("metadata") or {}).get("name"):
        errors.append(f"{path}: manifest is missing metadata.name")
    # The root app's destination is the argocd namespace, so anything meant to
    # live elsewhere has to say so explicitly or it lands in the wrong place.
    if kind and kind != "Application" and not (doc.get("metadata") or {}).get("namespace"):
        errors.append(
            f"{path}: {kind} '{doc.get('metadata', {}).get('name')}' has no explicit "
            f"metadata.namespace — it would be applied into 'argocd'"
        )
    if not errors:
        print(f"    {GREEN}ok{RESET} — {kind} (structural check)")
    return errors


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "argocd-apps")
    if not root.is_dir():
        print(f"{RED}no such directory: {root}{RESET}")
        return 1

    files = sorted(p for p in root.rglob("*.yaml"))
    if not files:
        print(f"{RED}no YAML files found under {root}{RESET}")
        return 1

    errors: list[str] = []
    helm_apps = 0

    for path in files:
        print(f"{path}")
        try:
            docs = [d for d in yaml.safe_load_all(path.read_text()) if d]
        except yaml.YAMLError as exc:
            errors.append(f"{path}: invalid YAML:\n{exc}")
            print(f"    {RED}invalid YAML{RESET}")
            continue

        if not docs:
            errors.append(f"{path}: contains no YAML documents")
            continue

        for doc in docs:
            if doc.get("kind") == "Application":
                source = (doc.get("spec") or {}).get("source") or {}
                if source.get("chart"):
                    helm_apps += 1
                    errors.extend(render_helm_app(path, doc, source))
                else:
                    # Git-sourced app (e.g. the root app-of-apps): nothing to
                    # render, but the Application object itself must be sane.
                    print(f"    {GREEN}ok{RESET} — git-sourced Application "
                          f"(path: {source.get('path', '?')})")
                    if not source.get("repoURL"):
                        errors.append(f"{path}: Application has no spec.source.repoURL")
            else:
                errors.extend(check_plain_manifest(path, doc))

    print()
    if errors:
        print(f"{RED}FAILED — {len(errors)} problem(s):{RESET}\n")
        for err in errors:
            print(f"  {RED}•{RESET} {err}\n")
        return 1

    print(f"{GREEN}All {len(files)} manifest(s) valid "
          f"({helm_apps} Helm chart(s) rendered).{RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
