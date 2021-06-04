# Device Plugins for Waggle Nodes

## Nvidia GPU

To expose Nvidia GPU in Kubernetes cluster, Nvidia's device plugin needs to be deployed. Following [the instructions](https://github.com/NVIDIA/k8s-device-plugin#quick-start) makes it possible to use Nvidia GPU in a Kubernetes pod.

## Nvidia Tegra GPU in Jetson devices

__Last update: June 4th 2021__

The Nvidia's device plugin does not support Tegra devices (Jetson). [The pull request](https://gitlab.com/nvidia/kubernetes/device-plugin/-/merge_requests/61) is created to support that. By patching the commits to the device plugin should enable GPU access over k3s cluster via the device plugin. [This blog](https://blogs.windriver.com/wind_river_blog/2020/06/nvidia-k8s-device-plugin-for-wind-river-linux/) provides useful information to proceed with the patching.
