###
### APKROOTTOOL
###
### Build an apk root.

# Tool: apkroottool
# Commands: init setup

tool_apkroottool() { return 0 ; }
apkroottool() {
	fkrt_init
	: "${OPT_apkroot_setup_cmdline:=--repositories-file /etc/apk/repositories --host-keys --arch-keys}"
	case "$1" in
		help) apkroottool_usage ; return 0 ;;
		init)	shift
			mkdir_is_writable "$1" || ! warning "Could not create writable directory for apkroot at '$1'!" || return 1
			file_exists "$1/.fkrt-db" && fkrt_faked_db_load_file "rt" "$1/.fkrt-db"
			fkrt_faked_db_save_file "rt" "$1/.fkrt-db" && fkrt_enable "rt" || ! _ret=$? || ! fkrt_cleanup || ! warning "Could not start fkrt or create state file '$1/.fkrt-db'!" || return $_ret
			apkroot_init "$@" ; _ret=$?
			fkrt_cleanup
			[ $_ret -eq 0 ] || ! warning "Failed to init apkroot at '$1'!"
			return $_ret
			;;
		setup)
			shift
			mkdir_is_writable "$1" || ! warning "Could not create writable directory for apkroot at '$1'!" || return 1
			file_exists "$1/.fkrt-db" && fkrt_faked_db_load_file "rt" "$1/.fkrt-db"
			fkrt_faked_db_save_file "rt" "$1/.fkrt-db" && fkrt_enable "rt" || ! _ret=$? || ! fkrt_cleanup || ! warning "Could not start fkrt or open state file '$1/.fkrt-db'!" || return $_ret
			case "$2" in
				--*|-*|'') apkroot_init "$1" ; _ret=$? ; shift ;;
				*) apkroot_init "$1" "$2" ; _ret=$? ; shift 2 ;;
			esac
			if [ $_ret -ne 0 ] ; then warning "Failed to init apkroot at '$1'!"
			elif ! apkroot_setup $OPT_apkroot_setup_cmdline && _ret=$? ; then warning "Failed to setup apkroot at '$1'!" ; fi
			fkrt_cleanup
			return $_ret
			;;
		manifest|index-libs|index-bins|dep-libs|dep-bins|deps|subset-deps|subset|subset-cpio|subset-cpiogz)
			_cmd="$1" ; shift
			dir_exists "$1" || ! warning "No apkroot directory found at '$1'!"
			file_exists "$1/.fkrt-db" && fkrt_faked_db_load_file "rt" "$1/.fkrt-db" || warning "Could not read fkrt state fle '$1/.fkrt-db', Fakeroot owners/permission may not work!"
			fkrt_faked_db_save_file "rt" "$1/.fkrt-db" && fkrt_enable "rt" && apkroot_init "$1" || ! _ret=$? || ! fkrt_cleanup || ! warning "Failed to init apkroot at '$1'!" || return $_ret
			shift
			case "$_cmd" in
				manifest) apkroot_manifest_installed_packages ; _ret=$? ;;
				index-libs) apkroot_manifest_index_libs ; _ret=$? ;;
				index-bins) apkroot_manifest_index_bins ; _ret=$? ;;
				dep-libs) apkroot_manifest_dep_libs ; _ret=$? ;;
				dep-bins) apkroot_manifest_dep_bins ; _ret=$? ;;
				deps) apkroot_manifest_deps ; _ret=$? ;;
				subset-deps) apkroot_manifest_subset_deps "$@" ; _ret=$? ;;
				subset) apkroot_manifest_subset "$@" ; _ret=$? ;;
				subset-cpio) apkroot_manifest_subset_cpio "$@" ; _ret=$? ;;
				subset-cpiogz) apkroot_manifest_subset_cpiogz "$@" ; _ret=$? ;;
			esac
			fkrt_cleanup
			return $_ret
			;;
	esac
	dir_is_readable "$1" || ! warning "Can't read apkroot directory at '$1'!" || return 1
	dir_is_readable "$1/etc/apk/keys" || ! warning "'$1' does not appear to be the root of an apkroot directory!\n(Try '$0 init <apkrootroot> [<arch>]')" || return 1
	case "$2" in
		apk)
			file_exists "$1/.fkrt-db" && fkrt_faked_db_load_file "rt" "$1/.fkrt-db"
			fkrt_faked_db_save_file "rt" "$1/.fkrt-db" && fkrt_enable "rt" && apkroot_init "$1" && shift 2 && _apk ${VERBOSE:+-v} $@ ; _ret=$?
			fkrt_cleanup
			return $_ret
			;;
		*)
			file_exists "$1/.fkrt-db" && fkrt_faked_db_load_file "rt" "$1/.fkrt-db"
			fkrt_faked_db_save_file "rt" "$1/.fkrt-db" && fkrt_enable "rt" && apkroot_init "$1" && shift && (cd "$_apkroot" && "$@" ) ; _ret=$?
			fkrt_cleanup
			return $_ret
			;;

	esac
}

apkroottool_usage() {
	apkroottool_commands_usage
	multitool_usage
	apkroot_opts_usage
}

apkroottool_commands_usage() {
cat <<EOF
Usage: 	apkroottool <global options>
		( (<apkroot cmd> <apkroot> [<args>])	# Command Mode
		| (<apkroot> apk <apk cmd> [<args>])	# APK Mode
		| (<apkroot> <commd> [<args>]) )	# Wrapper Mode

Command Mode:
	init <apkroot> [<arch>]
		  Use existing apkroot or initilize a new apkroot directory
		  at <apkroot> (using arch <arch> if specified).

	setup <apkroot> [<arch>]
		Modify exising or setup new <apkroot> using the apkroot
		command-line options specified (see below).

	deps <apkroot>
		Builds all of the following stages for <apkroot>:

		manifest <apkroot> - Build manifest of installd files.
		index-libs <apkroot> - Build index of installed libs.
		index-bins <apkroot> - Build index of installed bins.
		dep-libs <apkroot> - Build dep list for installed libs.
		dep-bins <apkroot> - Build dep list for installed bins.
		(See output in <apkroot>/.*)

	subset-deps <apkroot> <globs>...
		Print list of bin and lib deps for given <globs> in <apkroot>.

	subset <apkroot> <globs>... (To be renamed subset-manifest)
		Print submainfest of all files matching <glibs> and their deps.

	subset-cpio <apkroot> <outfile|-> <globs>...
		Build cpio archive <outfile> ('-' for stdout) containing all
		files in <apkroot> Manifest matching <globs> and their deps.

	subset-cpiogz <apkroot> <outfile|-> <globs>...
		Same as with subset-cpio, piped through 'gzip -9'.


APK Mode:
	apkroottool <apkroot> apk <apk cmd> <apk args>
		Call _apk using specified <apkroot>, detect arch, and use fkrt.

Wrapper Mode:
	apkroottool <apkroot> <cmdline>
		Run subshell in <apkroot> and execute arbitrary command wrapped
		using fkrt, with state loaed from <apkroot>/.fkrt-db

EOF
}
