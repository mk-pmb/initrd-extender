#!/bin/sh
# -*- coding: utf-8, tab-width: 2 -*-

irdex_read_one_line_with_timeout () {
  local TIMEOUT="$1"; shift
  exec <&10
  sed -e q <&10 &
  local SED_PID=$!
  irdex_timeout_by_pid "$SED_PID" "$TIMEOUT" HUP
  wait "$SED_PID"
  exec 10<&-
}


irdex_timeout_by_pid () {
  local SUBJ_PID="$1"; shift
  local TIMEOUT="$1"; shift
  local SIGNAL="$1"; shift
  while [ "$TIMEOUT" != "${TIMEOUT#0}" ]; do TIMEOUT="${TIMEOUT#0}"; done
  TIMEOUT="${TIMEOUT}0" # convert to tenths of a second
  [ -n "$SIGNAL" ] || SIGNAL=HUP
  local ELAPSED=0
  while [ "$TIMEOUT" -gt "$ELAPSED" ]; do
    # kill -0 "$SED_PID" 2>/dev/null || break
    sleep 0.1s
    ELAPSED=$(( $ELAPSED + 1 ))
  done
  kill -"$SIGNAL" "$SUBJ_PID" 2>/dev/null
}
