#!/usr/bin/env python3
"""Remove CAST.ai and Helm resources from terraform state before destroy.

Terraform initialises all configured providers during planning, including the
Helm/Kubernetes provider which requires a live cluster. By stripping these
resources from state first, destroy can proceed against AWS-only resources
without needing a reachable cluster.
"""

import json
from pathlib import Path

STATE_FILE = Path(__file__).parent.parent / "terraform" / "terraform.tfstate"
DROP_TERMS = {"castai", "helm_release"}


def main():
    if not STATE_FILE.exists():
        print("No state file found, nothing to prune.")
        return

    state = json.loads(STATE_FILE.read_text())
    resources = state.get("resources", [])
    before = len(resources)

    state["resources"] = [
        r for r in resources
        if not any(term in r.get("module", "") or term in r.get("type", "") for term in DROP_TERMS)
    ]
    state["serial"] = state.get("serial", 0) + 1

    STATE_FILE.write_text(json.dumps(state, indent=2))
    pruned = before - len(state["resources"])
    print(f"Pruned {pruned} castai/helm resources from state ({len(state['resources'])} remaining).")


if __name__ == "__main__":
    main()
