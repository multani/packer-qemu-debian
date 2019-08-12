variable "name" {
  default = "test"
}

variable "libvirt_bridge" {
  default = "virbr0"
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_volume" "debian" {
  name   = "debian-10.0.0-1.qcow2"
  source = "https://github.com/multani/packer-qemu-debian/releases/download/10.0.0-1/debian-10.0.0-1.qcow2"
  format = "qcow2"
}

resource "libvirt_volume" "root" {
  name           = "${var.name}-root.qcow2"
  base_volume_id = "${libvirt_volume.debian.id}"
}

data "template_file" "user_data" {
  template = <<EOF
#cloud-config
hostname: ${var.name}
EOF
}

resource "libvirt_cloudinit_disk" "cloud_init" {
  name      = "${var.name}-cloud-init.iso"
  user_data = "${data.template_file.user_data.rendered}"
}

resource "libvirt_domain" "test" {
  name   = "${var.name}"
  memory = "512"
  vcpu   = 1

  cloudinit = "${libvirt_cloudinit_disk.cloud_init.id}"

  network_interface {
    bridge = "${var.libvirt_bridge}"
  }

  disk {
    volume_id = "${libvirt_volume.root.id}"
  }
}
