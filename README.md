# Pixel 1 NFS-backed internal storage on Windows and WSL2

This guide documents a verified end-to-end setup for a first-generation Google Pixel (`sailfish`) running Android 10 build `QP1A.191005.007.A3`. It unlocks and roots the phone, builds an NFS-enabled 3.18 kernel, hosts a capped NFSv3 export in Ubuntu on WSL2, exposes that export inside Android internal storage, and mounts it automatically through Magisk.

It was developed while following and extending [master-hax/pixel-backup-gang](https://github.com/master-hax/pixel-backup-gang). The exact upstream revision used was `d91c366eabf44e852e66d88afcebf16a85dc27e4`.

> [!NOTE]
> On 2026-09-05, the reference phone was returned to Magisk 30.6 root on Google's original A3 kernel and the NFS-specific phone/Windows components were removed. The verified teardown and transition boundary are documented in [docs/NFS-ROLLBACK.md](docs/NFS-ROLLBACK.md). The historical NFS procedure remains here as a reproducible case study.

> [!CAUTION]
> This is an advanced, destructive procedure for an end-of-life phone. Unlocking wipes the device. Flashing the wrong image can make it unbootable. NFSv3 is unencrypted and must remain on a trusted LAN. Read [SECURITY.md](SECURITY.md) and prepare a verified rollback image before flashing a custom kernel.

## What this creates

```text
Windows
  \\wsl.localhost\PixelNFS\srv\pixel-backup\the_binding
                         │
                         │ NFSv3/TCP through Windows portproxy
                         ▼
Pixel global namespace
  /mnt/pixel_nfs/the_binding
                         │
                         │ sdcardfs mapping
                         ▼
Android internal storage
  /storage/emulated/0/the_binding
```

Files placed in the Windows `the_binding` directory appear to Android media applications as an internal-storage device folder. The guide does not replace `DCIM/Camera`; keeping a separate folder avoids hiding camera files when the laptop is offline.

## Verified target and important limits

- Device: Pixel 1 `sailfish`, not Pixel XL `marlin`
- Android build: `QP1A.191005.007.A3`
- Kernel source: Google MSM commit `72a7a64494e033f2213c9701dbf137d277bf2026`
- Boot partition: exactly 32 MiB or 33,554,432 bytes
- Root image used: Magisk 30.6
- NFS: version 3 over TCP
- Host: Windows 11 with Ubuntu/WSL2

Do not blindly reuse these boot artifacts on another build. Verify `ro.product.device`, `ro.build.id`, the active slot, the kernel version, and the partition size first.

## Repository contents

```text
.
├── README.md
├── SECURITY.md
├── docs/
│   ├── CASE-STUDY.md
│   ├── FILE-INVENTORY.md
│   ├── NFS-ROLLBACK.md
│   ├── PUBLISHING-CHECKLIST.md
│   ├── TROUBLESHOOTING.md
│   └── VERIFIED-ARTIFACTS.md
├── kernel/
│   └── sailfish_72a7a64494e_defconfig
├── module/
│   ├── module.prop.template
│   ├── mount_nfs.sh
│   └── service.sh.template
└── scripts/
    ├── Backup-PixelBootSlots.ps1
    ├── Build-Install-AutomountModule.ps1
    ├── Build-SailfishNfsKernels.ps1
    ├── Flash-NfsBoot.ps1
    ├── Manual-Mount.ps1
    ├── Repack-NfsBoot.ps1
    ├── Repair-PixelNFS-NAT.ps1
    ├── Remove-PixelNFS.ps1
    ├── Restore-PixelBootSlot.ps1
    ├── Setup-PixelNFS.ps1
    ├── Verify-PixelNfs.ps1
    └── wsl/build-sailfish-nfs-kernels.sh
```

The `.gitignore` deliberately excludes factory images, boot images, partition backups, APKs, logs, WSL disks, and build outputs.

## 1. Install host prerequisites

Install:

- [Current Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools)
- [Google USB driver for Windows](https://developer.android.com/studio/run/win-usb)
- WSL2 and Ubuntu
- Git

If Windows does not bind the Pixel to the Google ADB/Fastboot driver, download the official driver, extract it, and install its INF from Administrator PowerShell:

```powershell
pnputil /add-driver C:\path\to\usb_driver\android_winusb.inf /install
```

In an Administrator PowerShell window:

```powershell
wsl --install -d Ubuntu
```

Start Ubuntu once and allow its first-launch setup to complete:

```powershell
wsl -d Ubuntu
```

On the phone, enable **Developer options**, **OEM unlocking**, and **USB debugging**. Connect by USB, accept the debugging authorization prompt, and verify:

```powershell
adb devices -l
adb shell getprop ro.product.device
adb shell getprop ro.build.id
```

Expected for this guide:

```text
sailfish
QP1A.191005.007.A3
```

## 2. Unlock the bootloader

> [!WARNING]
> Unlocking performs a factory reset. Back up anything important first.

```powershell
adb reboot bootloader
fastboot flashing unlock
```

Confirm the unlock on the phone with the volume and power buttons. After the wipe, complete Android setup, re-enable USB debugging, and verify:

```powershell
adb reboot bootloader
fastboot getvar unlocked
fastboot getvar current-slot
fastboot reboot
```

## 3. Obtain the matching factory boot image

Download the matching `sailfish` build from Google's [factory image page](https://developers.google.com/android/images). Google's terms restrict redistribution, so do not commit the factory ZIP or extracted `boot.img`.

Extract the outer factory ZIP, then extract the nested `image-sailfish-...zip`. Copy its `boot.img` into a private `artifacts` directory and record its hash:

```powershell
Get-FileHash -Algorithm SHA256 .\artifacts\stock-boot.img
```

For the verified A3 installation, the factory ZIP and stock boot hashes are recorded in [docs/VERIFIED-ARTIFACTS.md](docs/VERIFIED-ARTIFACTS.md).

## 4. Root with Magisk while respecting the 32 MiB ceiling

Install the official [Magisk 30.6 APK](https://github.com/topjohnwu/Magisk/releases/tag/v30.6) on the Pixel. Copy the matching stock `boot.img` to the phone, then use Magisk's **Select and Patch a File** workflow. Pull the result back to Windows.

Before flashing, check its size:

```powershell
$image = Get-Item .\artifacts\magisk-patched.img
$limit = 33554432
$image.Length
$limit - $image.Length
```

In the reference installation, Magisk 30.7 produced a 34,301,226-byte image and fastboot rejected it as too large. Magisk 30.6 produced a 31,814,954-byte image and fit. This is an observed compatibility constraint, not a recommendation to use an old Magisk version on unrelated devices.

Flash only the current slot's boot partition:

```powershell
adb reboot bootloader
fastboot getvar current-slot
fastboot flash boot_b .\artifacts\magisk-patched.img
fastboot reboot
adb shell su -c id
```

Replace `boot_b` if your verified active slot is A.

## 5. Back up both boot partitions

Once Magisk root works, make byte-for-byte backups before building or flashing the NFS kernel:

```powershell
.\scripts\Backup-PixelBootSlots.ps1 `
  -PlatformTools C:\Android\platform-tools `
  -OutputDirectory .\artifacts\boot-backups
```

Save the reported SHA-256 values separately. The files should each be exactly 33,554,432 bytes.

Prepare the restore command before proceeding:

```powershell
.\scripts\Restore-PixelBootSlot.ps1 `
  -PlatformTools C:\Android\platform-tools `
  -BackupImage .\artifacts\boot-backups\boot_b-full.img `
  -ExpectedSha256 YOUR_RECORDED_HASH `
  -Slot b
```

Do not run it now; keep it ready for recovery.

## 6. Confirm and capture the running kernel configuration

```powershell
adb shell su -c "zcat /proc/config.gz" > .\artifacts\sailfish-running.config
Get-FileHash -Algorithm SHA256 .\artifacts\sailfish-running.config
```

The verified phone reported:

```text
Linux version 3.18.137-g72a7a64494e
```

Its decompressed configuration was byte-for-byte identical to the upstream project's `marlin_72a7a64494e_defconfig`. Pixel and Pixel XL share this Google kernel tree/configuration for the A3 build, even though their boot images and ramdisks must not be interchanged. The matching config is retained at [kernel/sailfish_72a7a64494e_defconfig](kernel/sailfish_72a7a64494e_defconfig).

## 7. Build reference and NFS-enabled kernels

Clone the upstream project at the verified revision:

```powershell
git clone https://github.com/master-hax/pixel-backup-gang.git
git -C .\pixel-backup-gang checkout d91c366eabf44e852e66d88afcebf16a85dc27e4
```

Build both an unchanged reference and an NFS-enabled kernel:

```powershell
.\scripts\Build-SailfishNfsKernels.ps1 `
  -UpstreamRepository .\pixel-backup-gang `
  -OutputDirectory .\artifacts\kernel-build
```

The Nix build pins the Google kernel source and GCC toolchains. The special kernel enables:

```text
CONFIG_NETWORK_FILESYSTEMS=y
CONFIG_NFS_FS=y
CONFIG_NFS_V3=y
CONFIG_NFS_V4=y
```

The reference kernel will not be byte-identical to Google's binary because its build timestamp/user metadata differs. Validate the source revision, GCC version, config, header, and successful boot rather than expecting the compressed bytes to match.

## 8. Insert the NFS kernel into the working Magisk image

Do not use the upstream `marlin` boot image on `sailfish`. Repack your own known-good, matching `sailfish` Magisk 30.6 boot image:

```powershell
.\scripts\Repack-NfsBoot.ps1 `
  -PlatformTools C:\Android\platform-tools `
  -WorkingMagiskBootImage .\artifacts\magisk-patched.img `
  -NfsKernel .\artifacts\kernel-build\nfs-Image.lz4-dtb `
  -OutputImage .\artifacts\sailfish-nfs-magisk.img
```

This script runs Magisk's own `magiskboot` on the rooted phone. It:

1. Unpacks the known-good Magisk image.
2. Decompresses the new `Image.lz4-dtb`.
3. Replaces only the kernel.
4. Reapplies the Pixel 1 legacy system-as-root patch: `skip_initramfs` to `want_initramfs`.
5. Repackages the original Magisk ramdisk.
6. Rejects output larger than 32 MiB.

Without step 4, Android can boot but Magisk will disappear because the kernel skips the patched ramdisk.

## 9. Flash and verify the NFS/Magisk image

The original Pixel may reject `fastboot boot image.img` with `dtb not found` even for a flashable image. Since temporary boot testing may be unavailable, verify the rollback backup first and flash only the active boot slot:

```powershell
.\scripts\Flash-NfsBoot.ps1 `
  -PlatformTools C:\Android\platform-tools `
  -Image .\artifacts\sailfish-nfs-magisk.img `
  -Slot b
```

After Android starts:

```powershell
adb shell uname -a
adb shell su -c id
adb shell su -c "zcat /proc/config.gz | grep CONFIG_NFS"
```

If it does not boot, hold **Power + Volume Down**, connect fastboot, and run the prepared restore script.

## 10. Create the 512 GiB WSL2 NFS server

Reserve fixed LAN addresses for both the Windows laptop and the Pixel. Example only:

```text
Laptop: 192.168.8.167
Pixel:  192.168.8.143
```

The setup creates a dedicated `PixelNFS` WSL distribution under the chosen storage root and a sparse ext4 image. Physical usage grows as data is written; the logical ceiling defaults to 512 GiB.

Run in Administrator PowerShell:

```powershell
.\scripts\Setup-PixelNFS.ps1 `
  -PixelAddress 192.168.8.143 `
  -LaptopAddress 192.168.8.167 `
  -StorageRoot D:\NFSFolder1 `
  -CapacityGiB 512
```

The first script attempts WSL mirrored networking. On systems where Windows reserves NFS port 2049 or mirrored mode does not pass NFS reliably, apply the verified NAT/portproxy configuration:

```powershell
.\scripts\Repair-PixelNFS-NAT.ps1 `
  -PixelAddress 192.168.8.143 `
  -ExternalAddress 192.168.8.167 `
  -StorageRoot D:\NFSFolder1
```

The NAT repair:

- switches WSL2 to NAT mode;
- fixes NFSv3 services on TCP 111, 2049, and 20048;
- forwards those Windows ports to the current WSL address;
- discovers and authorizes the WSL gateway seen by `rpc.mountd`;
- keeps the Windows inbound firewall restricted to the Pixel's reserved address;
- installs a logon task that refreshes forwarding when WSL's address changes.

Windows can access the export at:

```text
\\wsl.localhost\PixelNFS\srv\pixel-backup
```

## 11. Test a manual Android mount

```powershell
.\scripts\Manual-Mount.ps1 `
  -PlatformTools C:\Android\platform-tools `
  -NfsServer 192.168.8.167
```

Then place a test file in:

```text
\\wsl.localhost\PixelNFS\srv\pixel-backup\the_binding
```

Read it on Android at:

```text
/storage/emulated/0/the_binding
```

The mapping uses Android's global mount namespace. Running `mount` from an ordinary ADB/Magisk namespace can give a false impression that it is missing; use `nsenter -t 1 -m` as the scripts do.

## 12. Install the Magisk automount module

```powershell
.\scripts\Build-Install-AutomountModule.ps1 `
  -PlatformTools C:\Android\platform-tools `
  -NfsServer 192.168.8.167 `
  -NfsExport /srv/pixel-backup
```

The service waits for Android storage and TCP/2049, not ICMP ping. This matters when Windows blocks ping while allowing NFS. It mounts in the global namespace, waits briefly for Android media services, then broadcasts a media scan.

After reboot, verify:

```powershell
.\scripts\Verify-PixelNfs.ps1 `
  -PlatformTools C:\Android\platform-tools `
  -NfsServer 192.168.8.167
```

## Google Photos and DCIM

The safe default is a separate internal-storage folder named `the_binding`. In Google Photos, enable backup for that device folder. The upstream README rhetorically mentions mounting a NAS into DCIM, but its implemented NFS script exposes `/the_binding` instead.

Directly replacing `DCIM` is risky: it can hide locally captured photos, confuse the Camera app, and make the folder vanish when the server is offline. If DCIM placement is unavoidable, mount only a child such as `DCIM/NFSBackup`, never over `DCIM/Camera`, and test camera behavior with the server unavailable.

## Recovery and maintenance

- If the phone fails to boot, use [Restore-PixelBootSlot.ps1](scripts/Restore-PixelBootSlot.ps1).
- To retire the dedicated Windows/WSL server after restoring a non-NFS boot image, use [Remove-PixelNFS.ps1](scripts/Remove-PixelNFS.ps1) from Administrator PowerShell. Read [the rollback record](docs/NFS-ROLLBACK.md) first.
- If the laptop was off for more than the automount retry window, start the server and reboot the Pixel or run [Manual-Mount.ps1](scripts/Manual-Mount.ps1).
- If the WSL address changes and mounting fails, rerun [Repair-PixelNFS-NAT.ps1](scripts/Repair-PixelNFS-NAT.ps1).
- Check module logs with `adb shell su -c "dmesg | grep pixel-nfs"`.
- Keep Windows from sleeping while large uploads are active.
- Do not accept Android OTAs without rebuilding and validating the boot image for the new build.

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for failure-specific recovery steps and [docs/CASE-STUDY.md](docs/CASE-STUDY.md) for the exact verified session.

Before publishing, review [docs/PUBLISHING-CHECKLIST.md](docs/PUBLISHING-CHECKLIST.md) and the complete [file inventory](docs/FILE-INVENTORY.md).

## Attribution

This work was inspired by and tested against [master-hax/pixel-backup-gang](https://github.com/master-hax/pixel-backup-gang). That repository did not expose a license file at the pinned revision, so its source files are not redistributed here. The compatible mount implementation in this repository was written separately from the verified behavior and command sequence.
