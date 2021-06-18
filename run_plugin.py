#!/usr/bin/env python3
import argparse
import subprocess
import random

parser = argparse.ArgumentParser()
parser.add_argument("name", type=str, help="name of plugin")
parser.add_argument("remainder", nargs=argparse.REMAINDER)
args = parser.parse_args()

fields = args.name.split("/", 2)

if len(fields) == 1:
    fields = ["docker.io", "waggle"] + fields
elif len(fields) == 2:
    fields = ["docker.io"] + fields

image = "/".join(fields)

name = fields[-1].split(":")[0] + "-" + str(random.randint(0, 10000))

extra_args = []

if len(args.remainder) > 0:
    extra_args = ["--command", "--"] + args.remainder

subprocess.run(["kubectl", "run", name, "-it", "--rm", "--restart=Never", f"--image={image}", "--image-pull-policy=Never", *extra_args])
