#!/bin/bash

ABANDONED_FILENAME=abandoned
ABANDONED_FILENAME_TOP=TOP_abandoned
BTRFS_ROOT_DIR=btrfsroot

HELP="

DESCRIPTION:

This script will restore a snapshot taken by snapper by renaming current subvolume and replacing it with read-write copy of chosen snapshot.
The replaced subvolume copy will remain and have to be cleared manually later.

The script meant to be used for restoring system subvolume on all linux distributions that don't support Open SUSE style rollback.
-r | --reboot) REBOOT=true; shoft 1;;
Running this script will not require any changes to GRUB configuration, as the new snapshot will replace current root subvolume.

After running the script you may continue working, however, you will boot into the reverted snapshot state after rebooting.


USAGE:

sudo ./restore.sh [OPTIONS]


OPTIONS:

-c | --config - snapper config
                default: root

-d | --device - path to block device where BTRFS system reside.

-m | --mount-point - mount point for BTRFS root.
                     default: /mnt


"

function echoerr() {
	echo "$@" 1>&2;
}

function get_parent_uuid(){
	echo $(btrfs subvolume show $1 | grep "Parent UUID:" | awk -F: '{ print $2 }' | sed -r 's/\s*//g; s/-//g')
}

function get_subvolume_id(){
	echo $(btrfs subvolume show $1 | grep "Subvolume ID:" | awk -F: '{ print $2 }' | sed -r 's/\s*//g; s/-//g')
}

if [[ $EUID -ne 0 ]]; then
	echo "Root privileges required. Exiting..."
	exit 1
fi

CONFIG="root"
cp /etc/fstab /etc/fstab.bak-nal
MOUNT="/mnt"

while true; do
       case "$1" in 
	       -s | --snapshot ) SNAPSHOT="$2"; shift 2;;
		   -v | --subvolume ) SUBVOLUME="$2"; shift 2;;
	       -c | --config) CONFIG="$2"; shift 2;;
	       -m | --mount-point ) MOUNT="$2"; shift 2;; # optional
	       -d | --device ) DEV="$2"; shift 2;;        # optional
		   -r | --reboot) REBOOT=true; shoft 1;;      # optional
	       -h | --help ) echo "$HELP"; exit 0;;
	       * ) break ;;
       esac
done       

function check_snapper_configuration(){
	if ! snapper -c "$1" list 2>/dev/null >/dev/null; then
		echo "Snapper configuration not found."
		exit 1
	fi
}

function mount_btrfs(){
	# $1 mount point
	# $2 block device

	if [[ ! -d $1/$BTRFS_ROOT_DIR ]]; then
		mkdir $1/$BTRFS_ROOT_DIR
	fi

	mount -t btrfs -o subvolid=5 $2 $1/$BTRFS_ROOT_DIR

	echo BTRFS mounted
}


function perform_rollback(){
	#$1 snapper config
	#$2 subvolume root (one that being abandoned)
	#$3 snapshot path

	#echo "Config: $1, subvolume: $2, Snapshot: $3"

    snapper -c $1 create  -d "Before rollback"

	OLD_ID=$(get_subvolume_id $2)

	#echo "OLD ID: $OLD_ID"

	# Checking whether it is top level subvolume or snapshot
	if [[ $(get_parent_uuid ${2}) ]]; then
		# This is a snapshot. Marking it as orphaned with date.
		# It can be later deleted
		mv ${2} ${2}-$ABANDONED_FILENAME-$(date -u +"%Y-%m-%dT%H-%M-%S")
		#echo non top
	else
		# No parent uuid, thus it is the actual subvolume and cannot be deleted later.
		mv ${2} ${2}-$ABANDONED_FILENAME_TOP-$(date -u +"%Y-%m-%dT%H-%M-%S")
		#echo top
	fi

	btrfs subvol snapshot $3 $2

	NEW_ID=$(get_subvolume_id $2)

	LINE=$(egrep -n subvolid=$OLD_ID /etc/fstab | awk -F: '{ print $1 }')
	#echo "New id: $NEW_ID line: $LINE"
	cp /etc/fstab /etc/fstab.bak-$(date -u +"%Y-%m-%dT%H-%M-%S")
	sed -r -i "${LINE}s/(.*)(subvolid=[0-9]*)(.*)/\1subvolid=${NEW_ID}\3/" /etc/fstab

}


