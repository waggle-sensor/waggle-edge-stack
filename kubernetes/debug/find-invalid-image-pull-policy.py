#!/usr/bin/env python3
import argparse
from pathlib import Path
import yaml


def find_containers(x):
    def walk(obj, containers):
        if isinstance(obj, list):
            for item in obj:
                walk(item, containers)
        elif isinstance(obj, dict):
            for key, item in obj.items():
                if key in ["containers", "initContainers"]:
                    containers += item
                walk(item, containers)

    containers = []
    walk(x, containers)
    return containers


def main():
    wes_kube_dir = Path(__file__).parent.parent

    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=wes_kube_dir, type=Path)
    args = parser.parse_args()

    for file in args.root.glob("**/*.yaml"):
        for doc in yaml.safe_load_all(file.read_text()):
            for container in find_containers(doc):
                if container.get("imagePullPolicy") != "IfNotPresent":
                    print(file, container["name"])


if __name__ == "__main__":
    main()
