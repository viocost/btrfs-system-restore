# BTRFS root subvolume rollback utility.
This utility rolls back BTRFS root subvolume to previously created snapshot without booting from live usb and messing with GRUB.
It supports any subvolume naming scheme.

## Requirements
1. BTRFS file system.
2. Snapper installed and configured for root.
3. Dialog terminal utility.


## Usage
1. Run the script as root.
2. Select desired snapshot from the list.
3. Select subvolume to replace, in Ubuntu style it will be @
4. Reboot now or later to boot into chosen snapshot. 
   After running the script any changes to the system will remain in current state.
   
## What is actually happening
The rollback achieved by renaming current root subvolume to root-abandoned-<timestamp> (or root-TOP-abandoned-<timestamp>) 
and renaming chosen snapshot to root. This approach works with GRUB, so there is no need to 
mess with subvolume id or do any extra manipulations.

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





   


