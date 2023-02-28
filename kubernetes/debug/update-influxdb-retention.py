#!/usr/bin/env python3
import argparse
import subprocess
import json


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("bucket_retention", help="bucket retention time (ex. 3d, 7d, 12h)")
    args = parser.parse_args()

    # get bucket id    
    output = subprocess.check_output(["kubectl", "exec", "wes-node-influxdb-0", "--", "influx", "bucket", "list", "--name", "waggle", "--json"])
    data = json.loads(output)
    bucket_id = data[0]["id"]

    # update bucket retention
    subprocess.check_call(["kubectl", "exec", "wes-node-influxdb-0", "--", "influx", "bucket", "update", "--id", bucket_id, "--retention", args.bucket_retention])

if __name__ == "__main__":
    main()
