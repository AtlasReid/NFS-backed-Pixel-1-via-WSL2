# Troubleshooting

## Fastboot says the image is too large

Check the exact byte size:

```powershell
(Get-Item .\boot.img).Length
```

Pixel 1's boot partition is 33,554,432 bytes. Do not try to force an oversized image. In the reference installation, Magisk 30.7 was too large while 30.6 fit.

## `fastboot boot` fails with `dtb not found`

This can be a Pixel 1 bootloader limitation rather than a corrupt image. Validate the image header, appended DTB, size, device/build, and rollback image. The verified installation had to flash the active boot partition because temporary booting was unavailable.

Never use this observation as permission to flash an unverified image.

## Android boots but `su` is missing

If this happens immediately after swapping kernels into an existing Magisk image, the replacement likely removed Magisk's legacy system-as-root kernel patch.

Restore the original boot partition, then repack with:

```text
skip_initramfs\0 -> want_initramfs\0
```

The provided `Repack-NfsBoot.ps1` applies Magisk 30.6's exact hex patch.

## NFS options are absent

Check:

```sh
su -c 'zcat /proc/config.gz | grep CONFIG_NFS'
cat /proc/filesystems | grep nfs
```

Expected entries include `CONFIG_NFS_FS=y`, `CONFIG_NFS_V3=y`, `nfs`, and `nfs4`.

## NFS ports are closed

From the Pixel:

```sh
su -c '/data/adb/magisk/busybox nc -z -w 3 SERVER 111'
su -c '/data/adb/magisk/busybox nc -z -w 3 SERVER 2049'
su -c '/data/adb/magisk/busybox nc -z -w 3 SERVER 20048'
```

Rerun the NAT repair script as Administrator and inspect `netsh interface portproxy show v4tov4`. Confirm that the `PixelNFS` distro is running and the laptop has the reserved address used by the module.

## Mount returns `Permission denied` and Toybox says the source is read-only

Toybox may print a generic read-only retry message after the kernel returns `EACCES`; it does not prove the export is actually read-only.

With Windows portproxy, the WSL NFS daemon sees the WSL gateway as the client. Ensure `/etc/exports` authorizes that gateway and rerun `exportfs -ra`. `Repair-PixelNFS-NAT.ps1` does this dynamically.

## Manual mount works but automount does not

Check:

```sh
su -c 'dmesg | grep pixel-nfs'
su -c 'ls -la /data/adb/modules/pixel_nfs_automount'
```

Common causes:

- `service.sh` or `mount_nfs.sh` is not executable.
- The module waited on ICMP ping even though Windows blocks it.
- The laptop/NFS server was unavailable longer than the retry window.
- The Pixel's DHCP address changed and no longer matches the firewall rule.

The supplied module uses a TCP/2049 readiness check and fixes script permissions after Magisk stages the ZIP.

## The mount exists under `/mnt` but not in apps

It must be created in PID 1's global mount namespace and mapped through Android's storage layer:

```sh
su -c '/data/adb/magisk/busybox nsenter -t 1 -m -- mount'
```

Look for both the NFS mount and an `sdcardfs` mount ending in `/the_binding`.

## ADB shell cannot create a file in `the_binding`

The ADB `shell` user is not necessarily a member of Android's `everybody` group used by the `sdcardfs` mapping. It may be able to read but not create files even though media apps with storage permission work. Test writes through the NFS mount as root and reads through `/storage/emulated/0/the_binding` as a normal user.

## Files do not appear in Google Photos immediately

Force-close and reopen Google Photos, confirm backup is enabled for the `the_binding` device folder, and trigger a media scan:

```sh
su -c '/data/adb/magisk/busybox nsenter -t 1 -m -- am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///storage/emulated/0/the_binding/'
```

Boot-time media services may not be ready for the first broadcast; the supplied service waits an additional 15 seconds before sending it.

## WSL starts but the share disappears after reboot

Inspect the scheduled task named `Pixel NFS Server`. It must run with administrative rights because it refreshes Windows portproxy rules. Rerun `Repair-PixelNFS-NAT.ps1` to recreate it.

## Emergency rollback

1. Hold **Power + Volume Down** until the bootloader appears.
2. Connect USB.
3. Run the hash-checking `Restore-PixelBootSlot.ps1` command prepared before flashing.
4. Do not flash a different slot or factory package unless you understand the A/B state.
