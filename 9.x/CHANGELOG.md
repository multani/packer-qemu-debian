# Releases

## 9.6.0-3

* Fix the reinitialisation of /etc/machine-id.
  The file must be there but empty.

## 9.6.0-2

* Add the `cloud-guest-utils` in the image.
  This allows the cloud-init `growpart` module to be used by default.

## 9.6.0-1

* Initial release using Debian 9.6.0