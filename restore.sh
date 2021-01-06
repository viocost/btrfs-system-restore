#!/bin/bash
#
VERSION="0.0.3"

ABANDONED_FILENAME=abandoned
ABANDONED_FILENAME_TOP=TOP_abandoned
BTRFS_ROOT_DIR=btrfsroot

HELP="

BTRFS rollback utility v$VERSION

DESCRIPTION:

This script will restore a snapshot taken by snapper by renaming current subvolume and replacing it with read-write copy of chosen snapshot.
The replaced subvolume copy will remain and have to be cleared manually later.

The script meant to be used for restoring system subvolume on all linux distributions that don't support Open SUSE style rollback.
After running the script you may continue working, however, you will boot into the reverted snapshot state after rebooting.


USAGE:

sudo ./restore.sh -c <snapper_config> -s <path_to_desired_snapshot> -v <subvolume_name> [OPTIONS]




OPTIONS:

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


CONFIG="root"
MOUNT="/mnt"

while true; do
       case "$1" in 
	       -s | --snapshot ) SNAPSHOT="$2"; shift 2;;
		   -v | --subvolume ) SUBVOLUME="$2"; shift 2;;
	       -c | --config) CONFIG="$2"; shift 2;;
		   -f | --keep-fstab) KEEP_FSTAB=true; shift 1;; # if fstab is found in root of the snapshot and replaces subvolume, it is backed up and replaced with current fstab
	       -m | --mount-point ) MOUNT="$2"; shift 2;; # optional
	       -d | --device ) DEV="$2"; shift 2;;        # optional
		   -r | --reboot) REBOOT=true; shift 1;;      # optional
	       -h | --help ) echo "$HELP"; exit 0;;
	       * ) break ;;
       esac
done       


if [[ $EUID -ne 0 ]]; then
	echo "Root privileges required. Exiting..."
	exit 1
fi

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

	TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%S")


	[[ $(get_parent_uuid ${2}) ]] && ABANDONED_PATH="${2}-${ABANDONED_FILENAME}-${TIMESTAMP}" \
	    ||  ABANDONED_PATH="${2}-${ABANDONED_FILENAME_TOP}-${TIMESTAMP}";

	mv ${2} $ABANDONED_PATH

	btrfs subvol snapshot $3 $2

	NEW_ID=$(get_subvolume_id $2)

	LINE=$(egrep -n subvolid=$OLD_ID /etc/fstab | awk -F: '{ print $1 }')
	#echo "New id: $NEW_ID line: $LINE"
	cp /etc/fstab /etc/fstab.bak-$(date -u +"%Y-%m-%dT%H-%M-%S")
	sed -r -i "s/(.*)(subvolid=$OLD_ID)(.*)/\1subvolid=${NEW_ID}\3/" /etc/fstab

	# If fstab is found in both subvolumes then
	# Copying current fstab to the new subvolume
	if [[ ! -z $KEEP_FSTAB ]]; then
		if [[ -f ${2}/etc/fstab && -f ${ABANDONED_PATH}/etc/fstab ]]; then

			echo Copying fstab

			# backing up fstab in new subvolume
			cp ${2}/etc/fstab ${2}/etc/fstab-bak-$TIMESTAMP

			# copying current fstab
			cp ${ABANDONED_PATH}/etc/fstab  ${2}/etc/fstab
		fi
	fi


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
