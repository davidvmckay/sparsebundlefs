sparsebundlefs
================

FUSE filesystem for reading macOS sparse-bundle disk images.

[![Continuous Integration][ci-badge]][ci-link]
![CodeQL][codeql-badge]
[![CodeFactor][codefactor-badge]][codefactor-link]
[![LGTM][lgtm-badge]][lgtm-link]
[![License][license-badge]][bsd]

Mac OS X 10.5 (Leopard) introduced the concept of sparse-bundle disk images, where the data is
stored as a collection of small, fixed-size *band*-files instead of as a single monolithic file. This
allows for more efficient backups of the disk image, as only the changed bands need to be
stored.

One common source of sparse-bundles is macOS' backup utility, *Time Machine*, which stores
the backup data within a sparse-bundle image on the chosen backup volume.

This software package implements a FUSE virtual filesystem for read-only access to the sparse-bundle, as if it was a single monolithic image.

Installation
------------

Clone the project from GitHub:

    git clone git://github.com/torarnv/sparsebundlefs.git

Or download the latest tar-ball:

    curl -L https://github.com/torarnv/sparsebundlefs/tarball/master | tar xvz

Install dependencies:

  - [macFUSE][macfuse] on *macOS*, e.g. via `brew install pkgconf macfuse`
  - `sudo apt-get install pkg-config libfuse-dev fuse` on Debian-based *GNU/Linux* distros
  - Or install the latest FUSE manually from [source][fuse]

Compile:

    make

**Note:** If your FUSE installation is in a non-default location you may have to
export `PKG_CONFIG_PATH` before compiling.

Install:

    sudo make install

The default install prefix is `/usr/local`. To choose another prefix pass
`prefix=/foo/bar` when installing. The `DESTDIR` variable for packaging is
also supported.

Usage
-----

To mount a `.sparsebundle` disk image, execute the following command:

    sparsebundlefs [-o options] sparsebundle mountpoint

For example:

    sparsebundlefs ~/MyDiskImage.sparsebundle /tmp/my-disk-image

This will give you a directory at the mount point with a single `sparsebundle.dmg` file.

You may then proceed to mount the `.dmg` file using regular means, e.g. for HFS:

    mount -o loop -t hfsplus /tmp/my-disk-image/sparsebundle.dmg /mnt/my-disk

Or, for Apple File System (APFS) partitions, using [apfs-fuse][apfs-fuse]:

    apfs-fuse /tmp/my-disk-image/sparsebundle.dmg /mnt/my-disk

This will give you read-only access to the content of the sparse-bundle disk image.

### Access, ownership, and permissions

By default, FUSE will restrict access to the mount point to the user that mounted the file system.
Nobody, not even root, can access another user's FUSE mount. To override this behavior, enable
the `allow_other` option by passing `-o allow_other` on the command line. This will give all
users on the system access to the resulting `.dmg` file. The `allow_root` option has the same
effect, but only extends access to the root user.

The ownership of the mount point and the `.dmg` file will always reflect the user who mounted
the sparsebundle, with the group set to `nogroup` to indicate that the group has no effect on
whether a mount is accessible or not:

    -r--------  1 torarne  nogroup  1099511627776 Sep  7 20:19 /tmp/my-disk-image/sparsebundle.dmg

The file permissions reflect the state of who can access the mount, with the `allow_other` and
`allow_root` options adding the `o+r` permission to indicate that the mount is accessible for
users beyond the owning user:

    -r-----r--  1 torarne  nogroup  1099511627776 Sep  7 20:19 /tmp/my-disk-image/sparsebundle.dmg

**Note:** Unless the `default_permissions` option is also enabled, the owner and mount point
permissions are only informative, and the access control happens in FUSE based on the presence
of `allow_other` and `allow_root`, as described in the first paragraph of this section.

### Mounting partitions at an offset

Some sparse-bundles may contain partition maps that `mount.hfsplus` will fail to process, for example the *GUID Partition Table* typically created for Time Machine backup volumes. This will manifest as errors such as "`wrong fs type, bad option, bad superblock on /dev/loop1`" when trying to mount the image.

