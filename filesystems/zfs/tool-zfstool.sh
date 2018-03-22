####
###  ZFSTOOL
###
###  ZFS pool and dataset setup and maniputation tool.
####

# Tool: zfstool
# Commands: help 

# Usage: tool_zfstool
tool_zfstool() {
	: "${_zfstool_zpool:=$(command -v zpool)}"
	: "${_zfstool_zfs:=$(command -v zfs)}"
	if [ -z "$_zfstool_zpool" ] || [ -z "$_zfstool_zfs" ] || [ "${_zfstool_zpool%/zpool}" != "${_zfstool_zfs%/zfs}" ] ; then
		if [ -x /sbin/zpool ] && [ -x /sbin/zfs ] ; then
			_zfstool_zpool=/sbin/zpool
			_zfstool_zfs=/sbin/zfs
		elif [ -x /usr/sbin/zpool ] && [ -x /usr/sbin/zfs ] ; then
			_zfstool_zpool=/usr/sbin/zpool
			_zfstool_zfs=/usr/sbin/zfs
		else
			warning "Could not find 'zpool' and 'zfs' tools!"
			return 1
		fi
	fi

	return 0
}

# Usage: zfstool <cmd>
zfstool() {
	info_prog_set "zfstool"

	local command
	command="$1"

	case "$1" in
		be) shift; zfstool_be $@ ; return $? ;;
		status) shift; zfstool_zpool_status ; return $? ;;
		list) shift; zfstool_zfs_list ; return $? ;;
		_parse) shift; _zfstool_parse_zfstab ; return $? ;;
		_gen) shift; _zfstool_gen_zfstab ; return $? ;;
		_order) shift; _zfstool_order_zfstab ; return $? ;;
		_findroots) shift; _zfstool_findroots_zfstab ; return $? ;;
		help) zfstool_usage && return 0 ;;
		--*) warning "Unhandled global option '$1'!" ; zfstool_usage ; return 1 ;;
		*) warning "Unknown command '$1'!" ; zfstool_usage ; return 1 ;;
	esac
	return 1
}

# Usage: zfstool be <cmd>
zfstool_be() {
	info_prog_set "zfstool be"

	local command
	command="$1"

	case "$1" in
		get) shift; zfstool_be_get $@ ; return $? ;;
		list) shift; zfstool_be_list $1 ; return $? ;;
		help) zfstool_be_usage && return 0 ;;
		--*) warning "Unhandled global option '$1'!" ; zfstool_be_usage ; return 1 ;;
		*) warning "Unknown command 'be $1'!" ; zfstool_be_usage ; return 1 ;;
	esac
	return 1
}

# Usage: zfstool be get <cmd>
zfstool_be_get() {
	info_prog_set "zfstool be get"

	local command
	command="$1"
	case "$1" in
		active) shift; zfstool_be_get_active $1 ; return $? ;;
		help) zfstool_be_usage && return 0 ;;
		--*) warning "Unhandled global option '$1'!" ; zfstool_be_usage ; return 1 ;;
		*) warning "Unknown command 'be $1'!" ; zfstool_be_usage ; return 1 ;;
	esac
	return 1
}


# Print usage for "zfstool"
# Usage: zfstool_usage
zfstool_usage() {
	zfstool_commands_usage
}

# Print usage for "zfstool be"
# Usage: zfstool_be_usage
zfstool_be_usage() {
	zfstool_commands_usage
}

# Usage: zfstool_commands_usage
zfstool_commands_usage() {
cat <<EOF
Usage: zfstool <global opts> <command> <command opts>

Commands:
	status	get pool status
	list	list existing ZFS datasets
	help	show this help

EOF
}

zfstool_zfs_list() {
	"$_zfstool_zfs" list
}

zfstool_zpool_status() {
	"$_zfstool_zpool" status
}


##
#
# pool definitions
#
##

## Get the guid for the specified pool
_zfstool_zpool_get_guid() {
	test -z "$1" && return 1
	"$_zfstool_zpool" get guid -H -o value $1 2> /dev/null
}

## Check that the named pool exists
_zfstool_pool_exists() {
	"$_zfstool_zpool" get guid $1 > /dev/null
}

##
#
# filesystem definitions
#
##

### 'zfstab' format:
####	filesystem	name	canmount	mountpoint	flags	options
####	volume	name	volsize	volblocksize	flags:sparse?	options


