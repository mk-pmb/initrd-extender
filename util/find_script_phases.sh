#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function find_script_phases () {
  echo '# NB: if an nfs stage is used, its local twin will be skipped.'
  </dev/null COLUMNS=9002 man \
    --locale=C \
    --no-hyphenation \
    --no-justification \
    initramfs-tools | grep -xPe '\s+Subdirectories' -m 1 -A 9002 | sed -nre '
    1n
    2n
    /^ {0,4}\S/q
    s~^ {8,}([a-z]+-[a-z]+) (OR ([a-z]+-[a-z]+) |).*$~\3\n\1~p
    ' | grep .
}



find_script_phases "$@"; exit $?
