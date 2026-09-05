# Verified artifacts from the reference installation

These hashes document one successful installation on a Google Pixel `sailfish`, Android 10 build `QP1A.191005.007.A3`. They are evidence, not downloadable binaries. Google factory/device binaries and Magisk artifacts are intentionally excluded from this repository.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Google factory ZIP | 1,386,103,670 | `D455265945BB936A653730031AF7D7A4ABA70DC0C775024666A53491C9833B61` |
| Extracted factory `boot.img` | 31,532,262 | `B020DBA98C188955B5DF150D1639D81A9A5A1CC7BBF04AEE93A797B23E49B445` |
| Magisk 30.6 patched boot | 31,814,954 | `AE2A2026BE45742B0BC30B00F8423BADA74796E38E5478A57BE80D276044FBF3` |
| Magisk 30.7 patched boot (too large) | 34,301,226 | `234C1186C2E05A3C0BBE75B35E5361593B0A340D84D4EC5D0F115F4ED4105C43` |
| Rebuilt reference kernel | 21,154,878 | `A0DD6F032C99DE89EA0A9E73447BE2C9DD08524ABC06C70218F8890E6B50029B` |
| NFS-enabled kernel | 21,529,240 | `0E0C1F7DBA02161B1DF63D64A859E716E896B3224C94836D413A49EC4CA9A252` |
| Final Magisk 30.6 + NFS + legacy-SAR boot | 32,187,690 | `F8FBAF6917FB8E8C6B2C80F138A5A98B71146F54ADA0EFA816D9FD039A154110` |
| Automount module used in the session | 3,057 | `DE5BC6ABC36FAA73894BA7F05EA488CA1C8036167E6051E5F6872FF107778310` |
| Full `boot_a` partition backup | 33,554,432 | `5E54A53D08CDB6639D078DEC8C08FC9229CFF7913F583CBE8F1FD41DEA93D3CE` |
| Full pre-NFS `boot_b` partition backup | 33,554,432 | `9884B5828187746F56A9DDB4131B9078F1FC84D82E30F7E3BC62AED14BF5AB5D` |
| `/proc/config.gz` from the phone | 28,025 | `468FC83627FBF8937A3151370679135B6D66988F0352196122CE69B04AEA31CD` |
| Decompressed kernel config | 123,834 | `33E5ABC5F841ECF43B3317B5A23B0C6EA330EEBA977615F815A43E2D9084AE6D` |

The 32 MiB boot-partition ceiling is 33,554,432 bytes. The final image had 1,366,742 bytes of headroom.

After the NFS teardown on 2026-09-05, the live `/dev/block/by-name/boot_b` hash was `9884B5828187746F56A9DDB4131B9078F1FC84D82E30F7E3BC62AED14BF5AB5D`, exactly matching the complete pre-NFS `boot_b` backup above. Magisk 30.6 root remained functional on Google's original A3 kernel.

Upstream `pixel-backup-gang` revision used: `d91c366eabf44e852e66d88afcebf16a85dc27e4`.

Google kernel source revision used by the upstream Nix expression: `72a7a64494e033f2213c9701dbf137d277bf2026`.
