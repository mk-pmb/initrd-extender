#!/bin/sh
# -*- coding: utf-8, tab-width: 2 -*-
#
#   NB: In net-util-pmb, `serialport-repl.sh` already has `stty` config.
#   NB: In net-util-pmb, `serialport-socat.sh` has `--prepare-only`.
#
stty -F /dev/ttyUSB0 115200 sane -cstopb -echo raw litout -echo
