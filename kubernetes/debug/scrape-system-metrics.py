#!/usr/bin/env python3
from collections import namedtuple
from pathlib import Path
import json
import subprocess
from typing import List
from datetime import datetime
import gzip
import sys
import re

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


def get_core_device(devices: List[Device]) -> Device:
    for device in devices:
        if devices.ip == "10.31.81.1":
            return device
    raise KeyError("could not find core device")


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

    # scrape core device specific metrics
    device = get_core_device(devices)

    # scrape rabbitmq metrics
    output = subprocess.check_output(["kubectl", "get", "pod", "-o", "wide"]).decode()
    rabbitmq_ip = re.search(r"wes-rabbitmq-0.*(10\.42\S+)", output).group(1)

    if rabbitmq_ip is not None:
        timestamp = datetime.utcnow()
        output = subprocess.check_output(
            [
                "curl",
                "-s",
                f"http://{rabbitmq_ip}:15692/metrics",
            ]
        )
        timestamp_ms = int(timestamp.timestamp() * 1000)
        Path(rootdir, f"{device.name}_rabbitmq_{timestamp_ms}.prom.gz").write_bytes(
            gzip.compress(output)
        )


if __name__ == "__main__":
    main()