_zfstool_parse_zfstab() {
	awk '
		BEGIN { FS="\t" ; split("", datasets) }
		/^filesystem/	{ ds=$2; datasets[ds]=ds ; type[ds]=$1 ; filesystems[ds]=ds ; canmount[ds]=$3 ; mountpoint[ds]=$4 ; options[ds]=$5 }
		/^volume/	{ ds=$2; datasetsp[ds]=ds ; type[ds]=$1 ; volumes[ds]=ds ; volsize[ds]=$3 ; volblocksize[ds]=$4 ; sparse[ds]=$5 ; options[ds]=$6 }
		END {
			for ( fs in filesystems ) {
				opts=options[fs]
				if (canmount[fs] != "" && canmount[fs] != "inherit" && canmount[fs] != "default" ) { opts="canmount=" canmount[fs] " " opts }
				if (mountpoint[fs] != "" && mountpoint[fs] != "inherit") { opts="mountpoint=\"" mountpoint[fs] "\" " opts }
				gsub(/[[:alnum:]]+=/, "-o &", opts)
				printf("zfs create %s\"%s\"\n", opts, fs)

			}
			for ( vol in volumes ) {
				opts=options[vol]
				gsub(/[[:alnum:]]+=/, "-o &", opts)
				if ( sparse[vol]=="sparse" ) { sparseflag="-s " } else { sparseflag="" }
				printf("zfs create %s%s-b %s -V %s \"%s\"\n", sparseflag, opts, volblocksize[vol], volsize[vol], vol)
			}
		}
	'
}

### 'zfs get -H -o' format:
####	dataset	option	value	source
_zfstool_gen_zfstab() {
	"$_zfstool_zfs" list -H -p -o type,name | awk '
		BEGIN { OFS="\t" ; split("", datasets) }

		{
			t=$1 ; ds=$2 ;
			datasets[ds]=ds ; type[ds]=t ; name[ds]=ds
			if ( t == "filesystem" ) {
					cmd="( '"$_zfstool_zfs"' get mountpoint -H -p -s local -t filesystem " ds " | cut -f3 )"
					cmd | getline mountpoint[ds]
					close(cmd)
					cmd="( '"$_zfstool_zfs"' get canmount -H -p -t filesystem " ds " | cut -f4 )"
					cmd | getline canmountsrc[ds]
					close(cmd)
					if ( canmountsrc[ds] == "local" ) {
						cmd="( '"$_zfstool_zfs"' get canmount -H -p -s local -t filesystem " ds " | cut -f3 )"
						cmd | getline canmount[ds]
						close(cmd)
					} else if ( canmountsrc[ds] == "inherited" ) {
						canmount[ds]="inherit"
					} else { canmount[ds]="default" }

					cmd="( '"$_zfstool_zfs"' get all -H -p -s local -t filesystem " ds " | cut -f2,3 --output-delimiter=\"=\" | grep -v -e \"mountpoint=\" -e \"canmount=\" | tr \"\n\" \" \")"
					cmd | getline options[ds]
					close(cmd)

			} else if ( t == "volume" ) {
					cmd="( '"$_zfstool_zfs"' get volsize -H -p -s local -t volume " ds " | cut -f3 )"
					cmd | getline volsize[ds]
					close(cmd)
					cmd="( '"$_zfstool_zfs"' get volblocksize -H -t volume " ds " | cut -f3 )"
					cmd | getline volblocksize[ds]
					close(cmd)
					cmd="( '"$_zfstool_zfs"' get refreservation -H -p -s local -t volume " ds " | cut -f3 )"
					cmd | getline refreservation[ds]
					close(cmd)
					if ( refreservation[ds] != "" && refreservation[ds] < volsize[ds] ) { sparse[ds]="sparse" }
					cmd="( '"$_zfstool_zfs"' get all -H -p -s local -t volume " ds " | cut -f2,3 --output-delimiter=\"=\" | grep -v -e \"volsize=\" | tr \"\n\" \" \")"
					cmd | getline options[ds]
					close(cmd)
			}
		}

		END {
			for ( ds in datasets ) {
				if ( type[ds] == "filesystem" ) {
					print type[ds] "\t" name[ds] "\t" canmount[ds] "\t" mountpoint[ds] "\t" options[ds]
				} else if ( type[ds] == "volume" ) {
					print type[ds] "\t" name[ds] "\t" volsize[ds] "\t" volblocksize[ds] "\t" sparse[ds] "\t" options[ds]
				}
			}
		}
	'
}

## Create list of potential root filesystems from a 'zfstab'
#
_zfstool_findroots_zfstab() {

	awk 'BEGIN {
			FS="\t"
			split("",datasets)
			split("",mounts)
		}

		( $1 ~ /filesystem/ ) && ! ( $3 ~ /off/ ) && ( $4 == "/" ) {
			mounts[$2]=$0
		}

		END {
			for (m in mounts) {
				print m
			}
		}

	'
}

