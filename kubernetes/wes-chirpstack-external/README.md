# WES Chirpstack (external gateway)

Kustomize overlay of [wes-chirpstack](../wes-chirpstack) for a LoRaWAN gateway that is not on the node.

The overlay keeps the shared Chirpstack stack and patches only the gateway Deployment:

- Drop the onboard `wes-lorawan-gateway` packet-forwarder sidecar and the host `/sys` mount.
- Schedule the gateway bridge on the control-plane node.
- Publish UDP `1700` on the host so an external gateway can reach the bridge.

Shared server, tracker, Redis, PostgreSQL, init job, and config files live in `wes-chirpstack`.
