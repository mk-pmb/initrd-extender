#!/bin/sh
# -*- coding: utf-8, tab-width: 2 -*-


irdex_main () {
  local ACTION="$1"
  [ -n "$ACTION" ] || ACTION='boot'
  [ "$#" = 0 ] || shift

  export LANG=en_US.UTF-8  # make error messages search engine-friendly
  export LANGUAGE="$LANG"
  local ORIG_ARG_ZERO="$0"
  local SELFFILE="$(readlink -f -- "$0")"
  local SELF_IRD_SCRIPT="$(echo "$0" | sed -nre '
    s~^/scripts/([a-z]+(-[a-z]+|)/[a-z-]+\.sh)$~\1~p')"
  local SELF_IRD_PHASE="${SELF_IRD_SCRIPT#/scripts/}"

  local BOOT_PHASE="$IRDEX_BOOT_PHASE"
  [ -n "$BOOT_PHASE" ] || BOOT_PHASE="$SELF_IRD_PHASE"
  [ -n "$BOOT_PHASE" ] || BOOT_PHASE='__unknown__'

  local SCRIPT_PHASES="$(echo $(echo '
    # ./util/find_script_phases.sh
    # NB: if an nfs stage is used, its local twin will be skipped.
    init-top
    init-premount
    nfs-top
    local-top
    local-block
    nfs-premount
    local-premount
    nfs-bottom
    local-bottom
    init-bottom
    ' | sed -nre 's~^\s+~~;/^[a-z-]+$/p'))"

  irdex_"$ACTION" "$@"; return $?
}


irdex_prereqs () {
  echo ''
}


irdex_log () {
  local LVL="$1"; shift
  MSG="$(date +'%F %T') irdex[$$]: $LVL: $*"
  case "$LVL" in
    W | E ) echo "$MSG" >&2;;
    * ) echo "$MSG";;
  esac
}


irdex_boot () {
  irdex_unfold
  irdex_scan || return $?
}


irdex_chapter_cmd () {
  echo
  echo "=== $* ==="
  eval "$*"
}


irdex_unfold () {
  irdex_symlink_self_to /bin/irdex

  local WHY_NOT_IRFS="$(irdex_unfold_why_not_inside_initramfs)"
  ( echo "invoked as '$ORIG_ARG_ZERO'" \
      "in phase '$BOOT_PHASE' ('$IRDEX_BOOT_PHASE')"
    echo "our local PS1 (might differ from env): '$PS1'"
    echo "why not initramfs: '$WHY_NOT_IRFS'"
    irdex_chapter_cmd 'env | sort'
    # ^-- sort: beware the restricted options, e.g. no -V
    irdex_chapter_cmd mount
  ) >"/tmp/irdex_unfold.debug.$(date +%y%m%d-%H%M%S).$$.txt" 2>&1

  if [ -n "$WHY_NOT_IRFS" ]; then
    irdex_log D "Will not unfold: We're probably not inside an initramfs:" \
      "$WHY_NOT_IRFS"
    return 0
  fi
  irdex_log D "Looks like we're running inside an initramfs. Unfold!"

  irdex_ensure_order_triggers || return $?
}


irdex_unfold_why_not_inside_initramfs () {
  [ "$irdex_inside_initramfs" = 'yes_really' ] && return 0
  local WHY_NOT=
  case "$PS1" in
    '# ' | \
    '' ) ;; # probably script-triggered
    '(initramfs) '* ) ;; # probably running inside rescue shell
    * ) WHY_NOT="$WHY_NOT,ps1";;
  esac
  mount | cut -d ' ' -sf 1-5 | grep -qxFe 'rootfs on / type rootfs' \
    || WHY_NOT="$WHY_NOT,rootfs"
  [ "$rootmnt" = '/root' ] || WHY_NOT="$WHY_NOT,rootmnt"
  [ -n "$SELF_IRD_SCRIPT" ] || WHY_NOT="$WHY_NOT,selfpath"
  WHY_NOT="${WHY_NOT#,}"
  [ -n "$WHY_NOT" ] || return 0
  echo "$WHY_NOT"
  return 2
}


irdex_symlink_self_to () {
  local DEST="$1"
  case "$DEST" in
    */ ) DEST="$DEST/$(basename -- "$SELFFILE")";;
  esac
  [ -f "$DEST" ] && return 0
  ln -s -- "$SELFFILE" "$DEST" || return $?$(
    irdex_log W "failed to create symlink '$DEST' to '$SELFFILE'")
}


irdex_ensure_order_triggers () {
  local ADD_TRIG= ORDER_FILE=
  for ADD_TRIG in $SCRIPT_PHASES; do
    [ "$ADD_TRIG" == "$SELF_IRD_PHASE" ] && continue
    ORDER_FILE="/scripts/$ADD_TRIG/ORDER"
    grep -qFe "${SELF_IRD_SCRIPT} " -- "$ORDER_FILE" && continue
    sed -re "1i IRDEX_BOOT_PHASE=$ADD_TRIG $SELF_IRD_SCRIPT"' "$@"' \
      -i -- "$ORDER_FILE" || return $?
  done
}


