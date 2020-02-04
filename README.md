
<!--#echo json="package.json" key="name" underline="=" -->
initrd-extender
===============
<!--/#echo -->

<!--#echo json="package.json" key="description" -->
Dynamically add files and autorun scripts to your initramfs via kernel
parameters.
<!--/#echo -->


Purpose
-------

* To help me debug initrd failures more comfortably.



Security risks
--------------

* It will help anyone with local access debug your initrd, for whatever
  behavior the potential attacker considers a "bug". This might very well
  include stuff that you intended to be a security feature.
* Anyone who can configure the kernel parameters, or can guess which
  irdex devices you have enabled by default, might also have an easier
  time hacking you remotely.



How it works
------------

The core of initrd-extender is the `irdex` program.
Several times during initrd startup, it will:

1. __(unfold)__ Install itself more thoroughly.
1. __(dyndisks)__ Check a given a list of devices for additional instructions.



### (unfold)

1.  __(unfold:check_booting)__
    Check whether irdex is running inside an initramfs.
    If there's doubt about it, skip the remainder of (unfold).
    See config for how to skip these checks.
1.  __(unfold:retrigger)__
    Add itself to later initramfs script triggers.
    Done at initramfs time because `update-initramfs` didn't accept my
    symlinks, and I don't like having a separate hook script.
    * :bug: Figure out how to make this work. Neither symlinks nor actual
      copies of the file seem to re-trigger.



### (dyndisks)

The list of devices can be configured via `irdex_disks=`.
Each devices is checked for whether it's present and mounted.
If it's present but not (yet) mounted, `irdex` will

1.  try to mount it. If this fails, skip the device.
1.  check whether it has an `/irdex-fx` directory. If not, skip the device.
1.  __(fx:bin)__
    If there are any files inside directory `/irdex-fx/bin`,
    copy each of them to `/bin` and mark the destination files executable.
    (This way your source disk can use a file system that does not support
    the executable bit.)
    Some known script filename extensions (e.g. `.sh`, `.py`, `.pl`, `.sed`)
    are stripped from the destination filename.
1.  __(fx:bin-arch)__ Same as (fx:bin) but with directory
    `/irdex-fx/bin-###`, where `###` is the machine architecture reported
    by `uname -m`, e.g. `/irdex-fx/bin-i686` or `/irdex-fx/bin-x86_64`.
1.  __(fx:upd)__
    check whether it has an `/irdex-fx/upd` directory.
    If so, copy all of its contents to `/`.
    No guarantees are given whether hidden items (i.e. whose name starts with
    a dot) are copied.
    Existing destination files will be replaced.
    In case the destination is a symlink, there's no guarantee whether
    `irdex` will (try to) replace the symlink itself, or its target.
1.  __(fx:upd-arch)__ Same as (fx:upd), but using an architecture-specific
    directory name as in (fx:bin-arch), e.g. `/irdex-fx/upd-x86_64`.
1.  __(fx:add)__
    Like (fx:upd) but using the `/irdex-fx/add` directory,
    and existing destinations are skipped.
1.  __(fx:add-arch)__ Same as (fx:add), but using an architecture-specific
    directory name as in (fx:bin-arch), e.g. `/irdex-fx/add-x86_64`.
1.  __(fx:autorun)__
    check whether it has an `/irdex-fx/autorun.sh` file.
    If so, it is copied to `/bin/irdex-autorun-###`, where `###` is a name
    derived from the mountpoint name.
    The resulting file is then marked executable and is executed,
    with the environment variable `IRDEX_FXDIR` set to the path of the
    `irdex-fx` directory the autorun script originated from.


Other things that `irdex` will do:

* Create a symlink `/bin/irdex` to itself so you can easily re-run it
  from an initramfs shell.




Configuration
-------------

Configuration is done via environment variables.
To set them at initramfs time:

* The intended method is to provide them as kernel parameters.
* Using `export`ed variables in `/etc/initramfs-tools/conf.d/*` files
  should work, too.
  It seems that vars set in those configs will always win over kernel params,
  but don't rely on it until you find a trusted source that says so.



### irdex_disks=

Set this to a list of devices whose irdex instructions you want to activate.

* List items are separated by comma, space, or any combination thereof.
* Empty list items are ignored.
* Unsupported list items cause a warning to stderr as their only effect.
* Disk device items take the form `[<criterion>:][[<mntdir>]:]<name>`, where
  * `<criterion>` optionally specifies what namespace to look for `<name>` in:
    * `L` (default): file system label
    * `U`: GPT partition UUID, then file system UUID
    * `N`: GPT partition name
    * `I`: `/dev/disk/by-id/`
    * `P`: `/dev/disk/by-path/`
    * anything that starts with a slash (`/`):
      It's added verbatim in front of `<name>` to construct a device path.
      Decide for yourself if you want a slash at the end.
      If you set it to `/dev/exotic-`, a `<name>` of `fruit` will result in
      `/dev/exotic-fruit`.
  * `<mntdir>` is an optional custom name for the mountpoint.
    If omitted or empty, it will be derived from `<name>`.
    (You may want to specify this empty in case `<name>` contains a colon.)
    In case it does not contain slashes, `/mnt/` is inserted in front.
  * `<name>` is the identifier of the disk device within the namespace
    selected by `<criterion>`.


### irdex_inside_initramfs=

Set this to `yes_really` to skip the (unfold:check_booting) checks.





<!--#toc stop="scan" -->



Known issues
------------

* [Known problems with mkinitramfs](docs/mkinitramfs_gotchas.md)
* Needs more/better tests and docs.




&nbsp;


License
-------
<!--#echo json="package.json" key=".license" -->
ISC
<!--/#echo -->
