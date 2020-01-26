#!/bin/bash

SAVEIFS=$IFS
IFS=$'\n'
SNAPSHOTS=$(sudo snapper --machine-readable csv -c root list | awk -F, '{printf "%s %s %s\n", $3, $8, $12}')
for i in $SNAPSHOTS; do
	echo ${i}
done

IFS=$SAVEIFS
exit 0

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
	--radiolist "Select root btrfs subvolume" 0 0 0 \
	"${ENTRIES[@]}" 2>subvol.tmp

SUBVOLROOT=$(cat subvol.tmp)

rm subvol.tmp

echo $SUBVOLROOT


cd ../
umount ./btrfsroot