The reason for this error is that the HFS+ partition lives at an offset inside the sparse-bundle, so to successfully mount the partition we need to pass this offset to the mount command. This is normally done through the `-o offset` option to mount, but in the case of HFS+ we need to also pass the partition size, otherwise the full size of the `dmg` image is used, giving errors such as "`hfs: invalid secondary volume header`" on mount.

To successfully mount the partition, first figure out the offset and size using a tool such as `parted`:

    parted /mnt/bundle/sparsebundle.dmg unit B print

This will print the partition map with all units in bytes:

```
Model:  (file)
Disk /mnt/bundle/sparsebundle.dmg: 1073741824000B
Sector size (logical/physical): 512B/512B
Partition Table: gpt
Disk Flags:

Number  Start       End             Size            File system  Name                  Flags
 1      20480B      209735679B      209715200B      fat32        EFI System Partition  boot
 2      209735680B  1073607585791B  1073397850112B  hfsx         disk image
```

Next, use the *start* and *size* columns from the above output to create a new loopback device:

    losetup -f /mnt/bundle/sparsebundle.dmg --offset 209735680 --sizelimit 1073397850112 --show

This will print the name of the loopback device you just created.

**Note:** Passing `-o sizelimit` directly to the `mount` command instead of creating the loopback device manually does not seem to work, possibly because the `sizelimit` option is not propagated to `losetup`.

Finally, mount the loopback device (which now starts at the right offset and has the right size), using regular mount:

    mount -t hfsplus /dev/loop1 /mnt/my-disk


### Reading Time Machine backups

Time Machine builds on a feature of the HFS+ filesystem called *directory hard-links*. This allows multiple snapshots of the backup set to reference the same data, without having to maintain hard-links for every file in the backup set.

Unfortunately this feature is not yet part of `mount.hfsplus`, so when navigating the mounted Time Machine image these directory hard-links will show up as empty files instead of directories. The real data still lives inside a directory named `.HFS+ Private Directory Data\r` at the root of the volume, but making the connection from a a zero-sized file to its corresponding directory inside the secret data location is a bit cumbersome.

Luckily there's another FUSE filesystem available, [tmfs][tmfs], which will allow you to re-mount an existing HFS+ volume and then navigate it as if the directory hard-links were regular directories. The syntax is similar to sparsebundlefs:

    tmfs /mnt/tm-hfs-image /mnt/tm-root

### Troubleshooting

If any of the above operations fail, you may try running `sparsebundlefs` in debug mode, where it will dump lots of debug output to the console:

    sparsebundlefs ~/MyDiskImage.sparsebundle /tmp/my-disk-image -s -f -D

The `-s` and `-f` options ensure that `sparsebundlefs` runs single-threaded and in the foreground, and the `-D` option turns on the debug logging. You should not see any errors in the log output, and if you suspect that the disk image is corrupted you may compare the read operations against a known good disk image.


License
-------

This software is licensed under the [BSD two-clause "simplified" license][bsd].



[ci-badge]: https://github.com/torarnv/sparsebundlefs/actions/workflows/ci.yml/badge.svg
[ci-link]: https://github.com/torarnv/sparsebundlefs/actions/workflows/ci.yml

[codefactor-badge]: https://www.codefactor.io/repository/github/torarnv/sparsebundlefs/badge
[codefactor-link]: https://www.codefactor.io/repository/github/torarnv/sparsebundlefs

[lgtm-badge]: https://img.shields.io/lgtm/grade/cpp/github/torarnv/sparsebundlefs?label=LGTM
[lgtm-link]: https://lgtm.com/projects/g/torarnv/sparsebundlefs/

[codeql-badge]: https://github.com/torarnv/sparsebundlefs/workflows/CodeQL/badge.svg

[license-badge]: https://img.shields.io/github/license/torarnv/sparsebundlefs?color=informational&label=License

[macfuse]: https://osxfuse.github.io/ "Fuse for macOS"
[fuse]: https://github.com/libfuse/libfuse "FUSE"
[bsd]: http://opensource.org/licenses/BSD-2-Clause "BSD two-clause license"
[tmfs]: https://github.com/abique/tmfs "Time Machine File System"
[apfs-fuse]: https://github.com/sgan81/apfs-fuse "APFS Fuse Driver"
