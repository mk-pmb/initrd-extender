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
  local SELF_IRD_SCRIPT="$(echo "$ORIG_ARG_ZERO" | sed -nre '
    s~^/scripts/([a-z]+(-[a-z]+|)/[a-z-]+\.sh)$~\1~p')"
  local SELF_IRD_PHASE="${SELF_IRD_SCRIPT#/scripts/}"

  [ -n "$irdex_tmpdir" ] || export irdex_tmpdir=/tmp/initrd-extender
  [ -n "$irdex_flagdir" ] || export irdex_flagdir="$irdex_tmpdir"/flags
  [ "$ACTION" = prereqs ] || irdex_set_flag "launch.action.$ACTION" || return $?

  local BOOT_PHASE="$irdex_boot_phase"
  irdex_unabbreviate_boot_phase || return $?
  [ -n "$BOOT_PHASE" ] || BOOT_PHASE="${SELF_IRD_PHASE%/*.sh}"
  [ -n "$BOOT_PHASE" ] || BOOT_PHASE='__unknown__'
  irdex_boot_phase="$BOOT_PHASE"
  export irdex_boot_phase

  local SCRIPT_PHASES="$(echo $(echo '
    # ./util/find_script_phases.sh
    # NB: if an nfs phase is used, its local twin will be skipped.
    init-top
    init-premount
    nfs-top
    local-top
    # after {local|nfs}-top, a root filesystem is expected to be mounted.
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
  # NB: There is a prereqs call at (or before?) the init-top phase,
  #     when there are no ORDER files yet. I guess the ORDER is
  #     figured out anew at each boot, by whatever prereqs are
  #     dynamically determined.
  # :TODO: Test if missing ORDER files were just another aspect of
  #     the tmp-noexec bug.

  irdex_hook_install_helpful_tools || return $?
}


irdex_set_flag () {
  mkdir -p -- "$irdex_flagdir"
  [ -z "$1" ] || date >"$irdex_flagdir/$1" || return $?
}


irdex_flag_once () {
  local TASK="$1"; shift
  local SED="s|=|${1#irdex_}|g"
  TASK="$(echo "$TASK" | sed -re "$SED")"
  if [ -f "$irdex_flagdir/done.$TASK" ]; then
    irdex_log D "skip task (already done): $*"
    return 0
  fi
  if [ -f "$irdex_flagdir/skip.$TASK" ]; then
    irdex_log D "skip task as requested: $*"
    return 0
  fi
  "$@" || return $?
  irdex_set_flag "done.$TASK" || return $?
}


irdex_hook_suggest_helpful_tools () {
  echo '
    agetty
    base64
    basename
    bash
    dirname
    grep
    head
    less
    lvm
    nl
    ps
    readlink
    rev
    sed
    setsid
    sha1sum
    sha256sum
    sha512sum
    socat
    sponge
    tac
    tail
    tar
    ts
    '
  local PROG="$(which fsck)"
  [ -x "$PROG" ] && ls -- "$PROG" "$PROG".*
}


irdex_hook_install_helpful_tools () {
  # According to `man 8 initramfs-tools`, this should be in a hook,
  # not a script. However, I prefer to install irdex by copying
  # just one file.
  local HOOKFUNCS_LIB='/usr/share/initramfs-tools/hook-functions'
  [ -f "$HOOKFUNCS_LIB" ] || return 0
  case "$DESTDIR" in
    /tmp/mkinitramfs_* ) ;;
    /var/tmp/mkinitramfs_* ) ;;
    * )
      echo "E: irdex_hook_install_helpful_tools: flinching:" \
        "unusual target directory DESTDIR='$DESTDIR'" >&2
      return 3;;
  esac
  . "$HOOKFUNCS_LIB" || return 0

  local TOOLS="$(irdex_hook_suggest_helpful_tools)"
  local ITEM=
  for ITEM in $TOOLS; do
    ITEM="$(which "$ITEM" 2>/dev/null | grep '^/')"
    [ -n "$ITEM" ] || continue
    copy_exec "$ITEM" || return $?
  done
}


