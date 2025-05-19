# WES Chirpstack

_Note: This directory contains experimental work to try running Chirpstack against an external gateway device._

Contains all components to support the Chirpstack software stack to gain access to LoRaWAN device data.

## Metrics

Most of the Chirpstack pods publish prometheus metrics on port `9100`. See the individual deployment files for details.

## More Information

For more information on each component:

- Gateway:
   - [udp-packet-forwader](https://github.com/RAKWireless/udp-packet-forwarder)
   - [chirpstack-gateway-bridge](https://github.com/chirpstack/chirpstack-gateway-bridge)
- Chirpstack:
   - [wes-chirpstack-server](https://github.com/waggle-sensor/wes-chirpstack-server)
   - [wes-chirpstack-tracker](https://github.com/waggle-sensor/wes-chirpstack-tracker)
   - [init-chirpstack-server](https://github.com/waggle-sensor/init-chirpstack-server)
   - [redis](https://github.com/redis/redis)
   - [postgres](https://www.postgresql.org/)
