#!/bin/sh -e

fatal() {
    echo $*
    exit 1
}

case $(uname -m) in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    armv7l) arch=arm-v7 ;;
    *) fatal "invalid arch" ;;
esac

wget -q "https://github.com/moby/buildkit/releases/download/v0.8.3/buildkit-v0.8.3.linux-$arch.tar.gz" -O buildkit.tar.gz
tar -C /usr/local -xvf buildkit.tar.gz
rm buildkit.tar.gz

mkdir -p /etc/buildkit
cat > /etc/buildkit/buildkitd.toml <<EOF
[worker.oci]
  enabled = false

[worker.containerd]
  address = "/run/k3s/containerd/containerd.sock"
  enabled = true
  # platforms is manually configure platforms, detected automatically if unset.
  # platforms = [ "linux/amd64", "linux/arm64", "linux/arm/v7" ]
  namespace = "k8s.io"
EOF

cat > /etc/systemd/system/buildkitd.service <<EOF
[Unit]
Description=Buildkit

[Service]
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/buildkitd --addr unix:///run/buildkit/buildkitd.sock --addr tcp://127.0.0.1:1234

[Install]
WantedBy=multi-user.target
EOF

systemctl enable buildkitd
systemctl start buildkitd
