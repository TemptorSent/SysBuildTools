#!/bin/sh

# apk add \
#	abuild apk-tools alpine-conf busybox fakeroot syslinux xorriso
#	(for efi:) mtools dosfstools grub-efi

# FIXME: clean workdir out of unneeded sections
# FIXME: --release: cp/mv images to REPODIR/$ARCH/releases/
# FIXME: --update-latest: rewrite latest-releases.yaml with this build

set -e


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
. "$scriptdir/utils/utils-apk.sh"

#_apk_init "/usr/bin/abuild-apk"
_apk_init

default_colors
info_prog_set "$scriptname"


checksum() {
	sha1sum | cut -f 1 -d ' '
}

###
### Begin code for mkimage proper
###

mkimage_usage() {
	cat <<EOF

$scriptname	[--tag RELEASE] [--outdir OUTDIR] [--workdir WORKDIR]
		[--arch ARCH] [--profile PROFILE] [--hostkeys] [--simulate]
		[--repository REPO] [--extra-repository REPO] [--yaml FILE]
$scriptname	--help

options:
--arch			Specify which architecture images to build
			(default: $default_arch)
--no-hostkeys		Don't copy system apk signing keys to created images
--outdir		Specify directory for the created images
--profile		Specify which profiles to build
--plugins		Specify a file or directory structure root from
                        which to load additional discovered plugins.
--repository-file	File to use for list of repositories
--repository		Package repository to use for the image create
--extra-repository	Add repository to search packages from
--apk-cache-dir		Sets cache directory for apks.
--simulate		Don't execute commands
--tag			Build images for tag RELEASE
--workdir		Specify temporary working directory (cache)
--yaml

known plugins     : $all_plugins
known archs       : $all_archs
known profiles    : $all_profiles
known kern-flavors: $all_kernel_flavors
known image types : $all_imagetypes
known features    : $all_features

EOF
}

_co="$@" && for _i in $_co ; do case "$_i" in --quiet) QUIET="yes" ; break ;; --) break ;; esac ; done

# load plugins from script dir and ~/.mkimage
info_prog_set "$scriptname:plugin-loader"
load_plugins "$scriptdir"
[ "$HOME" ] && [ -e "$HOME/.mkimage" ] && load_plugins "$HOME/.mkimage"

info_prog_set "$scriptname"

_hostkeys="${_hostkeys:-yes}"
_simulate="${_simulate:-}"
_checksum="${_checksum:-}"

default_arch="$(_apk --print-arch)"

# parse parameters
while [ $# -gt 0 ]; do
	opt="$1"
	shift
	case "$opt" in
	--repositories-file) _repos="${_repos+$_repos }--repositories-file $1" ; shift ;;
	--repository) _repos="${_repos+$_repos }--repository $1" ; shift ;;
	--extra-repository) _repos="${_repos+$_repos }--repository $1" ; shift ;;
	--apk-cache-dir) _apk_cache_dir="$1" shift ;;
	--workdir) WORKDIR="$1"; shift ;;
	--outdir) OUTDIR="$1"; shift ;;
	--tag) RELEASE="$1"; shift ;;
	--arch) req_arch="$1"; shift ;;
	--profile) req_profiles="$1"; shift ;;
	--plugin) load_plugins "$1"; shift ;;
	--no-hostkeys) _hostkeys="";;
	--simulate) _simulate="yes";;
	--checksum) _checksum="yes";;
	--yaml) _yaml="yes";;
	--quiet) : ;;
	--) break ;;
	--help) _show_usage="yes" ; break ;;
	-*) _show_usage="error" ; warning "Unrecognized option '$opt'" ; break ;;
	esac
done


# Global variable declarations
all_checksums="sha256 sha512"
build_date="$(date +%Y%m%d)"

# Location of yaml generator
mkimage_yaml="$(dirname $0)"/release/mkimage-yaml.sh

# If we're NOT running in the script directory, default to outputting in the curent directory.
# If we ARE running in our script directory, at least put output files somewhere sane, like ./out
OUTDIR="${OUTDIR:-$PWD}"

# Handle usage either from --help or unrecognized option.
if [ "$_show_usage" ] ; then 
	mkimage_usage
	[ "$_show_usage" = "error" ] && exit 1
	exit 0
fi

# Save ourselves from making a mess in our script's root directory.
mkdir_is_writable "$OUTDIR" && OUTDIR="$(realpath "$OUTDIR")" \
	&& ( [ "$OUTDIR" != "$scriptrealdir" ] || OUTDIR="${OUTDIR}/out" && mkdir_is_writable "$OUTDIR" ) \
	|| ! error "Can not write to output directory '$OUTDIR'." || exit 1

# Setup default workdir in /tmp using mktemp
if [ -z "$WORKDIR" ]; then
	WORKDIR="/tmp/$(mktemp -d -t mkimage.XXXXXX)"
	trap 'rm -rf $WORKDIR' INT
fi
WORKDIR="${WORKDIR%%/}"
mkdir_is_writable "$WORKDIR" && WORKDIR="$(realpath "$WORKDIR")" \
	|| ! error "Can not write to work directory '$WORKDIR'." || exit 1

# Release configuration
RELEASE="${RELEASE:-${build_date}}"

if [ -z "$RELEASE" ]; then
	if git describe --exact-match >/dev/null 2>&1; then
		RELEASE=$(git describe --always)
		RELEASE=${RELEASE#v}
	else
		RELEASE="${build_date}"
	fi
fi



# get abuild pubkey used to sign the apkindex
# we need inject this to the initramfs or we will not be able to use the
# boot repository
if [ -z "$_hostkeys" ]; then
	_pub=${PACKAGER_PRIVKEY:+${PACKAGER_PRIVKEY}.pub}
	_abuild_pubkey="${PACKAGER_PUBKEY:-$_pub}"
fi

# Create lists of candidate archs and profiles for building images.
req_arch=${req_arch:-${default_arch}}
[ "$req_arch" != "all" ] || req_arch="${all_archs}"
# FIXME: We probably DON'T want to build all profiles by default!
req_profiles=${req_profiles:-all}
[ "$req_profiles" != "all" ] || req_profiles="${all_profiles}"

# Build image for each requested arch/profile (profiles skip if invalid combo).
for ARCH in $req_arch; do
	info_prog_set "$scriptname:$ARCH"
	info_func_set "build arch"

	apkroot_init "$WORKDIR/.apkroot-$ARCH" "$ARCH" 
	apkroot_setup "${_hostkeys:+--host-keys}" "${_apk_cache_dir:+--cache--dir $_apk_cache_dir}" $_repos
	_apk update

	if [ "$_yaml" = "yes" ]; then
		info_func_set "build yaml"
		msg "Generating yaml release manifest..."
		_yaml_out="${OUTDIR:-.}"/latest-releases.yaml
		echo "---" > "$_yaml_out"
		msg2 "... '$_yaml_out' generated."
	fi
	for PROFILE in $req_profiles; do
		info_prog_set "$scriptname:$ARCH:$PROFILE"
		info_func_set "build profile"
		msg "Beginning build for profile '$PROFILE'..."
		(build_profile) || ! error "BUILD FAILED IN PROFILE '$PROFOLE' -- ABORTING!" || exit 1
		msg "...build for profile '$PROFILE' completed."
	done
done

info_prog_set "$scriptname"
info_func_set "DONE"

msg "Images generated in '$OUTDIR'."

