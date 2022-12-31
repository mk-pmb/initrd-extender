#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function irlux_cli_prep () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local DBGLV="${DEBUGLEVEL:-0}"
  [ -n "$irdex_lvm_disk" ] || local irdex_lvm_disk="${irdex_host}_luks"
  case "$irdex_lvm_disk" in
    /* ) ;;
    * ) local irdex_lvm_disk="/dev/disk/by-partlabel/$irdex_lvm_disk";;
  esac
  [ -n "$irdex_lvm_pv" ] || local irdex_lvm_pv="pv_${irdex_host}_luks"
  [ -n "$irdex_lvm_vg" ] || local irdex_lvm_vg="vg_${irdex_host}_luks"

  local OP= ARG= KEY_BASE64=
  while [ "$#" -ge 1 ]; do
    OP="$1"; shift
    ARG=
    case "$OP" in
      *:*:* ) ARG="${OP#*:}";;
      *: ) ARG="$1"; shift;;
      *:* ) ARG="${OP#*:}";;
    esac
    OP="${OP%%:*}"
    [ "$DBGLV" -ge 2 ] && echo "D: op='$OP', arg='$ARG'" >&2
    case "$OP" in
      cd | \
      echo | \
      sleep | \
      eval ) "$OP" -- "$ARG";;
      * ) irlux_"$OP" "$ARG" || return $?;;
    esac
  done
}


function dbg_vdo () {
  [ "$DBGLV" -ge "$1" ] && echo "D: run: ${*:2}" >&2
  "${@:2}" || return $?$(echo "W: failed: ${*:2}, rv=$?" >&2)
}


function irlux_wait_for_disk () {
  irdex retryable 15 2s test -b "$irdex_lvm_disk" || return 4$(
    echo "E: not a block device: $irdex_lvm_disk" >&2)
}


function irlux_unlock_by_keyfile () {
  local KEY_FILE="$1"; shift
  case "$KEY_FILE" in
    /dev/fd/[3-9]* | /dev/fd/[1-9][0-9]* )
      echo "E: It's not reliable to pass $KEY_FILE as key file:" \
        'lvm might consider extra file descriptors as accidentially' \
        'leaked, and thus might flinch. Instead, use stdin ("-").' >&2
      return 3;;
  esac
  local CRY=(
    cryptsetup
    open
    --type=luks
    --key-file "$KEY_FILE"
    $irdex_luksopen_opt
    --
    "$irdex_lvm_disk"
    "$irdex_lvm_pv"
    )
  dbg_vdo 2 "${CRY[@]}" || return $?$(echo "E: Unable to open disk" \
    "'$irdex_lvm_disk' as '$irdex_lvm_pv' using key file '$KEY_FILE'." >&2)
  dbg_vdo 2 irdex retryable 5 1s test -b /dev/mapper/"$irdex_lvm_pv" \
    || return $?
  dbg_vdo 2 lvm vgchange --activate y "$irdex_lvm_vg" || return $?
}


function irlux_boot () {
  dbg_vdo 2 irdex retryable 5 1s test -b "$ROOT" || return $?
  dbg_vdo 2 irdex actually_mount "$ROOT" "$rootmnt" || return $?
  cd / || return $?
  dbg_vdo 2 irdex umount_all_mnt || return $?
}


function irlux_base64key_read () {
  local KEEP= ADD= LN=
  case "$ARG" in
    clear ) KEY_BASE64=; return 0;;
    '+'* ) KEEP="$KEY_BASE64"; ARG="${ARG:1}";;
  esac
  case "$ARG" in
    pipe ) ARG+=':9009009';;
  esac
  case "$ARG" in
    blind ) IFS= read -p "$ARG" -rs ADD;;
    pipe:* )
      ARG="${ARG#*:}" # max line count
      [ "$DBGLV" -ge 2 ] && echo "D: readling key from pipe, maxln=$ARG" >&2
      while [ "${ARG:-0}" -ge 1 ]; do
        (( ARG -= 1 ))
        LN=
        IFS= read -rs LN || break   # e.g. eof
        LN="${LN//$'\r'/}"
        case "$LN" in
          '' ) ;;
          . | *::* ) break;;
          * ) ADD+="$LN";;
        esac
      done;;
    * ) echo "E: unsupported $FUNCNAME mode: '$ARG'" >&2; return 2;;
  esac
  [ -n "$ADD" ] || return 0
  KEY_BASE64="$KEEP$ADD"
  KEY_BASE64="${KEY_BASE64//[ #]/}"
}


function irlux_base64key_checksum () {
  local ALGO="${1:-sha256}"; shift
  local CUTOFF="${1:-8}"; shift
  local CKSUM="$(<<<"$KEY_BASE64" base64 -d | "${ALGO}"sum -b)"
  [ -n "$CUTOFF" ] && CKSUM="${CKSUM:0:$CUTOFF}"
  echo "D: key checksum ($ALGO): $CKSUM" >&2
}


function irlux_base64key_unlock () {
  [ "$DBGLV" -ge 2 ] && irlux_base64key_checksum
  <<<"$KEY_BASE64" base64 -d | irlux_unlock_by_keyfile - || return $?
}




irlux_cli_prep "$@"; exit $?
