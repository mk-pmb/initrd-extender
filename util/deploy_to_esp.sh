#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function copy_to_esp () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m "$BASH_SOURCE"/..)"
  cd "$SELFPATH"/.. || return $?
  busybox sh -n initrd-extender.sh || return $?

  source "$SELFPATH"/with_temp_mount.sh --lib || return $?
  with_temp_mount "$1" copy_to_esp__doit || return $?
}


function copy_to_esp__doit () {
  sudo cp --verbose --target-directory=trigger.dest/ \
    -- initrd-extender.sh || return $?
  sudo -E update-initramfs -uk all || return $?
  sudo cp --verbose --target-directory="${TGT_DEST:-E_NO_TGT_DEST}" \
    -- /boot/initrd.img-* || return $?
}










[ "$1" == --lib ] && return 0; copy_to_esp "$@"; exit $?
