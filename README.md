# BTRFS root subvolume rollback utility.
This utility rolls back BTRFS subvolume to previously created snapshot without booting from live usb and manual editing config files.
It supports any subvolume naming scheme.

## Requirements
1. BTRFS file system.
2. Snapper installed and configured for root.


## Usage
Run restore script as root:
./restore.sh -c <snapper_config> -s <path_to_desired_snapshot> -v <subvolume_name> [OPTIONS]
   

### Options

-c | --config - snapper config
                default: root

-d | --device - path to block device where BTRFS system reside.
     Block device is determined automatically, if your system
     has a single btrfs partition.
     If system havs multiple btrfs partitions, then this option
     should point to selected btrfs partition. Ex: /dev/sda2

-m | --mount-point - mount point for BTRFS root.
	 default: /mnt
     Path to mount root btrfs partition.


-s | --snapshot  - path to selected snapshot

-v | --subvolume - the name of subvolume as it is appears in top BTRFS partition.
     To find out the name - mount root BTRFS partition and ls its content.
     Any name can be replaced with any snapshot.
	 Be careful, don't replace root subvolume with home or log.
     Examples: ./restore.sh -v @
               ./restore.sh -v @home

-f | --keep-fstab - tells the script to copy current partition scheme
     to the restored snapshot. This is done by copying current /etc/fstab file (with replaced id)
     to the newly created (from snapshot) subvolume. It also back up old /etc/fstab that was in the
     snapshot. This option will work only if /etc/fstab is found in snapshot/etc/fstab.
     This option also means that replaced subvolume is root. It is thus recommended to
     reboot your system after the rollback.

     WARNING! IF you perform multiple rollbacks during the same session, make sure that
     root rollback is done last, otherwise fstab will contain wrong ids and the system will
     not start. It is possible to rollback @home and then @ in the same session.

-r | --reboot - automatically reboots the computer after successful rollback.

-h | --help  - prints this message
   

## What is actually happening
The rollback achieved by renaming current subvolume to <name>-abandoned-<timestamp> (or <name>-TOP-abandoned-<timestamp>), 
creating new read-write subvolume from chosen snapshot and placing it instead of abandoned one. 
The script also replaces id of abandoned subvolume in fstab and if it is root subvolume and flag -f is set then fstab is copied 
to the new subvolume, so all current partitions are mounted correctly next time you boot.
This approach has been tested with GRUB.

Old snapshots can be later deleted manually, unless root subvolume is actually a top level subvolume.
This is the case on the very first rollback. Do NOT delete abandoned  top level subvolume, otherwise all data from it will be lost!
Any consequent snapshots can be safely deleted (since they are just snapshots of the top level subvolume).

Usually it would be difficult to delete root subvolume, it will complain that the directory is not empty and refuse deletion.
To find out whether current subvolume is a top level subvolume run 

```
sudo btrfs subvolume show /path/to/mounted/root/subvolume | grep "Parent UUID"
```
If parent UUID is set, then it is a snapshot that can be safely deleted.
If parent UUID is "-" (hyphen, no quotes) then it is top level subvolume.


## Caution
The script doesn not check whether snapshot and subvolume are actually related, so 
if you ask script to replace root subvolume with snapshot of your home directory - it will do it!

## Recovery
If for any reason the system refused to mount subvolumes at boot, do following:
1. Enter your root password
2. Mount btrfs root subvolume somewhere, ex: `mount -t btrfs /dev/sda3 /mnt/btrfsroot`
3. cd into btrfs root
3. check ID of all failed-to-mount subvolumes by running `btrfs subvol show ./<subvolume_name>`
   This will list you list of attributes for given subvolume. Look for "Subvolume ID"
4. edit /etc/fstab such that every btrfs record there has ID obtained in previous step. 
5. Repeat steps 3 and 4 for each failed-to-mount subvolume. 
6. Reboot.
7. Open an issue on github.

## Known issues
If kernel versions are different across the snapshots - the system may not boot after the rollback.
This happens because pacman writes changes to EFI boot partition at /boot, and boot is not part of 
btrfs. Thus, after the rollback the system will be looking for upgraded kernel and won't find it.

To fix that - boot from arch bootable USB and reinstall the kernel package (linux or linux-lts or other), or rollback it to previous version.
see version of kernel and the version of kernel package:
uname -a
pacman -Q linux



   