irdex_unabbreviate_boot_phase () {
  local A="${ACTION%-*}"
  local B="${ACTION#*-}"
  [ "$ACTION" = "$A-$B" ] || return 0
  case "$A" in
    i ) A='init';;
    l ) A='local';;
    n ) A='nfs';;
    * ) return 0;;
  esac
  case "$B" in
    t ) B='top';;
    p ) B='premount';;
    b ) B='block';;
    B ) B='bottom';;
    * ) return 0;;
  esac
  BOOT_PHASE="$A-$B"
  ACTION='boot'
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
  local WHY_NOT_IRFS="$(irdex_unfold_why_not_inside_initramfs)"
  ( echo "invoked as '$ORIG_ARG_ZERO', action '$ACTION'" \
      "in phase '$BOOT_PHASE'"
    echo "our local PS1 (might differ from env): '$PS1'"
    echo "why not initramfs: '$WHY_NOT_IRFS'"
    irdex_chapter_cmd 'env | sort'
    # ^-- sort: beware the restricted options, e.g. no -V
    irdex_chapter_cmd mount
  ) >"/tmp/irdex_boot_circumstances.debug.$(date +%y%m%d-%H%M%S).$$.txt" 2>&1

  echo "$(date +%T) phase $BOOT_PHASE" \
    "action $ACTION" \
    "initrd? $WHY_NOT_IRFS" \
    "arg0: $ORIG_ARG_ZERO" \
    "pid: $$" \
    >>/tmp/irdex_boot_phases.log

  if [ -n "$WHY_NOT_IRFS" ]; then
    irdex_log D "Will not unfold: We're probably not inside an initramfs:" \
      "$WHY_NOT_IRFS"
    tty -s && irdex_log H "To skip this check, try actions 'unfold' or 'scan'."
    return 0
  fi
  irdex_log D "Looks like we're running inside an initramfs's" \
    "$BOOT_PHASE phase. Unfold!"
  irdex_unfold || return $?

  local IMP='/tmp/env_import_cmdline.rc'
  if [ -z "$irdex_disks" ]; then
    irdex_log W "Empty irdex_disks! Will try to parse kernel commandline:" >&2
    </proc/cmdline irdex_env_parse_kopt >"$IMP" || return $?
    # ls -l -- "$IMP"
    # sed -re 's~^~\t» ~' -- "$IMP"
    irdex_log D "Import $IMP…"
    . "$IMP" || return $?
    [ -n "$irdex_disks" ] || irdex_log W \
      "Still no irdex_disks even after importing $IMP." >&2
  fi

  irdex_check_fix_hostname || return $?
  irdex_scan || return $?

  [ "$irdex_boot_phase" != init-bottom ] \
    || irdex_flag_once finally_= irdex_umount_all_mnt || return $?
}


irdex_check_fix_hostname () {
  [ -n "$irdex_host" ] && return 0
  [ -f /etc/hostname ] && return 0
  [ "$(hostname)" = '(none)' ] && return 0
  echo "$irdex_host" >/etc/hostname
  hostname "$irdex_host"
}


irdex_chapter_cmd () {
  echo
  echo "=== $* ==="
  eval "$*"
}


irdex_unfold () {
  [ -f "$irdex_flagdir/done.unfold" ] && return 0
  irdex_symlink_self_to /bin/irdex
  irdex_bin_alias_busybox_funcs || return $?
  irdex_schedule_later_triggers || return $?
  irdex_set_flag done.unfold || return $?
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
  local ROOTFS_MNT="$(mount | sed -nre '
    s~^(\S+) on / type rootfs .*$~\1~p')"
  [ -n "$ROOTFS_MNT" ] || WHY_NOT="$WHY_NOT,rootfs"
  [ "$rootmnt" = '/root' ] || WHY_NOT="$WHY_NOT,rootmnt"
  [ "$ORIG_ARG_ZERO" = /bin/irdex ] \
    || [ -n "$SELF_IRD_SCRIPT" ] \
    || WHY_NOT="$WHY_NOT,selfpath"
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
  [ -e "$DEST" ] && return 0
  [ -L "$DEST" ] && rm -- "$DEST"
  ln -s -- "$SELFFILE" "$DEST" || return $?$(
    irdex_log W "failed to create symlink '$DEST' to '$SELFFILE'")
}


irdex_schedule_later_triggers () {
  if irdex_check_any_order_exists; then
    irdex_ensure_order_triggers; return $?
  fi

  echo "W: Falling back to trying to install triggers without ORDER files." \
    "This is probably futile." >&2
  irdex_setup_late_triggers || return $?
}