## Sort a list of filesystems in 'zfstab' format into mount order
#
_zfstool_order_zfstab() {
	# type	name	canmount	mountpoint	options

	awk 'BEGIN {
			FS="\t"
			split("",datasets)
			split("",mounts)
		}

		( $1 ~ /filesystem/ ) {
			ds=$2; mp=$4
			mounts[ds]=mp
		}

		END {
			for (m in mounts) {
				if ( mounts[m] == "/" ) {
					d=1
				} else {
					d=split(mounts[m], sm, "/")
				}
				mp_depth[m]=d
			}
			for (m in mounts) {
				dsd=split(m,dsm,"/")
				if ( mounts[m] == "" ) {
					found=0
					smp=""
					mm=m
					for (n=dsd ; found < 1 && n > 0 ; n-- ) {
						smp="/" dsm[n] smp
						pat="/" dsm[n] "$"
						sub(pat,"",mm)
						if ( mp_depth[mm] > 0 ) {
							if ( mp_depth[mm] == 1 ) {
								mounts[m]=smp
							} else {
								mounts[m]=mounts[mm] smp
							}
							mp_depth[m]=mp_depth[mm]+dsd-n
							found=1
						}
					}
				}
				print mp_depth[m] "\t" dsd "\t" mounts[m] "\t" m
			}
		}

	' | sort -t"$(printf '\t')" -k1,1n -k2,2

	# Create list of all potential root filesystems:
	# Find filesystem specified by pool bootfs property
	# Find filesystems with canmount=noauto and mountpoint=/
	# Find filesystem with canmount=on and mountpoint=/
	# ..if it exist, find filesystems with mountpoint=none and canmount!=off that look like they are BE roots.

	# Determine root pool(s) for all filesystem on the candidate list and add them to the list in the order of the root filesystems.

	# From each root filesystem, walk the tree backwards to its top pool, prepending each filesystem having canmount!=on to the list.

	# For each level of path below /, 

	# Handle all canmount=off paths up to, but not including, the first mountable dataset.

	return
}

##
#
# volume definitions
#
##




##
#
# boot environments (BEs)
#
##

# List boot environments.

zfstool_be_list() {
	local be_root_path be_root_blank be_active
	be_root_path="${1:-${POOL:-rpool}/${BEROOT:-ROOT}}"
	be_active="$(zfstool_be_get_active)"
	"${_zfstool_zfs}" list -s creation -H -o name,mountpoint,used,creation -r ${be_root_path} | sed -e 's|\t|\t-\t| ; \|'${be_active}'| s|\t\t|\tActive\t|'
}

_zfstool_be_list() {
	local be_root_path be_root_blank be_active
	be_root_path="${1:-${POOL:-rpool}/${BEROOT:-ROOT}}"
	be_root_blank="$(printf -- "${be_root_path}" | tr '[:graph:]' ' ')"
	be_active="$(zfstool_be_get_active)"
	be_active="${be_active#${be_root_path}/}"
	"${_zfstool_zfs}" list -s creation -o name,mountpoint,used,creation -r "$be_root_path" | sed -re '1 s|'"$be_root_blank"'MOUNTPOINT|FLAGS  MOUNTPOINT| ; \|^('"${be_root_path}"')/[^/[:space:]]+/|d ; \|'"${be_root_path}"'[[:space:]]|d ; s|^'"${be_root_path}"'/([^[:space:]]+)([[:space:]]+)|\1\2  ---   |g ; s|('"${be_active}"'[[:space:]]+)---   |\1-*-   |'
}
# Create a boot environment.
zfstool_be_create() {
:
}

# Activate a boot environment.
zfstool_be_activate() {
	# Check bootfs and pool for existence
	"${_zfstool_zpool}" set bootfs="${2}" "${1:-rpool}"
}

zfstool_be_get_active() {
	# check pool for existence
	"${_zfstool_zpool}" get bootfs -H -o value "${1:-rpool}"
}

# Destroy a boot environment or snapshot.
zfstool_be_destroy() {
:
}

# Rename a boot environment.
zfstool_be_rename() {
:
}


#
# BE chroot utils
#

# Mount a boot environment to a temporary mountpoint.
zfstool_be_mount() {
:
}

# Bind mount other filesystems under our BE's temporary mountpoint.
zfstool_be_bind() {
	zfstool_be_mount
}

# Execute chroot to our BE's temporary mountpoint.
zfstool_be_chroot() {
	zfstool_be_bind

}

# Unbind other filesystems below our BE's temporary mountpoint.
zfstool_be_unbind() {
:
}

# Unmount our boot environment from the temporary mountpoint.
zfstool_be_unmount() {
	zfstool_be_unbind
}

