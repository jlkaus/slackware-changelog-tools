#!/usr/bin/perl

use strict;
use warnings;


# Determine which kernels are currently:
#   in-use (booted & running, uname -r)
#   installed packages (vmlinuz, headers, firmware, source, modules)
#   exist in the efi boot directories, including which have initrds.  /boot/efi/EFI/Slackware/
#   Referenced in elilo configuration (including which should have initrds)
#   most recently available from upstream

# The currently in-use and referenced in elilo config may only be determined to a version precision
# Currently in the efi boot directories likely can only be determined by md5sum comparisons with installed versions?
# Packages (installed and available) may also have a "build" number associated with it, that is important...


# Ideally, we should keep kernels installed that are currently in-use,
# as well as the newest one, and potentially some prior one, preferably one that has been booted before,
# if we are already running the latest.

# There may be some inconsistent states that could occur from prior failures or from non-rigorous installations
# before the script safely manages things.

# The script should use the changelog parser, operating on the current slackware version's latest changelog,
# to determine available kernel packages available.
# Note that the actual kernel binaries, the kernel modules, and the kernel source can all be installed side-by-side with each other
# and other versions of themselves, but the kernel headers and firmware cannot be.  Also, different build numbers of each packaged version cannot
# exist side-by-side, either.

# Therefore, the kernel headers and firmware are not managed here and are presumed to be updated to the latest version always, by some other process.
# Also, if a version has a "rebuild", the "rebuild" (newer build number) will always replace the older build of that version.

# So, we keep:
#  Latest version (matching headers), latest build of that version
#  If different than the latest available version, the currently executing version (matching uname -r), latest build of that version
#  If we are currently executing the latest version, we'll also keep the latest available build of the second latest available version currently installed.
# Perhaps we also keep some larger number downloaded, say, every version (latest build of each) from the old to the new, and at least the last 5?
# This will enable manually choosing different versions to boot, in the case of problems.

# ELILO Config & Binaries placed in EFI directories:
#  Entry for the latest version, huge.  Associated binary is vmlinuz-huge
#  Entry for the latest version, generic.  Associated binary is vmlinuz-generic.  Needs an initrd.gz generated.
#  Entry for the older version, huge.  Associated binary is vmlinuz-huge-old
#  Entry for the older version, generic.  Associated binary is vmlinuz-generic-old.  Needs an initrd generated (initrd-old.gz).

# In /boot, the actual kernels are installed, versioned.  Also, any generated initrds should be generated here, and versioned.
# In /boot/efi/.../Slackware, the appropriate files are copied over into names that match the elilo config files, to prevent needing
# to change the elilo config:  vmlinuz-huge, vmlinuz-generic, vmlinuz-huge-old, vmlinuz-generic-old, initrd.gz, initrd-old.gz

# Initrd generation should be handled for each kernel version assuming the initrd config file in /etc is correct.

# Allow options on this script to use specific versions as the next-to-boot or old-boot versions.
# Allow options to avoid going to the Internet to find the available kernels.  Instead, we just work with what we have locally, and validate consistency.
# Options to just do a dry-run to determine what would be done.


# Perhaps this script just sets the links for vmlinuz-huge, vmlinuz-generic, vmlinuz-old-huge, vmlinuz-old-generic, and their initrds, in /boot,
# to point to the correct versions, then copies from those linked binaries into the EFI location.
# Then, an option might just be to re-copy the linked binaries into the EFI location.
