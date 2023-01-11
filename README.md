# Debian image for QEMU

This repository contains [Packer](https://www.packer.io) configuration to build
"cloud-like" Debian images for QEMU.

## How to use these images?

### As an alternative Packer builder

You can reuse these images to test locally your own Packer configuration
instead of building images on your favorite cloud provider.

You can start with the following configuration:

* it downloads the image built using this repository from Github
* configures a new, larger QCOW disk to host the VM while Packer is building
* runs a basic provisioner (you may want to change this!)

```json
{
  "min_packer_version": "1.3.3",
  "variables": {
    "qemu_output_dir": "qemu-images",
    "qemu_output_name": "my-build.qcow2",
    "qemu_source_checksum_url": "https://github.com/multani/packer-qemu-debian/releases/download/10.0.0-1/SHA256SUMS",
    "qemu_source_iso": "https://github.com/multani/packer-qemu-debian/releases/download/10.0.0-1/debian-10.0.0-1.qcow2",
    "qemu_ssh_password": "debian",
    "qemu_ssh_username": "debian"
  },

  "builders": [
    {
      "type": "qemu",
      "iso_url": "{{ user `qemu_source_iso` }}",
      "iso_checksum_url": "{{ user `qemu_source_checksum_url` }}",
      "iso_checksum_type": "sha256",

      "disk_image": true,
      "accelerator": "kvm",
      "boot_wait": "1s",
      "format": "qcow2",
      "use_backing_file": true,

      "disk_size": 8000,

      "headless": true,
      "shutdown_command": "echo '{{ user `qemu_ssh_password` }}'  | sudo -S /sbin/shutdown -hP now",

      "ssh_host_port_max": 2229,
      "ssh_host_port_min": 2222,
      "ssh_password": "{{ user `qemu_ssh_password` }}",
      "ssh_username": "{{ user `qemu_ssh_username` }}",
      "ssh_wait_timeout": "1000s",

      "output_directory": "{{ user `qemu_output_dir` }}",
      "vm_name": "{{ user `qemu_output_name` }}"
    }
  ],

  "provisioners": [
    {
      "type": "shell",
      "inline": [
        "echo '  *** Running my favorite provisioner'"
      ]
    }
  ]
}
```

Save this file as `packer.json`, then you can run:

```
$ packer validate packer.json
Template validated successfully.
$ packer build -timestamp-ui packer.json
qemu output will be in this color.

2019-01-20T12:09:19+01:00: ==> qemu: Retrieving ISO
2019-01-20T12:09:20+01:00:     qemu: Found already downloaded, initial checksum matched, no download needed: https://github.com/multani/packer-qemu-debian/releases/download/10.0.0-1/debian-10.0.0-1.qcow2
2019-01-20T12:09:20+01:00: ==> qemu: Creating hard drive...
2019-01-20T12:09:20+01:00: ==> qemu: Resizing hard drive...
2019-01-20T12:09:20+01:00: ==> qemu: Found port for communicator (SSH, WinRM, etc): 2226.
2019-01-20T12:09:20+01:00: ==> qemu: Looking for available port between 5900 and 6000 on 127.0.0.1
2019-01-20T12:09:20+01:00: ==> qemu: Starting VM, booting disk image
2019-01-20T12:09:20+01:00: ==> qemu: Overriding defaults Qemu arguments with QemuArgs...
2019-01-20T12:09:22+01:00: ==> qemu: Waiting 1s for boot...
2019-01-20T12:09:23+01:00: ==> qemu: Connecting to VM via VNC (127.0.0.1:5957)
2019-01-20T12:09:23+01:00: ==> qemu: Typing the boot command over VNC...
2019-01-20T12:09:23+01:00: ==> qemu: Using ssh communicator to connect: 127.0.0.1
2019-01-20T12:09:23+01:00: ==> qemu: Waiting for SSH to become available...
2019-01-20T12:09:29+01:00: ==> qemu: Connected to SSH!
2019-01-20T12:09:29+01:00: ==> qemu: Provisioning with shell script: /tmp/packer-shell962483776
2019-01-20T12:09:29+01:00:     qemu:   *** Running my favorite provisioner
2019-01-20T12:09:29+01:00: ==> qemu: Gracefully halting virtual machine...
2019-01-20T12:09:31+01:00: ==> qemu: Converting hard drive...
2019-01-20T12:09:36+01:00: Build 'qemu' finished.

==> Builds finished. The artifacts of successful builds are:
--> qemu: VM files in directory: qemu-images
```

This gives you a test image in which you can test your provisioning and
configuration in less than 10 seconds.

This creates a pretty large image in the end, you can pass these additional
flags to Packer to reduce the final size (at the expense of a longer build):

```json
  "disk_compression": true,
  "disk_detect_zeroes": "unmap",
  "disk_discard": "unmap",
  "skip_compaction": false,
```


### As a virtual machine image for libvirt

Using the [Terraform provider for
libvirt](https://github.com/dmacvicar/terraform-provider-libvirt) you can
create a new VM with libvirt in order to test your
[cloud-init](https://cloudinit.readthedocs.io/) configuration for example:

```hcl
provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_volume" "debian" {
  name   = "debian.qcow2"
  pool   = "default"
  source = "https://github.com/multani/packer-qemu-debian/releases/download/10.0.0-1/debian-10.0.0-1.qcow2"
  format = "qcow2"
}

data "template_file" "user_data" {
  template = <<EOF
packages:
 - pwgen
 - nginx-full
EOF
}

resource "libvirt_cloudinit_disk" "cloud_init" {
  name           = "cloud-init.iso"
  user_data      = "${data.template_file.user_data.rendered}"
}

resource "libvirt_domain" "test" {
  name   = "test"
  memory = "512"
  vcpu   = 1

  cloudinit = "${libvirt_cloudinit_disk.cloud_init.id}"

  network_interface {
    network_name = "default"
  }

  disk {
    volume_id = "${libvirt_volume.debian.id}"
  }
}
```

See the [provider
documentation](https://github.com/dmacvicar/terraform-provider-libvirt/tree/master/website/docs)
for more details.


## How to build these images?
```shell
git tag -a -m "Debian 11.6.0-1" 11.6.0-1
git describe --debug
git push origin 11.6.0-1
make clean
make
```
or
```shell
eatmydata make OUTPUT_DIR=/tmp/output clean
eatmydata make OUTPUT_DIR=/tmp/output
```