irdex_check_any_order_exists () {
  local FN=
  for FN in /scripts/*/ORDER; do
    [ -f "$FN" ] && return 0
  done
  return 1
}


irdex_ensure_order_triggers () {
  local ADD_TRIG= ORDER_FILE=
  for ADD_TRIG in $SCRIPT_PHASES; do
    ORDER_FILE="/scripts/$ADD_TRIG/ORDER"
    [ -f "$ORDER_FILE" ] || continue
    sed -re '
      s~\|.*$~~
      s~\s+$~~
      s~^[A-Z_]+=[A-Za-z0-9-]+\s+~~
      ' -- "$ORDER_FILE" | grep -qxFe "$SELFFILE" && continue
    sed -re "1i irdex_boot_phase=$ADD_TRIG $SELFFILE" \
      -i -- "$ORDER_FILE" || return $?
  done
}


irdex_setup_late_triggers () {
  local ADD_TRIG=
  local SELF_BN="$(basename -- "$SELF_IRD_SCRIPT")"
  for ADD_TRIG in $SCRIPT_PHASES; do
    ADD_TRIG="/scripts/$ADD_TRIG"
    [ -d "$ADD_TRIG" ] || continue
    irdex_symlink_self_to "$ADD_TRIG"/ || return $?
  done
}


irdex_env_parse_kopt () {
  tr ' ' '\n' | sed -nre '
    s~'"'"'~&\\&&~g
    s~^([A-Za-z0-9_-]+)=(.*$|$\
      )~if [ -z "$\1" ]; then \1='"'"'\2'"'"'; export \1; fi~p
    '
}


irdex_scan () {
  irdex_parse_disk_specs "$irdex_disks $*" mount_extend || return $?
  irdex_run_all_autorun_scripts || return $?
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
  [ -n "$SPEC" ] || return 0
  local DISK_NS='L' MNTP= NICK=
  case "$SPEC" in
    ESP: )
      if [ -z "$irdex_esp_label" ]; then
        irdex_esp_label="$(echo "$irdex_host" | tr a-z A-Z)_ESP"
        export irdex_esp_label
      fi
      SPEC="L:$irdex_esp_label";;
  esac
  case "$SPEC" in
    upper:* )
      # Help me configure hostname-based FAT labels in GRUB,
      # saving the extra `tr --set=UC_HOST --upcase "$hostname"`.
      SPEC="${SPEC#*:}"
      SPEC="$(echo "$SPEC" | tr a-z A-Z)"   # busybox sh cannot ${^^}
      ;;
  esac
  case "$SPEC" in
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

  if [ -f "$irdex_flagdir/diskext.$NICK" ]; then
    irdex_log D "disk has been extended earlier already: $DISK_DEV ($NICK)"
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
  local PLATFORM_SUFFIXES="
    /
    -all/
    -$ARCH/
    "
  irdex_install_progs || return $?

  irdex_install_extras '' upd || return $?
  irdex_install_extras -n add || return $?
  irdex_install_autorun_script || return $?
  irdex_set_flag "diskext.$NICK" || return $?
}


irdex_install_progs () {
  [ -n "$FXDIR" ] || return 4$(irdex_log E "no fxdir given")
  # Maybe copy some programs that our autorun script might need.
  # Examples missing from busybox: bash socat tar
  # Examples crippled in busybox: cp grep readlink sed
  local ITEM= DEST=
  for ITEM in $PLATFORM_SUFFIXES; do
    for ITEM in "$FXDIR"/bin"$ITEM"*; do
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
  for ITEM in $PLATFORM_SUFFIXES; do
    for ITEM in "$FXDIR/$SUBDIR$ITEM"*; do
      irdex_copy_helper "$ITEM" / || return $?
    done
  done
}


irdex_bin_alias_busybox_funcs () {
  # Ensure that shells other than busybox can find basic commands like
  # "dirname" and "tee" as well.
  local BB_FUNCS='
    : skip
      n
      /Currently defined functions:/b funcs_list
    b skip
    : funcs_list
      n
      /^\s+/!b skip
      s~\s|,~\n~g
      p
    b funcs_list
    '
  BB_FUNCS="$(busybox 2>&1 | sed -nre "$BB_FUNCS" | sed -nre '/^[a-z]\S+$/p')"
  local ITEM=
  for ITEM in $BB_FUNCS; do
    which "$ITEM" >/dev/null && continue
    ITEM="/usr/bin/$ITEM"
    # Would be easier to just use /bin but I'd like to not clutter that one,
    # so it will be easier for me to see which of my own programs have been
    # copied from irdex-fx/bin-*.
    [ -e "$ITEM" ] && continue
    ln -sn /bin/busybox "$ITEM" || return $?
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


irdex_install_autorun_script () {
  local ORIG="$FXDIR/autorun.sh"
  if [ ! -f "$ORIG" ]; then
    irdex_log D "autorun script not found: $ORIG"
    return 0
  fi
  local DEST="/bin/irdex-autorun-$NICK"
  irdex_log D "Install autorun script $ORIG as $DEST…"
  cp -- "$ORIG" "$DEST" # busybox needs cripppled options
  chmod a+x -- "$DEST" # busybox needs cripppled options
  (
    echo irdex_dev="$DISK_DEV"
    echo irdex_partlabel="$NICK"
    echo irdex_fxdir="$FXDIR"
  ) >"$DEST".ctx
}


irdex_run_all_autorun_scripts () {
  local BASE='/bin/irdex-autorun-' ITEM= FLAG=
  for ITEM in "$BASE"*; do
    [ -x "$ITEM" ] || continue
    FLAG="$irdex_flagdir/autorun.${ITEM#$BASE}"
    if [ -f "$FLAG" ]; then
      irdex_log D "Skip autorun script $ITEM: marked as done."
      return 0
    fi
    irdex_log D "Run autorun script $ITEM…"
    irdex_autorun_done_flag="$FLAG" "$ITEM" || return $?
    # scripts shall do themselves if they like: # date >"$FLAG" || return $?
  done
}


irdex_retryable () {
  local MAX_FAILS="$1"; shift
  local FAIL_DELAY="$1"; shift
  "$@" && return 0
  local RV=$? FAIL_CNT=1
  while [ "$MAX_FAILS" -gt "$FAIL_CNT" ]; do
    irdex_log W "retryable: fail #$FAIL_CNT (rv=$RV) of $MAX_FAILS max.," \
      "will retry in $FAIL_DELAY: $*"
    sleep "$FAIL_DELAY"
    "$@"
    RV=$?
    [ "$RV" = 0 ] && return 0
    FAIL_CNT=$(( $FAIL_CNT + 1 ))
  done
  irdex_log W "retryable: final fail (rv=$RV) of $MAX_FAILS max.: $*"
  return "$RV"
}


irdex_boot_luks_lvm_by_keyfile () {
  irdex_unlock_luks_lvm_by_keyfile "$@" || return $?
  irdex_retryable 5 1s test -b "$ROOT" || return $?
  irdex_actually_mount "$ROOT" "$rootmnt" || return $?
  irdex_umount_all_mnt || return $?
}


irdex_unlock_luks_lvm_by_keyfile () {
  local KEY_FILE="$1"; shift
  case "$KEY_FILE" in
    /dev/fd/[3-9]* | /dev/fd/[1-9][0-9]* )
      irdex_log E "It's not reliable to pass $KEY_FILE as key file:" \
        'lvm might consider extra file descriptors as accidentially leaked,' \
        'and thus might flinch. Instead, use stdin ("-").';;
  esac
  cryptsetup open --type=luks --key-file "$KEY_FILE" "$@" \
    -- "$irdex_lvm_disk" "$irdex_lvm_pv" || return $?
  irdex_retryable 5 1s test -b /dev/mapper/"$irdex_lvm_pv" || return $?
  lvm vgchange --activate y "$irdex_lvm_vg" || return $?
}


irdex_umount_all_mnt () {
  # At the time initrd switches the /root, no other disks should be mounted,
  # or you'll get a kernel panic about "trying to kill init", probably
  # because the old init can't let go of its mounts and thus doesn't
  # quit in time..
  local MNT=
  for MNT in $(mount | sed -nre 's~^\S+ on (/mnt/\S+) type .*$~\1~p'); do
    umount -l "$MNT"
  done
  sleep 1s
  for MNT in $(mount | sed -nre 's~^\S+ on (/mnt/\S+) type .*$~\1~p'); do
    umount "$MNT" || return $?
  done
}













[ "$1" = --lib ] && return 0; irdex_main "$@"; exit $?
