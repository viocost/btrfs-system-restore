#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Root privileges required. Exiting..."
	exit 1
fi

FS=()
FS_RAW=$(df --output=source,fstype | grep btrfs | awk '{print $1}' | uniq)
for i in $FS_RAW; do
	FS+=( ${i} "btrfs" off)
done

dialog --title "Root partition" \
	--radiolist "Select BTRFS root partition" 0 0 0 \
	"${FS[@]}" 2>fs.tmp

PARTITION=$(cat fs.tmp)
rm fs.tmp
echo $PARTITION

declare MOUNT
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

cd $MOUNT

if [[ ! -d btrfsroot ]]; then
	mkdir btrfsroot
fi


mount -t btrfs -o subvolid=0 ${PARTITION} ./btrfsroot

cd ./btrfsroot

SUBVOL=$(ls)

dialog --title "Root subvolume" \
	--radiolist "Select root btrfs subvolume" 0 0 0 \
	"${SUBVOL[@]}" 2>subvol.tmp

SUBVOLROOT=$(cat subvol.tmp)
rm subvol.tmp

echo $SUBVOLROOT


cd ../
umount ./btrfsroot
