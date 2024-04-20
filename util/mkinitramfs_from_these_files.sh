#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
#
# This script makes a pluggable initrd file that GRUB2 can load after
# loading your regular initrd created by mkinitramfs. For details, see:
# https://www.gnu.org/software/grub/manual/grub/html_node/initrd.html


function miftf_main () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local DEST="$1"; shift
  [ -n "$DEST" ] || return 4$(
    echo E: 'No source directory or destination given.' >&2)
  local SRC_DIR=.
  [ "$#" -ge 1 ] || miftf_guess_sources || return $?

  local PIPELINE='miftf_pack "$@"'
  case "$DEST" in
    *.gz ) PIPELINE+='| gzip';;
  esac

  # echo "dest: >> $DEST <<"
  eval "$PIPELINE" >"$DEST" || return $?
  du --bytes -- "$DEST" || return $?
}


function miftf_guess_sources () {
  [ -d "$DEST" ] || return 4$(
    echo E: 'When invoked with only one argument, it must be a directory.' >&2)
  while [[ "$DEST" == */ ]]; do DEST="${DEST%/}"; done
  [ -n "$DEST" ] || return 4$(
    echo E: 'Cannot use root directory as source.' >&2)
  SRC_DIR="$DEST"
  [ "${SRC_DIR:0:1}" == / ] || SRC_DIR="$PWD/$SRC_DIR"
  DEST="$(basename -- "$DEST")"
  DEST="${DEST%.}"
  [ -z "$DEST" ] || DEST+=.
  DEST+='initrd.gz'
}


function miftf_pack () {
  local ABS_DEST="$(readlink -f -- "$DEST")"
  [ "$ABS_DEST" -ef "$DEST" ] || return 4$(
    echo E: "Failed to readlink destination: $DEST" >&2)

  pushd -- "$SRC_DIR" >/dev/null || return 6$(
    echo E: "Failed to chdir to source directory: $SRC_DIR" >&2)
  # echo "D: eval: $HOW" >&2

  local FIND=(
    find "$@"
    -mount  # constrain the `find` command to same filesystem.
    -not -samefile "$ABS_DEST"
    )
  local PACK=(
    cpio
    --create
    --format=crc
    --force-local
    --owner=+0:+0
    --reproducible
    --quiet
    )

  "${FIND[@]}" | sed -re 's:^\./::' | sort --version-sort | "${PACK[@]}"
  local RV_SUM="${PIPESTATUS[*]}"
  let RV_SUM="${RV_SUM// /+}"
  popd >/dev/null || return 6$(echo E: 'Failed to chdir back' >&2)
  [ "$RV_SUM" == 0 ] || return $RV_SUM$(
    echo E: "Pipeline failed: rv_sum=$RV_SUM" >&2)
}















miftf_main "$@"; exit $?
