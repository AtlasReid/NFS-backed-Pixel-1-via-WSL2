# File inventory

| File | Purpose |
|---|---|
| `README.md` | Complete end-to-end procedure and architecture |
| `SECURITY.md` | Threat model and safe-use boundaries |
| `.gitignore` | Prevents private/vendor/device artifacts from being committed |
| `docs/CASE-STUDY.md` | Exact verified installation and lessons from failed attempts |
| `docs/NFS-ROLLBACK.md` | Verified return to ordinary Magisk root and removal of the NFS-specific WSL host |
| `docs/TROUBLESHOOTING.md` | Symptom-based diagnostics and recovery |
| `docs/VERIFIED-ARTIFACTS.md` | Byte sizes and SHA-256 evidence from the reference installation |
| `kernel/sailfish_72a7a64494e_defconfig` | Kernel config captured from the A3 `sailfish` device |
| `module/module.prop.template` | Magisk module metadata template |
| `module/service.sh.template` | Boot service with Android-storage and NFS TCP readiness checks |
| `module/mount_nfs.sh` | Global-namespace NFS and `sdcardfs` mount implementation |
| `scripts/Setup-PixelNFS.ps1` | Creates the dedicated WSL distro, sparse ext4 store, NFS services, and initial firewall rules |
| `scripts/Repair-PixelNFS-NAT.ps1` | Configures reliable NAT forwarding, gateway-aware exports, firewall restriction, and logon refresh |
| `scripts/Remove-PixelNFS.ps1` | Safely unregisters only the dedicated NFS distro and removes its exact Windows integration/storage paths |
| `scripts/Build-SailfishNfsKernels.ps1` | Windows wrapper for the pinned Nix kernel build |
| `scripts/wsl/build-sailfish-nfs-kernels.sh` | Builds reference and NFS kernels inside Ubuntu |
| `scripts/Backup-PixelBootSlots.ps1` | Reads and hashes complete `boot_a` and `boot_b` partitions |
| `scripts/Repack-NfsBoot.ps1` | Inserts the NFS kernel into a working Magisk image and restores the legacy-SAR patch |
| `scripts/Flash-NfsBoot.ps1` | Checks product, slot, unlock state, and image size before flashing one boot slot |
| `scripts/Restore-PixelBootSlot.ps1` | Hash-verifies and restores a saved boot partition |
| `scripts/Manual-Mount.ps1` | Installs and runs the mount script for a one-off test |
| `scripts/Build-Install-AutomountModule.ps1` | Builds, stages, permissions, and optionally reboots into the automount module |
| `scripts/Verify-PixelNfs.ps1` | Read-only device, root, kernel, network, mount, capacity, and log checks |

Files intentionally absent: factory ZIPs, boot images, Magisk APKs, full partition backups, drivers, WSL disk images, module ZIP outputs, and logs.