irdex_scan () {
  irdex_parse_disk_specs "$irdex_disks $*" mount_extend || return $?
}


irdex_parse_disk_specs () {
  local TODO="$1"; shift
  # ensure empty last item, so we can always split unconditionally:
  TODO="$TODO,"
  TODO="$(echo "$TODO" | tr -s ', ' ,)"
  local SPEC=
  while [ -n "$TODO" ]; do
    SPEC="${TODO%%,*}"
    TODO="${TODO#*,}"
    irdex_parse_one_disk_spec "$SPEC" "$@" || return $?
  done
}



irdex_unary_first () {
  local OPER="$1"; shift
  local ITEM=
  for ITEM in "$@"; do
    [ $OPER "$ITEM" ] || continue
    echo "$ITEM"
    return 0
  done
  return 2
}


irdex_unary_fallback () {
  local OPER="$1"; shift
  local ITEM=
  for ITEM in "$@"; do
    [ $OPER "$ITEM" ] && break
  done
  echo "$ITEM"
}


lcbn () { basename -- "$1" | tr A-Z a-z; }


irdex_parse_one_disk_spec () {
  local SPEC="$1"; shift
  local ACTION="$1"; shift
  local DISK_NS='L' MNTP= NICK=
  case "$SPEC" in
    '' ) return 0;;
    [LUNIP]:* | /*:* ) DISK_NS="${SPEC%%:*}"; SPEC="${SPEC#*:}";;
  esac
  case "$SPEC" in
    *:* )
      MNTP="${SPEC%%:*}"
      SPEC="${SPEC#*:}"
      [ -n "$MNTP" ] || MNTP="$SPEC"
      ;;
    * ) MNTP="$(lcbn "$SPEC")"; NICK="$MNTP";;
  esac
  [ -n "$SPEC" ] || return 0
  [ -n "$NICK" ] || NICK="$(lcbn "$MNTP")"
  case "$MNTP" in
    /* ) ;;
    * ) MNTP="/mnt/$MNTP";;
  esac

  local BY='/dev/disk/by' DISK_DEV=
  case "$DISK_NS" in
    I ) DISK_DEV="$BY-id/$SPEC";;
    L ) DISK_DEV="$BY-label/$SPEC";;
    N ) DISK_DEV="$BY-partlabel/$SPEC";;
    P ) DISK_DEV="$BY-path/$SPEC";;
    U ) DISK_DEV="$(irdex_unary_fallback -e \
      "$BY"-partuuid/"$SPEC" \
      "$BY"-uuid/"$SPEC" \
      )";;
    /* ) DISK_DEV="$DISK_NS$SPEC";;
    * )
      irdex_log W "unsupported disk namespace: '$DISK_NS'"
      return 0;;
  esac

  case "$ACTION" in
    debug )
      irdex_log D "DISK_DEV='$DISK_DEV' NICK='$NICK' MNTP='$MNTP'"
      return 0;;
    * ) ACTION="irdex_${ACTION}_disk"
  esac
  "$ACTION" "$@" || return $?
}


irdex_ismnt () {
  local DISK="$1"; shift
  local MNTP="$1"; shift
  MNTP="${MNTP%/}"
  if [ -n "$DISK" ]; then
    # check strictly
    mount | cut -d ' ' -f 1-4 | grep -qxFe "$DISK on $MNTP type"; return $?
  fi
  mount | cut -d ' ' -f 2-4 | grep -qxFe "on $MNTP type"; return $?
}


irdex_actually_mount () {
  local DISK="$1"; shift
  local MNTP="$1"; shift
  local OPTS='defaults,noatime'
  # OPTS="$OPTS,uid=root,gid=root" # not supported by busybox for ext2
  mount "$DISK" "$MNTP" -o "$OPTS" || return $?
}


irdex_mount_extend_disk () {
  if [ ! -b "$DISK_DEV" ]; then
    if irdex_ismnt "$DISK_DEV" "$MNTP"; then
      irdex_log W "umount $MNTP because $DISK_DEV ($NICK)" \
        "is no longer a block device."
      umount "$MNTP" || return $?
      return 0
    fi
    irdex_log D "not (yet/again) a block device: $DISK_DEV ($NICK)"
    return 0
  fi
  mkdir -p -- "$MNTP" || return $?$(
    irdex_log E "failed to create mountpoint $MNPT for $DISK_DEV")
  local FXDIR="$MNTP/irdex-fx"
  if irdex_ismnt '' "$MNTP"; then
    irdex_log D "Something is already mounted in $MNTP."
    return 0
  else
    irdex_log D "Gonna fsck $DISK_DEV and mount it in $MNTP."
    fsck -a "$DISK_DEV" # avoid mount flinching
    [ -d "$FXDIR"  ] || irdex_actually_mount "$DISK_DEV" "$MNTP" || return $?
  fi
  if [ ! -d "$FXDIR"  ] ; then
    irdex_log D "No fxdir in $MNTP."
    return 0
  fi
  cd -- "$FXDIR" || return $?$(
    irdex_log E "Failed to chdir into fxdir: $FXDIR")

  local ARCH="$(uname -m)" # -p = CPU type was unknown in dvalin @2019-09-21
  irdex_install_progs || return $?
  irdex_install_extras '' upd || return $?
  irdex_install_extras -n add || return $?
  irdex_autorun || return $?
}


irdex_install_progs () {
  [ -n "$FXDIR" ] || return 4$(irdex_log E "no fxdir given")
  # Maybe copy some programs that our autorun script might need.
  # Examples missing from busybox: bash socat tar
  # Examples crippled in busybox: cp grep readlink sed
  local ITEM= DEST=
  for ITEM in "$FXDIR/bin"/* "$FXDIR/bin-$ARCH"/*; do
    [ -f "$ITEM" ] || continue
    DEST="${ITEM##*/}"
    DEST="${DEST%.pl}"
    DEST="${DEST%.py}"
    DEST="${DEST%.sed}"
    DEST="${DEST%.sh}"
    DEST="/bin/$DEST"
    [ -L "$DEST" ] && rm -- "$DEST"
    cp -- "$ITEM" "$DEST" # busybox needs cripppled options
    chmod a+x -- "$DEST" # busybox needs cripppled options
  done
}


