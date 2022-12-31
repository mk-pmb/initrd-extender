#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function with_temp_mount () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local TGT_LABEL="$1"; shift
  local TGT_DISK="/dev/disk/by-label/$TGT_LABEL"
  [ -b "$TGT_DISK" ] || return 3$(echo "E: not a block device: $TGT_DISK" >&2)
  local TGT_MNPT=
  local TGT_WAS_MOUNTED_ALREADY=
  if find_mountpoint; then
    TGT_WAS_MOUNTED_ALREADY=+
  else
    udiskmnt "$TGT_LABEL"
  fi
  find_mountpoint || return 4$(
    echo "E: Cannot find mountpoint for: $TGT_LABEL" >&2)

  local TGT_DEST="$TGT_MNPT"
  # ^-- might be changed by {$2 == 'source'}-d script
  "$@" || return $?

  if [ -n "$TGT_WAS_MOUNTED_ALREADY" ]; then
    [ ! -d "$TGT_DEST" ] || thun "$TGT_DEST" || return $?
  else
    echo -n "D: umounting $TGT_MNPT… "
    umount "$TGT_MNPT" || return $?
    echo 'done.'
  fi
}


function find_mountpoint () {
  local M=
  for M in "/media/$USER"/{$TGT_LABEL,${TGT_LABEL,,}}; do
    mountpoint -q "$M" || continue
    TGT_MNPT="$M"
    return 0
  done
  return 3
}










[ "$1" == --lib ] && return 0; with_temp_mount "$@"; exit $?
