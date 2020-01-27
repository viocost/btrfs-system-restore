#!/bin/bash

HELP="Description:

This script will restore a snapshot taken by snapper by renaming current subvolume and replacing it with read-write copy of chosen snapshot.
The replaced subvolume copy will remain and have to be cleared manually later.

The script meant to be used for restoring system subvolume on all linux distributions that don't support Open SUSE style rollback.
Running this script will not require any changes to GRUB configuration, as the new snapshot will replace current root subvolume.

After running the script you may continue working, however, you will boot into the reverted snapshot state after rebooting.


USAGE:

sudo ./restore.sh [OPTIONS]


OPTIONS:

-c | --config - snapper config
                default: root

-d | --device - path to block device where BTRFS system reside.

-s | --snapshots-dir - path to snapper snapshot directory. Script assumes snapper directory structure
                       default: /.snapshots

-m | --mount-point - mount point for BTRFS root.
                     default: /mnt


"


if [[ $EUID -ne 0 ]]; then
	echo "Root privileges required. Exiting..."
	exit 1
fi

CONFIG="root"
SNAPSHOTSDIR="/.snapshots"
MOUNT="/mnt"

while true; do
       case "$1" in 
	       -s | --snapshots-dir ) SNAPSHOTSDIR="$2"; shift 2;;
	       -m | --mount-point ) MOUNT="$2"; shift 2;;
	       -d | --device ) DEV="$2"; shift 2;;
	       -h | --help ) echo $HELP; exit 0;;
	       * ) break ;;
       esac
done       

if ! dialog --version >/dev/null 2>/dev/null; then
	echo "Missing dialog package"
	exit 1
fi

if [[ -d "/mnt" ]]; then 
	MOUNT="/mnt"
elif [[ -d "/media" ]]; then
	MOUNT="/media"
else
	read -p "Enter path to mount point: " MOUNT
fi


if [[ ! -d $MOUNT ]]; then 
	echo "Invalid mount point. Exiting..."
	exit 1
fi


if [[ ! -d  $SNAPSHOTSDIR ]]; then 
	echo "Snapshots directory not found."
	exit 1
fi


if ! snapper -c "$CONFIG" list 2>/dev/null >/dev/null; then
	echo "Snapper configuration not found."
	exit 1
fi


dialog --title "Snapshot" \
	--radiolist "Select snapshot to restore" 0 0 0 \
	$(for line in $(sudo snapper --machine-readable csv -c "$CONFIG" list | awk -F, '{gsub(/\s/, "_", $8); gsub(/\s/, "_", $12); printf "%s %s_%s off\n", $3, $8, $12}' | tail -n +3); do
		echo $line
	done) >/dev/tty  2>sn.tmp

clear
read  CHOICE < sn.tmp
rm sn.tmp

SNAPSHOTPATH="$SNAPSHOTSDIR/$CHOICE/snapshot"

if [[ ! -d $SNAPSHOTPATH ]] ; then
	echo SNAPSHOT NOT FOUND!
	exit 1
fi

FS=()
FS_RAW=$(df --output=source,fstype | grep btrfs | awk '{print $1}' | uniq)
for i in $FS_RAW; do
	FS+=( ${i} "btrfs" off)
done

if [[  -z $DEV ]]; then
	dialog --title "Root partition" \
		--radiolist "Select BTRFS root partition" 0 0 0 \
		"${FS[@]}" 2>fs.tmp

	DEV=$(cat fs.tmp)
	rm fs.tmp
elif [[ ! -b $DEV ]]; then
	echo BTRFS partition not found
	exit 1
fi



cd $MOUNT

if [[ ! -d btrfsroot ]]; then
	mkdir btrfsroot
fi

echo "MOUNTING BTRFS ROOT"
mount -t btrfs -o subvolid=0 ${PARTITION} ./btrfsroot
echo "DONE"

cd ./btrfsroot
ls

ENTRIES=()

for i in $(ls); do
	ENTRIES+=(${i} "btrfs" off)
done

echo $ENTRIES

dialog --title "Root subvolume" \
	--radiolist "Select current subvolume that will be replaced by the snapshot" 0 0 0 \
	"${ENTRIES[@]}" 2>subvol.tmp

SUBVOLROOT=$(cat subvol.tmp)

rm subvol.tmp


if dialog --title "Confirmation" \
	--yesno "Subvolume $SUBVOLROOT will now be renamed to ${SUBVOLROOT}-old and replaced with snapshot ${SHOICE}. \
	if ${SUBVOLROOT}-old already exists, IT WILL BE DELETED!
	\n\nProceed?" 0 0; then
	if [[ -d ${SUBVOLROOT}-old ]]; then
		if ! btrfs subvol delete ${SUBVOL}-old; then
			echo "Error deleting previous old partition"
			exit 1
		fi
	fi

	snapper create -c $CONFIG -d "Before rollback"

	mv ${SUBVOLROOT} ${SUBVOLROOT}-old
	btrfs subvol snapshot $SNAPSHOTPATH $SUBVOLROOT

	if dialog --title "Finish" \
		--yesno "Rollback completed. Reboot now?" 0 0; then
		REBOOT="yes"
	fi

fi



cd ../
umount ./btrfsroot

if [[ ! -z REBOOT ]]; then
	reboot
fi

