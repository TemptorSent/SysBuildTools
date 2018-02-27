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
	if [ -z "$_zfstool_zpool" ] || [ -z "$_zfstool_zfs" ] || [ "${_zfstool_zpool%/zpool}" != "${_zfstool_zfs%/zfs}"; then
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

# Usage: zfstool
zfstool() {
	info_prog_set "zfstool"

	local command
	command="$1"

	case "$1" in
		status) shift; zfstool_zpool_status && return 0 ;;
		list) shift; zfstool_zfs_list && return 0 ;;
		_parse) shift; _zfstool_parse_zfstab && return 0 ;;
		_gen) shift; _zfstool_gen_zfstab && return 0 ;;
		help) zfstool_usage && return 0 ;;
		--*) warning "Unhandled global option '$1'!" ; zfstool_usage ; return 1 ;;
		*) warning "Unknown command '$1'!" ; zfstool_usage ; return 1 ;;
	esac
	return 1
}



# Print usage
# Usage: zfstool_usage
zfstool_usage() {
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

### Format:
#	filesystem	canmount	name	mountpoint	options
#	volume	size	name	sparse-vol	options
_zfstool_parse_zfstab() {
	#"$_zfstool_zfs" list -H -p -o type,canmount,name,mountpoint | awk '
	awk '
		BEGIN { FS="\t" ; split("", datasets) }
		/^filesystem/	{ datasets[$3]=$3 ; type[$3]=$1 ; canmount[$3]=$2 ; filesystems[$3]=$3 ; mountpoint[$3]=$4 ; options[$3]=$5 }
		/^volume/	{ datasetsp[$3]=$3 ; type[$3]=$1 ; size[$3]=$2 ; volumes[$3]=$3 ; sparse[$3]=$4 ; options[$3]=$5 }
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
				printf("zfs create %s%s-V %s \"%s\"\n", sparseflag, opts, size[vol], vol)
			}
		}
	'
}

### Format:
#	dataset	option	value	source
_zfstool_gen_zfstab() {
	"$_zfstool_zfs" list -H -p -o type,name | awk '
		BEGIN { OFS="\t" ; split("", datasets) }

		{
			datasets[$2]=$2 ; type[$2]=$1 ; name[$2]=$2
			if ( $1 == "filesystem" ) {
					cmd="( '"$_zfstool_zfs"' get mountpoint -H -p -s local -t filesystem " $2 " | cut -f3 )"
					cmd | getline mountpoint[$2]
					close(cmd)
					cmd="( '"$_zfstool_zfs"' get canmount -H -p -t filesystem " $2 " | cut -f4 )"
					cmd | getline canmountsrc[$2]
					close(cmd)
					if ( canmountsrc[$2] == "local" ) {
						cmd="( '"$_zfstool_zfs"' get canmount -H -p -s local -t filesystem " $2 " | cut -f3 )"
						cmd | getline canmount[$2]
						close(cmd)
					} else if ( canmountsrc[$2] == "inherited" ) {
						canmount[$2]="inherit"
					} else { canmount[$2]="default" }

					cmd="( '"$_zfstool_zfs"' get all -H -p -s local -t filesystem " $2 " | cut -f2,3 --output-delimiter=\"=\" | grep -v -e \"mountpoint=\" -e \"canmount=\" | tr \"\n\" \" \")"
					cmd | getline options[$2]
					close(cmd)

			} else if ( $1 == "volume" ) {
					cmd="( '"$_zfstool_zfs"' get volsize -H -p -s local -t volume " $2 " | cut -f3 )"
					cmd | getline volsize[$2]
					close(cmd)
					cmd="( '"$_zfstool_zfs"' get refreservation -H -p -s local -t volume " $2 " | cut -f3 )"
					cmd | getline refreservation[$2]
					close(cmd)
					if ( refreservation[$2] < volsize[$2] ) { sparse[$2]="sparse" }
					cmd="( '"$_zfstool_zfs"' get all -H -p -s local -t volume " $2 " | cut -f2,3 --output-delimiter=\"=\" | grep -v \"volsize=\" | tr \"\n\" \" \")"
					cmd | getline options[$2]
					close(cmd)
			}

		}
		END {
			for ( ds in datasets ) {
				if ( type[ds] == "filesystem" ) {
					print type[ds] "\t" canmount[ds] "\t" name[ds] "\t" mountpoint[ds] "\t" options[ds]
				} else if ( type[ds] == "volume" ) {
					print type[ds] "\t" volsize[ds] "\t" name[ds] "\t" sparse[ds] "\t" options[ds]
				}
			}
		}
	'
}

