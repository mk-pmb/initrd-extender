#!/bin/sh
ESC="$(echo | tr '\n' '\033')"
echo
echo -n "${ESC}[${1:-0}m"
yes '  ██' | head --lines="${2:-10}" | tr -d '\n'
echo "${ESC}[0m"
echo
