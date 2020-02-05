#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function with_temp_mount () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local TGT_LABEL="$1"; shift
  local TGT_DISK="/dev/disk/by-label/$TGT_LABEL"
  local TGT_MNPT="/media/$USER/$TGT_LABEL"
  [ -b "$TGT_DISK" ] || return 3$(echo "E: not a block device: $TGT_DISK" >&2)
  local TGT_WAS_MOUNTED=
  if mountpoint -q "$TGT_MNPT"; then
    TGT_WAS_MOUNTED=+
  else
    udiskmnt "$TGT_LABEL"
  fi
  mountpoint -q "$TGT_MNPT" || return 4$(echo "E: not mounted: $TGT_MNPT" >&2)

  local TGT_DEST="$TGT_MNPT"
  # ^-- might be changed by {$2 == 'source'}-d script
  "$@" || return $?

  if [ -n "$TGT_WAS_MOUNTED" ]; then
    [ ! -d "$TGT_DEST" ] || thun "$TGT_DEST" || return $?
  else
    echo -n "D: umounting $TGT_MNPT… "
    umount "$TGT_MNPT" || return $?
    echo 'done.'
  fi
}










[ "$1" == --lib ] && return 0; with_temp_mount "$@"; exit $?
