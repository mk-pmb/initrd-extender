#!/bin/sh
# -*- coding: utf-8, tab-width: 2 -*-

labelmount () {
  local LABEL="$1"
  local DDBL='/dev/disk/by-label'

  if [ -z "$LABEL" ]; then
    echo
    ls -1 "$DDBL"
    echo
    return 0
  fi

  local MNTP="/mnt/$(echo "$LABEL" | tr A-Z a-z)"
  local DISK="$DDBL/$LABEL"
  [ -b "$DISK" ] || return 3$(echo "E: found no disk labeled '$LABEL'" >&2)

  local M_OPT='defaults,noatime'
  local USE_SUDO=
  [ -n "$USER" ] || local USER="$(whoami)"
  if [ "$USER" != root ]; then
    USE_SUDO='sudo -E'
    # not supported by ext3 -> # M_OPT="$M_OPT,uid=$USER,gid=adm"
  fi
  mount | grep -qFe " on $MNTP type " && return 0
  $USE_SUDO mkdir -p -- "$MNTP"
  $USE_SUDO mount "$DISK" "$MNTP" -o "$M_OPT" || return $?
}


[ "$1" = --lib ] && return 0; labelmount "$@"; exit $?
