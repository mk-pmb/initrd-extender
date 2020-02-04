
mkinitramfs gotchas
===================


Non-executable /tmp
-------------------

When generating your initrd, you might get this warning:

```text
update-initramfs: Generating /boot/initrd.img-…
W: TMPDIR is mounted noexec, will not cache run scripts.
```

When booting that initrd, you might see several lines like this:

```text
/init: eval: line 1: array_…=: not found
```

Finally your boot messages come to a rest, and when you hit enter,
you discover that you're in an initramfs rescue shell.
When you ask it, why:

```text
echo "$REASON"
PANIC: Circular dependancy. Exiting.
```

(Note the "a" in "dependancy". At that stage I had no disk drives available
in `/dev`, so I "copied" (typed) my search engine query
`initramfs panic "circular dependency"` manually, and now later I know
why my search engine didn't find anything helpful at first.)


[Solution in Debian bug tracker][debbug-689301-noexec]:

The host that runs your `update-initramfs` must have its `TMPDIR`
(usually, `/tmp`) on a filesystem that allows the executable flag
to be set on files while you run `update-initramfs`.

```bash
sudo mount /tmp -o remount,exec
```

[This patch][noexec-patch] might have fixed it.



  [debbug-689301-noexec]: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=689301#67
  [noexec-patch]: https://lists.debian.org/debian-kernel/2014/10/msg00277.html