function get_mount(){

	[[ -d "/media" ]] &&
		echo "/media"

	[[ -d "/mnt" ]] &&
		echo "/mnt"
}

# fuckit
if [[ -z $MOUNT ]]; then
	MOUNT=$(get_mount)
	if [[ -z $MOUNT ]]; then
		echoerr "could not set block device automatically"
		exit 1
	fi
fi

if [[ ! -d $MOUNT ]]; then
	echo "Invalid mount point. Exiting..."
	exit 1
fi

BTRFS_ROOT=$MOUNT/$BTRFS_ROOT_DIR

function get_block_device(){
	FS=()
	for i in $(df --output=source,fstype | grep btrfs | awk '{print $1}' | uniq); do
		FS+=(${i})
	done

	if [[ ${#FS[@]} == 1 ]]; then
		echo "$FS"
	fi
}

# Unmounts btrfs root partition
function cleanup(){
	umount $1
}

# If no block device specified -
# trying to set it automatically. If there is just one partition with BTRFS - then it will succeed, otherwise - die.
if [[ -z $DEV ]]; then
DEV=$(get_block_device)
	if [[  -z $DEV ]]; then
		echoerr "Could not set block device automatically. Exiting... $DEV"
		exit 1
	fi
fi



##MAIN STEPS:
check_snapper_configuration $CONFIG

mount_btrfs $MOUNT $DEV

if [[ ! -d $BTRFS_ROOT/$SUBVOLUME ]]; then
	echoerr "No subvolume $SUBVOLUME found."
	echoerr "$(ls $BTRFS_ROOT)"
	cleanup $BTRFS_ROOT
	exit 1
else
	echo subvolume found. Proceeding...
fi

function is_same_ancestor(){
	# $1 - subvol, can be top level (id 5)
	# $2 - snapshot

	SUBVOL1_PARENT_ID=$(btrfs subvol show $1 2>/dev/null | grep "Parent ID:" | awk -F: '{ print $2 }' | sed 's/\s//g')
	SUBVOL2_PARENT_ID=$(btrfs subvol show $2 2>/dev/null | grep "Parent ID:" | awk -F: '{ print $2 }' | sed 's/\s//g')

	SUBVOL1_PARENT_UUID=$(btrfs subvol show $1 2>/dev/null | grep "Parent UUID:" | awk -F: '{ print $2 }' | sed 's/\s*//g')
	SUBVOL2_PARENT_UUID=$(btrfs subvol show $2 2>/dev/null | grep "Parent UUID:" | awk -F: '{ print $2 }' | sed 's/\s*//g')

	SUBVOL1_UUID=$(btrfs subvol show $1 2>/dev/null | egrep "^\s*UUID:" | awk -F: '{ print $2 }' | sed 's/\s//g')
	SUBVOL2_UUID=$(btrfs subvol show $2 2>/dev/null | egrep "^\s*UUID:" | awk -F: '{ print $2 }' | sed 's/\s//g')

	# echo "PARENT UUID: DEBUG $1: $SUBVOL1_PARENT_UUID  $2: $SUBVOL2_PARENT_UUID "
	# echo "SELF UUID:  DEBUG $1: $SUBVOL1_UUID  $2: $SUBVOL2_UUID "
	if [[ "$SUBVOL1_PARENT_UUID" == "$SUBVOL2_PARENT_UUID" ]]; then
		echo yes
	elif [[ "$SUBVOL1_PARENT_ID" == 5 && "$SUBVOL2_PARENT_UUID" == "$SUBVOL1_UUID" ]]; then
		echo yes
	fi
}

echo "$BTRFS_ROOT/$SUBVOLUME $SNAPSHOT"


echo Doing rollback
perform_rollback $CONFIG $BTRFS_ROOT/$SUBVOLUME $SNAPSHOT




#if [[ ! -z $REBOOT ]]; then
#	reboot
#fi
