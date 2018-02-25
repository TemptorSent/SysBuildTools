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
		list) shift; zfs_list_existing && return 0 ;;
		help) initfstool_usage && return 0 ;;
		--*) warning "Unhandled global option '$1'!" ; return 1 ;;
		*) warning "Unknown command '$1'!" ; return 1 ;;
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
	list	list existing ZFS datasets
	help	show this help

EOF
}

zfs_list_existing() {
	"$_zfstool_zfs" status
}
