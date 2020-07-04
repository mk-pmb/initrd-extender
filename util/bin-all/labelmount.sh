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
  mount | grep -qFe " on $MNTP type " && return 0
  mkdir -p -- "$MNTP"
  mount "$DISK" "$MNTP" -o defaults,noatime || return $?
}


[ "$1" = --lib ] && return 0; labelmount "$@"; exit $?
