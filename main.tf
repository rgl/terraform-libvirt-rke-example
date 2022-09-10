# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.2.9"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    random = {
      source = "hashicorp/random"
      version = "3.4.3"
    }
    # see https://registry.terraform.io/providers/hashicorp/template
    template = {
      source = "hashicorp/template"
      version = "2.2.0"
    }
    # see https://registry.terraform.io/providers/dmacvicar/libvirt
    # see https://github.com/dmacvicar/terraform-provider-libvirt
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.6.14"
    }
    # see https://registry.terraform.io/providers/rancher/rke
    # see https://github.com/rancher/terraform-provider-rke
    rke = {
      source = "rancher/rke"
      version = "1.3.3"
    }
  }
}

variable "prefix" {
  default = "rke_example"
}

variable "kubernetes_version" {
  # see https://github.com/rancher/rke/releases/tag/v1.3.13
  default = "v1.20.15-rancher2-2"
}

variable "controller_count" {
  type = number
  default = 1
  validation {
    condition = var.controller_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "worker_count" {
  type = number
  default = 1
  validation {
    condition = var.worker_count >= 1
    error_message = "Must be 1 or more."
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

provider "rke" {
  log_file = "rke.log"
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/website/docs/r/network.markdown
resource "libvirt_network" "example" {
  name = var.prefix
  mode = "nat"
  domain = "example.test"
  addresses = ["10.17.3.0/24"]
  dhcp {
    enabled = false
  }
  dns {
    enabled = true
    local_only = false
  }
}

# a cloud-init disk for the controller nodes.
# NB this creates an iso image that will be used by the NoCloud cloud-init datasource.
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/website/docs/r/cloudinit.html.markdown
# see journactl -u cloud-init
# see /run/cloud-init/*.log
# see https://cloudinit.readthedocs.io/en/latest/topics/examples.html#disk-setup
# see https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html#datasource-nocloud
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/libvirt/cloudinit_def.go#L133-L162
resource "libvirt_cloudinit_disk" "controller" {
  count = var.controller_count
  name = "${var.prefix}_c${count.index}_cloudinit.iso"
  user_data = <<-EOF
    #cloud-config
    hostname: c${count.index}
    users:
      - name: vagrant
        passwd: '$6$rounds=4096$NQ.EmIrGxn$rTvGsI3WIsix9TjWaDfKrt9tm3aa7SX7pzB.PSjbwtLbsplk1HsVzIrZbXwQNce6wmeJXhCq9YFJHDx9bXFHH.'
        lock_passwd: false
        ssh-authorized-keys:
          - ${file("~/.ssh/id_rsa.pub")}
    runcmd:
      - sed -i '/vagrant insecure public key/d' /home/vagrant/.ssh/authorized_keys
      # make sure the vagrant account is not expired.
      # NB this is needed when the base image expires the vagrant account.
      - usermod --expiredate '' vagrant
    EOF
}

# a cloud-init disk for the worker nodes.
resource "libvirt_cloudinit_disk" "worker" {
  count = var.worker_count
  name = "${var.prefix}_w${count.index}_cloudinit.iso"
  user_data = <<-EOF
    #cloud-config
    hostname: w${count.index}
    users:
      - name: vagrant
        passwd: '$6$rounds=4096$NQ.EmIrGxn$rTvGsI3WIsix9TjWaDfKrt9tm3aa7SX7pzB.PSjbwtLbsplk1HsVzIrZbXwQNce6wmeJXhCq9YFJHDx9bXFHH.'
        lock_passwd: false
        ssh-authorized-keys:
          - ${file("~/.ssh/id_rsa.pub")}
    runcmd:
      - sed -i '/vagrant insecure public key/d' /home/vagrant/.ssh/authorized_keys
      # make sure the vagrant account is not expired.
      # NB this is needed when the base image expires the vagrant account.
      - usermod --expiredate '' vagrant
    EOF
}

# this uses the vagrant ubuntu image imported from https://github.com/rgl/ubuntu-vagrant.
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/website/docs/r/volume.html.markdown
resource "libvirt_volume" "controller" {
  count = var.controller_count
  name = "${var.prefix}_c${count.index}.img"
  base_volume_name = "ubuntu-20.04-amd64_vagrant_box_image_0_box.img"
  format = "qcow2"
  size = 66*1024*1024*1024 # 66GiB. the root FS is automatically resized by cloud-init growpart (see https://cloudinit.readthedocs.io/en/latest/topics/examples.html#grow-partitions).
}

resource "libvirt_volume" "worker" {
  count = var.worker_count
  name = "${var.prefix}_w${count.index}.img"
  base_volume_name = "ubuntu-20.04-amd64_vagrant_box_image_0_box.img"
  format = "qcow2"
  size = 66*1024*1024*1024 # 66GiB. the root FS is automatically resized by cloud-init growpart (see https://cloudinit.readthedocs.io/en/latest/topics/examples.html#grow-partitions).
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/website/docs/r/domain.html.markdown
resource "libvirt_domain" "controller" {
  count = var.controller_count
  name = "${var.prefix}_c${count.index}"
  #firmware = "/usr/share/OVMF/OVMF_CODE.fd"
  cpu {
    mode = "host-passthrough"
  }
  vcpu = 2
  memory = 2*1024
  qemu_agent = true
  cloudinit = libvirt_cloudinit_disk.controller[count.index].id
  disk {
    volume_id = libvirt_volume.controller[count.index].id
    scsi = true
  }
  network_interface {
    network_id = libvirt_network.example.id
    wait_for_lease = true
    addresses = ["10.17.3.${10+count.index}"]
  }
  connection {
    type = "ssh"
    user = "vagrant"
    host = self.network_interface[0].addresses[0]
    private_key = file("~/.ssh/id_rsa")
  }
  provisioner "file" {
    source = "provision.sh"
    destination = "/tmp/provision.sh"
  }
  # NB in a non-test environment, all the dependencies should already be in
  #    the base image and we would not needed to ad-hoc provision anything
  #    here.
  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/provision.sh"
    ]
  }
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/website/docs/r/domain.html.markdown
resource "libvirt_domain" "worker" {
  count = var.worker_count
  name = "${var.prefix}_w${count.index}"
  #firmware = "/usr/share/OVMF/OVMF_CODE.fd"
  cpu {
    mode = "host-passthrough"
  }
  vcpu = 2
  memory = 2*1024
  qemu_agent = true
  cloudinit = libvirt_cloudinit_disk.worker[count.index].id
  disk {
    volume_id = libvirt_volume.worker[count.index].id
    scsi = true
  }
  network_interface {
    network_id = libvirt_network.example.id
    wait_for_lease = true
    addresses = ["10.17.3.${20+count.index}"]
  }
  connection {
    type = "ssh"
    user = "vagrant"
    host = self.network_interface[0].addresses[0]
    private_key = file("~/.ssh/id_rsa")
  }
  provisioner "file" {
    source = "provision.sh"
    destination = "/tmp/provision.sh"
  }
  # NB in a non-test environment, all the dependencies should already be in
  #    the base image and we would not needed to ad-hoc provision anything
  #    here.
  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/provision.sh"
    ]
  }
}

# see https://registry.terraform.io/providers/rancher/rke/1.3.3/docs/resources/cluster
resource "rke_cluster" "example" {
  kubernetes_version = var.kubernetes_version
  dynamic "nodes" {
    for_each = libvirt_domain.controller
    iterator = it
    content {
      address = it.value.network_interface[0].addresses[0]
      user = "vagrant"
      role = ["controlplane", "etcd"]
      ssh_key = file("~/.ssh/id_rsa")
    }
  }
  dynamic "nodes" {
    for_each = libvirt_domain.worker
    iterator = it
    content {
      address = it.value.network_interface[0].addresses[0]
      user = "vagrant"
      role = ["worker"]
      ssh_key = file("~/.ssh/id_rsa")
    }
  }
  upgrade_strategy {
    drain = true
    max_unavailable_worker = "20%"
  }
}

output "rke_state" {
  sensitive = true
  value = rke_cluster.example.rke_state
}

output "kubeconfig" {
  sensitive = true
  value = rke_cluster.example.kube_config_yaml
}
