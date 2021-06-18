#!/usr/bin/env python3
import argparse
import subprocess
from pathlib import Path
import json

parser = argparse.ArgumentParser()
parser.add_argument("name", type=str, help="name of plugin")
parser.add_argument("path", type=Path, help="path to plugin directory")
args = parser.parse_args()

fields = args.name.split("/", 2)

if len(fields) == 1:
    fields = ["docker.io", "waggle"] + fields
elif len(fields) == 2:
    fields = ["docker.io"] + fields

name = "/".join(fields)

# output = subprocess.check_output(["kubectl", "get", "pod", "-o", "json"])
# info = json.loads(output)

# podIPs = []

# for obj in info["items"]:
#     if obj["metadata"]["labels"].get("app.kubernetes.io/name") != "wes-buildkitd":
#         continue
#     if obj["status"]["phase"] != "Running":
#         continue
#     podIP = obj["status"]["podIP"]
#     podIPs.append(podIP)

context = str(args.path.absolute())

# build for all targets
# for podIP in podIPs:
#     print(f"building on {podIP}")
#     subprocess.run([
#         "buildctl", "--debug", "--addr", f"tcp://{podIP}:1234", "build",
#         "--frontend=dockerfile.v0",
#         "--local", f"context={context}",
#         "--local", f"dockerfile={context}",
#         "--output", f"type=image,name={args.name}",
#     ])

subprocess.run([
    "buildctl", "build",
    "--frontend=dockerfile.v0",
    "--local", f"context={context}",
    "--local", f"dockerfile={context}",
    "--output", f"type=image,name={name}",
])
