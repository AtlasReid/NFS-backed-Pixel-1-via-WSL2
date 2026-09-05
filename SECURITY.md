# Security notes

This setup deliberately unlocks and modifies an end-of-life Android device. It is appropriate only for a dedicated device whose loss or compromise is acceptable.

- Unlocking the bootloader erases the phone and weakens physical security.
- Android 10 on the first-generation Pixel no longer receives normal security updates.
- NFSv3 is not encrypted or authenticated. Use it only on a trusted private LAN.
- Reserve the Pixel's LAN address and restrict the Windows firewall to that address.
- Do not expose TCP ports 111, 2049, or 20048 to the internet.
- Do not commit factory images, patched boot images, partition backups, Magisk APKs, WSL disk images, logs containing personal paths, or credentials.
- Keep an exact, hashed backup of the active boot partition on a different storage device.

The scripts intentionally refuse several ambiguous operations, but they cannot make bootloader flashing risk-free. Read each script before running it.
