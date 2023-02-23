"""
This is a tool for debugging Pod's RabbitMQ connections.

TODO(sean) We may want to move this (and other WES debug tools) into their own repo rather than being part of core WES.
"""
import json
import subprocess


class RabbitmqClient:

    def list_connections(self):
        output = subprocess.check_output(["kubectl", "exec", "svc/wes-rabbitmq", "--", "rabbitmqadmin", "list", "connections", "--format=raw_json"])
        return json.loads(output)


class KubernetesClient:

    def list_pods(self):
        output = subprocess.check_output(["kubectl", "get", "pods", "-o", "json"])
        return json.loads(output)["items"]


def pretty_print_table(table):
    column_width = {}

    for row in table:
        for i, item in enumerate(row):
            column_width[i] = max(column_width.get(i, 0), len(str(item)))

    for row in table:
        for i, item in enumerate(row):
            print(str(item).ljust(column_width[i] + 2, " "), end="")
        print()


def run(rabbitmq_client, kubernetes_client):
    connections = rabbitmq_client.list_connections()
    pods = kubernetes_client.list_pods()

    ip2pod = {pod["status"]["podIP"]: pod["metadata"]["name"] for pod in pods if pod["status"].get("podIP")}

    table = []

    table.append(["pod", "recv", "recv/s", "send", "send/s"])

    for connection in connections:
        ip = connection["peer_host"]
        if ip in ip2pod:
            table.append([ip2pod[ip], connection["recv_oct"], connection["recv_oct_details"]["rate"], connection["send_oct"], connection["send_oct_details"]["rate"]])
    
    pretty_print_table(table)


if __name__ == "__main__":
    rabbitmq_client = RabbitmqClient()
    kubernetes_client = KubernetesClient()
    run(rabbitmq_client, kubernetes_client)