irdex_install_extras () {
  local CP_OPT="$1"; shift
  local SUBDIR="$1"; shift
  [ -n "$FXDIR" ] || return 4$(irdex_log E "no fxdir given")
  [ -n "$SUBDIR" ] || return 4$(irdex_log E "no subdir given")
  # Copy other stuff.
  # To find which shared libraries are required for programs, try:
  # find-elf-shared-libs bash sed socat tar # uses ldd under the hood
  # Options must be crippled for busybox's cp:
  local ITEM=
  for ITEM in "$FXDIR/$SUBDIR"/* "$FXDIR/$SUBDIR-$ARCH"/*; do
    irdex_copy_helper "$ITEM" / || return $?
  done
}


irdex_copy_helper () {
  local ORIG="$1" DEST="$2"
  ORIG="${ORIG%/}"
  [ -e "$ORIG" ] || [ -L "$ORIG" ] || return 0
  case "$CP_OPT" in
    -n ) CP_OPT= irdex_copy_noreplace "$ORIG" "$DEST"; return $?;;
    '' ) ;;
    * )
      echo "E: unsupported CP_OPT for irdex_copy_helper: '$CP_OPT'" >&2
      return 8;;
  esac
  # busybox cp needs very limited short options
  cp -rpdf -- "$ORIG" "$DEST" || return $?
}


irdex_copy_noreplace () {
  # because busybox's cp doesn't support -n
  local ORIG="$1" DEST_DIR="$2"
  ORIG="${ORIG%/}"
  local BN="$(basename -- "$ORIG")"
  local DEST="${DEST_DIR%/}/$BN"
  if [ -L "$DEST" ]; then
    return 0
  elif [ -d "$DEST" ]; then
    [ -L "$ORIG" ] && return 0 # don't replace dir with symlink
    [ -d "$ORIG" ] || return 0 # don't replace dir with non-dir
  elif [ -e "$DEST" ]; then
    return 0 # don't replace existing non-dir target
  fi
  if [ -L "$ORIG" ]; then
    CP_OPT= irdex_copy_helper "$ORIG" "$DEST" || return $?
  elif [ -d "$ORIG" ]; then
    mkdir -p -- "$DEST"
    for ORIG in "$ORIG"/.* "$ORIG"/*; do
      case "$ORIG" in
        */. | */.. ) continue;;
      esac
      irdex_copy_noreplace "$ORIG" "$DEST" || return $?
    done
  else
    CP_OPT= irdex_copy_helper "$ORIG" "$DEST" || return $?
  fi
}


irdex_autorun () {
  local ORIG="$FXDIR/autorun.sh"
  if [ ! -f "$ORIG" ]; then
    irdex_log D "autorun script not found: $ORIG"
    return 0
  fi
  local DEST="/bin/irdex-autorun-$NICK"
  cp -- "$ORIG" "$DEST" # busybox needs cripppled options
  chmod a+x -- "$DEST" # busybox needs cripppled options
  irdex_log D "autorun $ORIG as $DEST:"
  IRDEX_DEV="$DISK_DEV" IRDEX_NAME="$NICK" IRDEX_FXDIR="$FXDIR" "$DEST"
}








[ "$1" = --lib ] && return 0; irdex_main "$@"; exit $?
