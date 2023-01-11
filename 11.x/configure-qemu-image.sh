#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# This provisions an very basic Debian installation, fresh from a basic netinst
# installation, into something that could be used like a "cloud image", similar
# to bare Debian VM images found on public cloud providers.


# Boot more quickly
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
update-grub

# Configure localepurge to remove unused locales. This makes the image smaller.
echo "localepurge	localepurge/use-dpkg-feature	boolean	true" | debconf-set-selections
###echo "localepurge	localepurge/nopurge	multiselect	en, en_US.UTF-8, fr, fr_CH.UTF-8, fr_FR.UTF-8"  | debconf-set-selections
#echo "localepurge	localepurge/nopurge	multiselect	en, en_US.UTF-8, de, de_DE.UTF-8, de_DE.UTF-8"  | debconf-set-selections
echo "localepurge	localepurge/nopurge	multiselect	en, en_US.UTF-8"  | debconf-set-selections

# Disable floppy support - it's (probably!) not needed and prevent spurious warnings from displaying.
echo "blacklist floppy" > /etc/modprobe.d/blacklist-floppy.conf
rmmod floppy
update-initramfs -u

# Default packages installed, which makes the image slightly more than just a
# fresh Debian install, and ready to be started as a "cloud image".
# These tools are pretty important to have for QEMU, as it makes the image smarter.
apt-get update
apt-get install --no-install-recommends \
    acpid \
    cloud-guest-utils \
    cloud-init \
    lsb-release \
    net-tools \
    qemu-guest-agent \
    --yes

# These tools are just "nice to have".
apt-get install --no-install-recommends \
    curl \
    less \
    localepurge \
    python3-distutils \
    rsync \
    vim \
    --yes


# Configure the main network interface as "auto".
# This ensures the main network interface is up when the systemd
# "networking.service" has completed.
# This in turn allows subsequent services to rely on the ability to query the
# network settings of that main interface.
cat <<EOF > /etc/network/interfaces
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto ens3
allow-hotplug ens3
iface ens3 inet dhcp
EOF


# Reconfigure cloud-init
# Don't "lock" the "debian" user password. It is configured directly by the
# preseeding and all the rest depends on it. Cloud-init, with the default
# configuration, overrides this user's settings and prevents from using it
# without a SSH key (which needs to be passed by the "cloud" user-data, which
# we may not always have.)
cat <<EOF > /etc/cloud/cloud.cfg.d/91-debian-user.cfg
# System and/or distro specific settings
# (not accessible to handlers/transforms)
system_info:
   # This will affect which distro class gets used
   distro: debian
   # Default user name + that default users groups (if added/used)
   default_user:
     name: debian
     lock_passwd: false
     gecos: Debian
     groups: [adm, audio, cdrom, dialout, dip, floppy, netdev, plugdev, sudo, video]
     sudo: ["ALL=(ALL) NOPASSWD:ALL"]
     shell: /bin/bash
   # Other config here will be given to the distro class and/or path classes
   paths:
      cloud_dir: /var/lib/cloud/
      templates_dir: /etc/cloud/templates/
      upstart_dir: /etc/init/
   package_mirrors:
     - arches: [default]
       failsafe:
         primary: http://deb.debian.org/debian
         security: http://security.debian.org/
   ssh_svcname: ssh
EOF

# Don't let cloud-init to take over the network configuration.
# This prevents to have more fine-grained configuration and enable lot of
# automagic configuration on interfaces that could (should!) be managed outside
# of cloud-init.
cat <<EOF > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
network:
  config: disabled
EOF

# Configure cloud-init to allow image instanciation-time customization.
# The only cloud-init "datasources" that make sense for this image are:
#
# * "None": this is the last resort when nothing works. This prevents
#   cloud-init from exiting with an error because it didn't find any datasource
#   at all. This in turns allow to start the QEMU image with no
#
# * "NoCloud": this fetches the cloud-init data from a ISO disk mounted into
#   the new VM or from other non-network resources. See
#   https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html
#   for more information.
cat <<EOF > /etc/cloud/cloud.cfg.d/99-nocloud-datasource.cfg
datasource_list:
- NoCloud
- None
EOF

# Disable warning about missing datasource. This type of image may run in a
# very special environment where we want to control what's happening, without
# having a specific datasource provided.
cat <<EOF > /etc/cloud/cloud.cfg.d/99-warnings.cfg
#cloud-config
warnings:
  dsid_missing_source: off
EOF

# Configure cloud-init to start once multi-user has been started.
systemctl add-wants multi-user.target cloud-init.target

# Prevent clearing the terminal when systemd invokes the initial getty
# From: https://wiki.debian.org/systemd#Missing_startup_messages_on_console.28tty1.29_after_the_boot
SYSTEMD_NO_CLEAR_FILE=/etc/systemd/system/getty@tty1.service.d/no-clear.conf
mkdir --parents "$(dirname "$SYSTEMD_NO_CLEAR_FILE")"
cat <<EOF > "$SYSTEMD_NO_CLEAR_FILE"
[Service]
TTYVTDisallocate=no
EOF
systemctl daemon-reload


# Configure the ACPI daemon to gently turn off the VM when the "power button"
# is pressed.
cp /usr/share/doc/acpid/examples/powerbtn /etc/acpi/events/powerbtn
cp /usr/share/doc/acpid/examples/powerbtn.sh /etc/acpi/powerbtn.sh
chmod +x /etc/acpi/powerbtn.sh
systemctl enable acpid


# The QEMU guest agent helps the host to run the VM more optimally.
# See https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/chap-qemu_guest_agent
systemctl enable qemu-guest-agent

# Remove all but the lastest kernel
apt-get autoremove --yes --purge $(dpkg -l "linux-image*" | grep "^ii" | grep -v linux-image-amd64 | head -n -1 | cut -d " " -f 3)

# Finally, cleanup all the things
apt-get install --yes deborphan # Let's try to remove some more
apt-get autoremove \
  $(deborphan) \
  deborphan \
  dictionaries-common \
  iamerican \
  ibritish \
  localepurge \
  task-english \
  tasksel \
  tasksel-data \
  --purge --yes

# Remove downloaded .deb files
apt-get clean

# Remove instance-specific files: we want this image to be as "impersonal" as
# possible.
find \
  /var/cache/apt \
  /var/lib/apt \
  /var/lib/dhcp \
  /var/log \
  -mindepth 1 -print -delete

rm -vf \
  /etc/network/interfaces.d/50-cloud-init.cfg \
  /etc/adjtime \
  /etc/hostname \
  /etc/hosts \
  /etc/ssh/*key* \
  /var/cache/ldconfig/aux-cache \
  /var/lib/systemd/random-seed \
  ~/.bash_history \
  ${SUDO_USER}/.bash_history


# From https://www.freedesktop.org/software/systemd/man/machine-id.html:
# For operating system images which are created once and used on multiple
# machines, [...] /etc/machine-id should be an empty file in the generic file
# system image.
truncate -s 0 /etc/machine-id

# Recreate some useful files.
touch /var/log/lastlog
chown root:utmp /var/log/lastlog
chmod 664 /var/log/lastlog

# Display some usage information
df -h

# Free all unused storage block. This makes the final image smaller.
echo "RUN fstrim --all --verbose"
fstrim --all --verbose


# Display some usage information
df -h


# Finally, remove this very script.
rm -f $(readlink -f $0)
