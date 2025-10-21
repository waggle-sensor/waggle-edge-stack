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
from shutil import rmtree

RETENTION_DAYS = 30

Device = namedtuple("Device", ["name", "ip", "core"])


def get_devices_from_kube() -> List[Device]:
    output = subprocess.check_output(["kubectl", "get", "nodes", "-o", "json"])
    kube_nodes_data = json.loads(output)
    devices = []
    for item in kube_nodes_data["items"]:
        metadata = item["metadata"]
        labels = metadata["labels"]
        annotations = item["metadata"]["annotations"]
        # get device details
        name = metadata["name"]
        ip = annotations["k3s.io/internal-ip"]
        # we essentially define that: core device = device where we run k3s control plane
        core = False
        if labels.get("node-role.kubernetes.io/control-plane") == "true":
            core = True
        if labels.get("node-role.kubernetes.io/master") == "true":
            core = True
        devices.append(Device(name, ip, core))
    return devices


def get_system_metrics_disk_usage_bytes() -> int:
    if not Path("/media/plugin-data/system-metrics").exists():
        return 0
    output = subprocess.check_output(["du", "-sb", "/media/plugin-data/system-metrics"])
    fs = output.split()
    return int(fs[0])


def get_core_device(devices: List[Device]) -> Device:
    core_devices = [device for device in devices if device.core]
    if len(core_devices) != 1:
        raise KeyError("could not find core device")
    return core_devices[0]


def scrape_cadvisor_metrics_for_device(device: Device, rootdir: Path):
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


def scrape_node_exporter_metrics_for_device(device: Device, rootdir: Path):
    timestamp = datetime.utcnow()
    output = subprocess.check_output(
        [
            "curl",
            "-s",
            f"http://{device.ip}:9100/metrics",
        ]
    )
    timestamp_ms = int(timestamp.timestamp() * 1000)
    Path(rootdir, f"{device.name}_node-exporter_{timestamp_ms}.prom.gz").write_bytes(
        gzip.compress(output)
    )


def scrape_rabbitmq_metrics(devices: List[Device], rootdir: Path):
    core_device = get_core_device(devices)
    output = subprocess.check_output(["kubectl", "get", "pod", "-o", "wide"]).decode()
    rabbitmq_ip = re.search(r"wes-rabbitmq-0.*(10\.42\S+)", output).group(1)

    if rabbitmq_ip is None:
        print("failed to scrape rabbitmq metrics")
        return

    timestamp = datetime.utcnow()
    output = subprocess.check_output(
        [
            "curl",
            "-s",
            f"http://{rabbitmq_ip}:15692/metrics",
        ]
    )
    timestamp_ms = int(timestamp.timestamp() * 1000)
    Path(rootdir, f"{core_device.name}_rabbitmq_{timestamp_ms}.prom.gz").write_bytes(
        gzip.compress(output)
    )


# fix_rabbitmq_metric_name fixes a naming bug where we accidentally tagged
# rabbitmq metrics with a non core device name. this is a hold over to
# fix the names once. eventually this function can be dropped as the bug
# is fixed.
def fix_rabbitmq_metrics_name(devices):
    core_device = get_core_device(devices)

    for path in Path("/media/plugin-data/system-metrics").glob("**/*rabbitmq*.prom.gz"):
        parts = path.name.split("_", maxsplit=2)
        if parts[0] == core_device.name:
            continue
        fixed_name = f"{core_device.name}_{parts[1]}_{parts[2]}"
        fixed_path = path.with_name(fixed_name)
        print("renaming", path, "to", fixed_path)
        path.rename(fixed_path)


def main():
    # perform safety check to make sure we don't have runaway disk usage.
    disk_usage_gb = get_system_metrics_disk_usage_bytes() / 1024**3

    print(f"system metrics using {disk_usage_gb:03f}Gi of space")

    if disk_usage_gb >= 10:
        print(
            "system metrics using more than 10Gi of disk space! service will not collect until admin cleans up /media/plugin-data/system-metrics"
        )
        sys.exit(1)

    # keep only the last 30 days of system metrics on disk.
    dirs = sorted(Path("/media/plugin-data/system-metrics/").glob("*/*/*"))
    print(f"{len(dirs)} days of system metrics are cached on disk.")

    excess = 0

    if len(dirs) > RETENTION_DAYS:
        excess = len(dirs) - RETENTION_DAYS
        print(
            f"more than {RETENTION_DAYS} days of metrics on disk. will perform clean up!"
        )

    for d in dirs[:excess]:
        print(f"removing {d}")
        rmtree(d)

    # ensure today's data directory exists.
    today = datetime.today()
    rootdir = Path(today.strftime("/media/plugin-data/system-metrics/%Y/%m/%d"))
    rootdir.mkdir(parents=True, exist_ok=True)

    devices = get_devices_from_kube()

    for device in devices:
        try:
            scrape_cadvisor_metrics_for_device(device, rootdir)
        except Exception:
            print(f"failed to scrape cadvisor metrics for {device.name}")

        try:
            scrape_node_exporter_metrics_for_device(device, rootdir)
        except Exception:
            print(f"failed to scrape node-exporter metrics for {device.name}")

    scrape_rabbitmq_metrics(devices, rootdir)

    # see note about eventually dropping this.
    fix_rabbitmq_metrics_name(devices)


if __name__ == "__main__":
    main()
