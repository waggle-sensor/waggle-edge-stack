#!/usr/bin/env python3
from pathlib import Path
import yaml


def find_containers(x):
    def walk(obj, containers):
        if isinstance(obj, list):
            for item in obj:
                walk(item, containers)
        elif isinstance(obj, dict):
            for key, item in obj.items():
                if key == "containers":
                    containers += item
                walk(item, containers)

    containers = []
    walk(x, containers)
    return containers


def main():
    kube_dir = Path(__file__).parent.parent

    for file in kube_dir.glob("**/*.yaml"):
        for doc in yaml.safe_load_all(file.read_text()):
            for container in find_containers(doc):
                if container.get("imagePullPolicy") != "IfNotPresent":
                    print(file, container["name"])


if __name__ == "__main__":
    main()
