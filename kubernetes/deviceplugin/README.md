# Device Plugins for Waggle Nodes

## Nvidia GPU

To expose Nvidia GPU in Kubernetes cluster, Nvidia's device plugin needs to be deployed. Following [the instructions](https://github.com/NVIDIA/k8s-device-plugin#quick-start) makes it possible to use Nvidia GPU in a Kubernetes pod.

## Nvidia Tegra GPU in Jetson devices

__NOTE: The Nvidia's device plugin does not support Tegra devices (Jetson). [The pull request](https://gitlab.com/nvidia/kubernetes/device-plugin/-/merge_requests/61) is created to support that. By patching the commits to the device plugin should enable GPU access over k3s cluster via the device plugin. [This blog](https://blogs.windriver.com/wind_river_blog/2020/06/nvidia-k8s-device-plugin-for-wind-river-linux/) provides useful information to proceed with the patching.__

[Nvidia's device plugin for Jetson](nvidia-device-plugin.yml) can be deployed in nodes that have Jetson device(s). To deploy it in a cluster,

```bash
kubectl apply -f nvidia-device-plugin.yml
```

__NOTE: The device plugin has been tested on Jetpack 4.4.1 with CUDA 10.2__

Kubernetes deployments or pods will need to specify the GPU resource. For example,

```bash
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  restartPolicy: OnFailure
  containers:
  - image: waggle/plugin-base:1.1.1-ml-cuda10.2-l4t
    name: gpu-pod
    command: ['sh', '-c', 'while true; do sleep 30; done']
    resources:
      limits:
        nvidia.com/gpu: 1
```

__TODO: the daemonset will need to launch its pod on Jetson devices only (using nodeselector?)__