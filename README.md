# About

This creates an example [RKE cluster](https://rancher.com/docs/rke/latest/en/) in libvirt QEMU/KVM Virtual Machines using terraform.

For a vSphere equivalent see the [rgl/terraform-rke-vsphere-cloud-provider-example](https://github.com/rgl/terraform-rke-vsphere-cloud-provider-example). 

For a Pulumi equivalent see the [rgl/dotnet-pulumi-libvirt-rke-example repository](https://github.com/rgl/dotnet-pulumi-libvirt-rke-example).

## Usage (Ubuntu 20.04 host)

Create and install the [Ubuntu 20.04 vagrant box](https://github.com/rgl/ubuntu-vagrant) (because this example uses its base disk).

Install `terraform`:

```bash
wget https://releases.hashicorp.com/terraform/1.2.9/terraform_1.2.9_linux_amd64.zip
unzip terraform_1.2.9_linux_amd64.zip
sudo install terraform /usr/local/bin
rm terraform terraform_*_linux_amd64.zip
```

Install `kubectl`:

```bash
kubectl_version='1.22.11'
wget -qO /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo 'deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
sudo apt-get update
kubectl_package_version="$(apt-cache madison kubectl | awk "/$kubectl_version-/{print \$3}")"
sudo apt-get install -y "kubectl=$kubectl_package_version"
```

Launch this example:

```bash
export TF_VAR_controller_count=1    # number of controller nodes.
export TF_VAR_worker_count=1        # number of worker nodes.
time make recreate
```

Test accessing the cluster:

```bash
terraform output --raw rke_state >rke_state.json # might be useful for troubleshooting.
terraform output --raw kubeconfig >kubeconfig.yaml
export KUBECONFIG="$PWD/kubeconfig.yaml"
kubectl get nodes -o wide
```

Destroy everything:

```bash
make destroy
```
