variable "output_dir" {
  type    = string
  default = "output"
}

variable "output_name" {
  type    = string
  default = "debian.qcow2"
}

variable "version" {
  type    = string
  default = "10.10.0"
}


variable "ssh_password" {
  type    = string
  default = "debian"
}

variable "ssh_username" {
  type    = string
  default = "debian"
}

# "timestamp" template function replacement
locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")

  archs = {
      #amd64 = {
        #cpu_arch = "x86_64"
        #version = var.version
        #arch = "amd64"
        #machine_type = "pc"
          # accelerator = "kvm"
      #}

      arm64 = {
        cpu_arch = "aarch64"
        version = var.version
        arch = "arm64"
        machine_type = "raspi3b"
  accelerator = "tcg"
      }
  }
}



build {
  description = <<EOF
This builder builds a QEMU image from a Debian "netinst" CD ISO file.
It contains a few basic tools and can be use as a "cloud image" alternative.
EOF

  dynamic "source" {
    for_each = local.archs

    # equivalent to `source "amazon-ebs.base"`
    labels = ["qemu.debian"]

    content {
      # "amazon-ebs.arm64" instead of "amazon-ebs.base" (the label)
      name = source.value.cpu_arch

      # Current images in https://cdimage.debian.org/cdimage/release/
      # Previous versions are in https://cdimage.debian.org/cdimage/archive/
      iso_url = "https://cdimage.debian.org/cdimage/release/${source.value.version}/${source.value.arch}/iso-cd/debian-${source.value.version}-${source.value.arch}-netinst.iso"
      iso_checksum = "file:https://cdimage.debian.org/cdimage/release/${source.value.version}/${source.value.arch}/iso-cd/SHA256SUMS"
      qemu_binary = "qemu-system-${source.value.cpu_arch}"

      machine_type = source.value.machine_type
      accelerator = source.value.accelerator
    }
  }

  provisioner "file" {
    destination = "/tmp/configure-qemu-image.sh"
    source      = "configure-qemu-image.sh"
  }

  provisioner "shell" {
    inline = [
      "sh -cx 'sudo bash /tmp/configure-qemu-image.sh'"
    ]
  }

  post-processor "manifest" {
    keep_input_artifact = true
  }

  post-processor "shell-local" {
    keep_input_artifact = true
    inline = [
      "./post-process.sh ${var.output_dir}/${var.output_name}"
    ]
  }
}


source qemu "debian" {
  cpus = 1
  # The Debian installer warns with a dialog box if there's not enough memory
  # in the system.
  memory      = 1024
  disk_size   = 8000

  headless = false

  # Serve the `http` directory via HTTP, used for preseeding the Debian installer.
  http_directory = "http"
  http_port_min  = 9990
  http_port_max  = 9999

  # SSH ports to redirect to the VM being built
  host_port_min = 2222
  host_port_max = 2229
  # This user is configured in the preseed file.
  ssh_password     = "${var.ssh_password}"
  ssh_username     = "${var.ssh_username}"
  ssh_wait_timeout = "1000s"

  shutdown_command = "echo '${var.ssh_password}'  | sudo -S /sbin/shutdown -hP now"

  # Builds a compact image
  disk_compression   = true
  disk_discard       = "unmap"
  skip_compaction    = false
  disk_detect_zeroes = "unmap"

  format           = "qcow2"
  output_directory = "${var.output_dir}"
  vm_name          = "${var.output_name}"

  boot_wait = "1s"
  boot_command = [
    "<down><tab>", # non-graphical install
    "preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "language=en locale=en_US.UTF-8 ",
    "country=CH keymap=fr ",
    "hostname=packer domain=test ", # Should be overriden after DHCP, if available
    "<enter><wait>",
  ]
}
