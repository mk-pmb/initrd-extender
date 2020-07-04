#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
FILE="$1"; shift
SED_CMD="$1"; shift
case "$*" in
  '-i' | *' -i' )
    sed -re "$SED_CMD" "$@" -- "$FILE" || exit $?
    nl -ba -- "$FILE" || exit $?
    sync
    ;;
  * )
    sed -re "$SED_CMD" "$@" -- "$FILE" | nl -ba;;
esac
