# Publishing checklist

Before pushing this folder to a public GitHub repository:

- Read every script and replace `YOUR_NAME` in `module/module.prop.template`.
- Choose and add a license for the original material in this repository.
- Confirm `git status` contains no files ignored by `.gitignore` through an override or force-add.
- Run a secret scanner if one is available.
- Do not add Google factory images or extracted device binaries; Google's download terms restrict redistribution.
- Do not add Magisk APKs or patched boot images.
- Do not add partition backups, WSL disk images, logs, DHCP/router exports, or credentials.
- Keep the private-LAN addresses in the case study only if you are comfortable publishing them.
- Preserve the upstream attribution and pinned revision.
- Prefer a release checklist that requires users to build their own boot image for their exact device/build.
