#!/bin/bash -e

# NOTE deploy stack is now "declarative", so it simply does the same thing as updated-stack.sh.
cd $(dirname $0)
./update-stack.sh
