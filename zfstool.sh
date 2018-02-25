#!/bin/sh
set -e

toolname="${0##*/}" && toolname="${toolname%.sh}"
scriptrealpath="$(realpath "$0")"
scriptname="${scriptrealpath##*/}"
scriptrealdir="$(dirname "$scriptrealpath")"

scriptdir="${scriptrealdir}"

# Include utilities: 'basic', 'list', 'fkrt'
. "$scriptdir/utils/utils-basic.sh"
. "$scriptdir/utils/utils-info.sh"
. "$scriptdir/utils/utils-list.sh"
. "$scriptdir/utils/utils-file.sh"
. "$scriptdir/utils/utils-search.sh"
. "$scriptdir/utils/utils-fkrt.sh"
. "$scriptdir/utils/utils-plugin-loader.sh"

default_colors
info_prog_set "$scriptname"

###
### Begin code for zfstool
###


_co="$@" && for _i in $_co ; do case "$_i" in -q|--quiet) QUIET="yes" ; break ;; --) break ;; esac ; done

# load plugins from script dir and ~/.mkimage
info_prog_set "$scriptname:plugin-loader"
load_plugins "$scriptdir/filesystems/zfs" "tools"

info_prog_set "$scriptname"

zfstool "$@"

