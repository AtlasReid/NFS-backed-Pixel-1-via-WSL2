# Retiring the NFS setup before external-drive testing

This record documents the verified 2026-09-05 transition from the NFS-backed setup to an ordinary rooted Pixel 1. It stops before formatting or mounting any USB drive.

The next phase follows the upstream [external-drive guide](https://github.com/master-hax/pixel-backup-gang/blob/master/docs/EXTERNAL_DRIVES.md), which expects a rooted Android 10 Pixel and an ext4 or FAT32 USB storage device. The custom NFS kernel is not required for that workflow.

## Scope

The teardown was deliberately limited to:

- the NFS-enabled boot image on active slot B;
- the `pixel_backup_gang_nfs_automount` Magisk module;
- the dedicated `PixelNFS` WSL2 distribution;
- the NFS portproxy, firewall, and scheduled-task integration;
- the dedicated storage root `D:\NFSFolder1`.

The bootloader remained unlocked, Magisk root was retained, and the general `Ubuntu` WSL2 distribution was preserved for Linux tooling.

## Verified starting state

Before changing anything, the phone reported:

```text
device:  sailfish
build:   QP1A.191005.007.A3
slot:    B
root:    uid=0(root), Magisk context
Magisk:  30.6 (30600)
module:  pixel_backup_gang_nfs_automount v2
```

NFS was mounted from `192.168.8.167:/srv/pixel-backup` at `/mnt/my_drive`, with `the_binding` exposed through Android's storage views.

The complete restore image was checked before use:

```text
file:    boot_b-full.img
bytes:   33,554,432
SHA-256: 9884B5828187746F56A9DDB4131B9078F1FC84D82E30F7E3BC62AED14BF5AB5D
```

## Phone rollback

Mark only the NFS module for removal and flush pending writes:

```powershell
adb shell su -c "touch /data/adb/modules/pixel_backup_gang_nfs_automount/remove"
adb shell su -c sync
adb reboot bootloader
```

Validate the fastboot target before flashing:

```powershell
fastboot getvar product
fastboot getvar current-slot
fastboot getvar unlocked
fastboot getvar slot-successful:b
fastboot getvar slot-unbootable:b
```

The verified values were `sailfish`, slot `b`, `unlocked: yes`, successful, and bootable. Only the active boot partition was restored:

```powershell
fastboot flash boot_b .\artifacts\boot-backups\boot_b-full.img
fastboot reboot
```

Do not copy this slot letter or image to another phone without independently verifying its device, build, active slot, image hash, and boot-partition size.

## Phone verification after reboot

The restored phone reported:

```text
device:  sailfish
build:   QP1A.191005.007.A3
slot:    B
root:    uid=0(root), Magisk context
Magisk:  30.6:MAGISK:R (30600)
kernel:  3.18.137-g72a7a64494e, Google build dated 2019-09-27
modules: none
NFS-related mounts: none
```

The live boot partition was hashed after the reboot:

```text
9884B5828187746F56A9DDB4131B9078F1FC84D82E30F7E3BC62AED14BF5AB5D  /dev/block/by-name/boot_b
```

That is an exact match for the saved pre-NFS backup. An empty `grep CONFIG_NFS` result from `/proc/config.gz` also confirmed that the custom NFS options were no longer present.

## Windows/WSL teardown

Run the guarded cleanup script from Administrator PowerShell:

```powershell
.\scripts\Remove-PixelNFS.ps1 `
  -ServerDistro PixelNFS `
  -StorageRoot D:\NFSFolder1
```

The script:

1. Stops and deletes the `Pixel NFS Server` scheduled task.
2. Deletes only TCP portproxy listeners `111`, `2049`, and `20048` on `0.0.0.0`.
3. Removes the `PixelNFS-*` firewall rules created by this setup.
4. Terminates and unregisters only the `PixelNFS` distribution.
5. Confirms that the distro is no longer registered.
6. Validates resolved paths before recursively deleting any residual `PixelNFS` directory.
7. Removes the portproxy helper and deletes `D:\NFSFolder1` only when nothing unrelated remains.

Unregistering a WSL distro permanently deletes the files inside its virtual disk. Back up the export before running the script.

## Verified host state after removal

The elevated cleanup completed successfully. Independent checks found:

```text
PixelNFS WSL distribution: absent
TCP portproxy 111/2049/20048: absent
Pixel NFS firewall rule: absent
Pixel NFS Server scheduled task: absent
D:\NFSFolder1: absent
Remaining WSL distribution: Ubuntu, stopped, version 2
```

## Boundary before the external-drive phase

At this point, the NFS experiment is fully retired and the phone is in the intended baseline state for external-drive work. Before proceeding:

- identify the USB device and partition unambiguously;
- back up anything already on the drive;
- choose ext4 or FAT32 based on file-size and interoperability requirements;
- do not format or mount a device until its exact block-device path has been rechecked after connection;
- keep the verified rooted boot backup available throughout testing.
