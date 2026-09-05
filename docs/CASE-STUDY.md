# Reference installation case study

## Final state

| Item | Verified value |
|---|---|
| Device | Google Pixel (`sailfish`) |
| Android | 10, `QP1A.191005.007.A3` |
| Active slot | B |
| Original kernel | `3.18.137-g72a7a64494e` |
| Root | Magisk 30.6 |
| Laptop LAN address | `192.168.8.167` |
| Pixel LAN address | `192.168.8.143` |
| WSL distro | `PixelNFS` |
| WSL NAT address during setup | `172.17.133.198` |
| WSL gateway authorized by NFS | `172.17.128.1` |
| Export | `/srv/pixel-backup` |
| Android-visible folder | `/storage/emulated/0/the_binding` |
| Windows-visible folder | `\\wsl.localhost\PixelNFS\srv\pixel-backup\the_binding` |
| Capacity ceiling | 512 GiB sparse image; about 503 GiB usable after formatting |

Both the laptop and Pixel addresses should be reserved in the router. The example addresses are private LAN addresses, not public endpoints.

## What went wrong and what it taught us

### Magisk 30.7 exceeded the boot partition

The Pixel 1 boot partitions are exactly 33,554,432 bytes. In this installation:

- Magisk 30.6 produced a 31,814,954-byte image.
- Magisk 30.7 produced a 34,301,226-byte image.

Fastboot correctly refused the oversized image. The solution was to use Magisk 30.6 and check every image size before flashing.

### `fastboot boot` returned `dtb not found`

The original Pixel bootloader rejected a temporary `fastboot boot candidate.img` test with `FAILED (remote: 'dtb not found')`. The image later booted successfully when flashed normally. This is a known limitation seen on `sailfish`; do not interpret it alone as proof that the appended DTB is absent.

Because temporary booting was unavailable, the active boot partition was backed up byte-for-byte before testing. Only `boot_b` was changed, and a hash-checking rollback script was prepared first.

### The first NFS kernel booted but Magisk disappeared

Replacing the kernel in an already-patched Magisk image also replaced Magisk's Pixel 1 legacy system-as-root kernel patch. Android booted, but `su` was missing because the kernel still contained `skip_initramfs` and skipped the Magisk ramdisk.

The original boot partition was restored. The corrected build reapplied Magisk 30.6's exact transformation:

```text
skip_initramfs\0 -> want_initramfs\0
736B69705F696E697472616D667300
77616E745F696E697472616D667300
```

The corrected image booted with both the NFS kernel and Magisk root.

### The NFS server denied the Pixel after NAT forwarding

The Windows port proxy accepted traffic from `192.168.8.143`, but the Linux NFS daemon saw the forwarded connection as coming from the WSL gateway `172.17.128.1`. An export restricted only to the Pixel address therefore returned `EACCES`.

The NAT repair script now discovers the WSL gateway and authorizes both the Pixel address and that gateway in `/etc/exports`. The Windows firewall remains restricted to the Pixel's LAN address, so other LAN clients cannot use the forwarding rules.

### Automount waited forever on ping

Windows allowed NFS TCP ports but did not answer ICMP echo. The upstream-style service waited for `ping`, even though TCP/2049 was already usable. The module in this repository checks the service it actually needs:

```sh
/data/adb/magisk/busybox nc -z -w 1 SERVER 2049
```

After this change, the share mounted automatically about 24 seconds after boot.

### The inactive slot was a different Android build

Slot B was A3, but a read-only inspection found A1 on slot A. Both releases use the same kernel source, but mixing an A3 boot ramdisk with the A1 system was avoided. Testing stayed on slot B with a verified rollback image.

## Final verification

The final reboot verified:

- Android reached `sys.boot_completed=1`.
- Kernel banner matched the NFS build.
- `su -c id` returned UID 0 in Magisk context.
- `CONFIG_NETWORK_FILESYSTEMS`, `CONFIG_NFS_FS`, `CONFIG_NFS_V3`, and `CONFIG_NFS_V4` were enabled.
- TCP ports 111, 2049, and 20048 were reachable.
- NFSv3 mounted read-write over TCP.
- The `sdcardfs` mapping appeared in all Android storage views.
- A file written through NFS was readable at `/storage/emulated/0/the_binding` and could be deleted.
- A post-boot Android media-scan broadcast succeeded.
