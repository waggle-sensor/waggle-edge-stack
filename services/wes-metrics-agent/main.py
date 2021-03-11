import argparse
from urllib.request import urlopen
from prometheus_client.parser import text_string_to_metric_families
from pathlib import Path
import time
import logging
from waggle import message
from os import getenv
import pika


def get_node_exporter_metrics(url):
    with urlopen(url) as f:
        return f.read().decode()


def get_uptime_seconds():
    text = Path("/proc/uptime").read_text()
    fs = text.split()
    return float(fs[0])


# prom2waggle holds a map of node_exporter's metrics to our metrics
prom2waggle = {
    # time
    "node_boot_time_seconds": "sys.boot_time",
    "node_time_seconds": "sys.time",
    # cpu
    "node_cpu_seconds_total": "sys.cpu_seconds",
    # load
    "node_load1": "sys.load1",
    "node_load5": "sys.load5",
    "node_load15": "sys.load15",
    # mem
    "node_memory_MemAvailable_bytes": "sys.mem.avail",
    "node_memory_MemFree_bytes": "sys.mem.free",
    "node_memory_MemTotal_bytes": "sys.mem.total",
    # fs
    "node_filesystem_avail_bytes": "sys.fs.avail",
    "node_filesystem_size_bytes": "sys.fs.size",
    # net
    "node_network_receive_bytes_total": "sys.net.rx_bytes",
    "node_network_receive_packets_total": "sys.net.rx_packets",
    "node_network_transmit_bytes_total": "sys.net.tx_bytes",
    "node_network_transmit_packets_total": "sys.net.tx_packets",
    "node_network_up": "sys.net.up",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--waggle-node-id', default=getenv('WAGGLE_NODE_ID', '0000000000000000'), help='waggle node id')
    # parser.add_argument('--waggle-host-id', default=getenv('WAGGLE_HOST_ID', ''), help='waggle host id')
    parser.add_argument('--rabbitmq-host', default=getenv('RABBITMQ_HOST', 'localhost'), help='rabbitmq host')
    parser.add_argument('--rabbitmq-port', default=int(getenv('RABBITMQ_PORT', '5672')), type=int, help='rabbitmq port')
    parser.add_argument('--rabbitmq-username', default=getenv('RABBITMQ_USERNAME', 'guest'), help='rabbitmq username')
    parser.add_argument('--rabbitmq-password', default=getenv('RABBITMQ_PASSWORD', 'guest'), help='rabbitmq password')
    parser.add_argument('--rabbitmq-exchange', default=getenv('RABBITMQ_EXCHANGE', 'metrics'), help='rabbitmq exchange to publish to')
    parser.add_argument('--metrics-url', default=getenv("METRICS_URL", "http://localhost:9100/metrics"), help='node exporter metrics url')
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s %(message)s',
        datefmt='%Y/%m/%d %H:%M:%S')

    while True:
        timestamp = time.time_ns()

        messages = []

        logging.info("scraping %s", args.metrics_url)
        text = get_node_exporter_metrics(args.metrics_url)

        for family in text_string_to_metric_families(text):
            for sample in family.samples:
                try:
                    name = prom2waggle[sample.name]
                except KeyError:
                    continue

                messages.append(message.Message(
                    name=name,
                    value=sample.value,
                    timestamp=timestamp,
                    meta=sample.labels,
                ))

        messages.append(message.Message(
            name="sys.uptime",
            value=get_uptime_seconds(),
            timestamp=timestamp,
            meta={},
        ))

        for msg in messages:
            msg.meta["node"] = args.waggle_node_id
            msg.meta["host"] = "vagrant"
            # TODO get node / host name
            logging.info("metric %s", message.dump(msg))

        params = pika.ConnectionParameters(
            host=args.rabbitmq_host,
            port=args.rabbitmq_port,
            credentials=pika.PlainCredentials(
                username=args.rabbitmq_username,
                password=args.rabbitmq_password,
            ),
        )

        logging.info('connecting to rabbitmq server at %s:%d as %s.', params.host, params.port, params.credentials.username)
        
        # connect to rabbitmq and publish all messages
        with pika.BlockingConnection(params) as connection:
            channel = connection.channel()
            for msg in messages:
                channel.basic_publish(exchange=args.rabbitmq_exchange, routing_key=msg.name, body=message.dump(msg))

        time.sleep(60)


if __name__ == "__main__":
    main()
