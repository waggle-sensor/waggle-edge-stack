#!/usr/bin/env python3
from collections import namedtuple
from pathlib import Path
import json
import subprocess
from typing import List
from datetime import datetime
import gzip
import sys

Device = namedtuple("Device", ["name", "ip"])


def get_devices_from_kube() -> List[Device]:
    output = subprocess.check_output(["kubectl", "get", "nodes", "-o", "json"])
    kube_nodes_data = json.loads(output)
    devices = []
    for item in kube_nodes_data["items"]:
        name = item["metadata"]["name"]
        ip = item["metadata"]["annotations"]["k3s.io/internal-ip"]
        devices.append(Device(name, ip))
    return devices


def get_system_metrics_disk_usage_bytes() -> int:
    output = subprocess.check_output(["du", "-sb", "/media/plugin-data/system-metrics"])
    fs = output.split()
    return int(fs[0])


def main():
    disk_usage_gb = get_system_metrics_disk_usage_bytes() / 1024**3

    print(f"system metrics using {disk_usage_gb:03f}Gi of space")

    if disk_usage_gb >= 10:
        print(
            "system metrics using more than 10Gi of disk space! service will not collect until admin cleans up /media/plugin-data/system-metrics"
        )
        sys.exit(1)

    today = datetime.today()
    rootdir = Path(today.strftime("/media/plugin-data/system-metrics/%Y/%m/%d"))
    rootdir.mkdir(parents=True, exist_ok=True)

    devices = get_devices_from_kube()

    for device in devices:
        # scrape cadvisor metrics
        timestamp = datetime.utcnow()
        output = subprocess.check_output(
            [
                "kubectl",
                "get",
                "--raw",
                f"/api/v1/nodes/{device.name}/proxy/metrics/cadvisor",
            ]
        )
        timestamp_ms = int(timestamp.timestamp() * 1000)
        Path(rootdir, f"{device.name}_cadvisor_{timestamp_ms}.prom.gz").write_bytes(
            gzip.compress(output)
        )

        # scrape node exporter metrics
        timestamp = datetime.utcnow()
        output = subprocess.check_output(
            [
                "curl",
                "-s",
                f"http://{device.ip}:9100/metrics",
            ]
        )
        timestamp_ms = int(timestamp.timestamp() * 1000)
        Path(
            rootdir, f"{device.name}_node-exporter_{timestamp_ms}.prom.gz"
        ).write_bytes(gzip.compress(output))


if __name__ == "__main__":
    main()
