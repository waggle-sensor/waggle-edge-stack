from pathlib import Path
import json
import main


class MockRabbitmqClient:

    def __init__(self, path):
        self.path = Path(path)

    def list_connections(self):
        return json.loads(self.path.read_text())


class MockKubernetesClient:

    def __init__(self, path):
        self.path = Path(path)

    def list_pods(self):
        return json.loads(self.path.read_text())["items"]


if __name__ == "__main__":
    rabbitmq_client = MockRabbitmqClient("test_connections.json")
    kubernetes_client = MockKubernetesClient("test_pods.json")
    main.run(rabbitmq_client, kubernetes_client)
