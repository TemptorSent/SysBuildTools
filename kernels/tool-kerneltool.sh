###
### KERNELTOOL
###
### Kernel components build and staging tool.

# Tool: kerneltool
# Commands: stage depmod

tool_kerneltool() { return 0 ; }
kerneltool() {
	info_prog_set "kerneltool"
	#: --staging-dir
	#: --arch
	#: --kernel-release <krel|apk|build-dir|install-dir|latest>
	#: stage [arch|arch/krel] <apk|build-dir|package-name)>  (i.e. /usr/src/linux or linux-firmware)
	#: depmod <basdir> <kernel release>
	#: subset_modules
	#: install
	#: package


	local command
	command="$1"

	case "$1" in
		stage) shift ; unset UNSTAGE RESTAGE ; kerneltool_stage "${STAGING_ROOT}" ${OPT_arch:+"$OPT_arch"} "$@" ; return $? ;;
		restage) shift ; unset UNSTAGE ; RESTAGE="yes" ; kerneltool_stage "${STAGING_ROOT}" ${OPT_arch:+"$OPT_arch"} "$@" ; return $? ;;
		unstage) shift ; unset RESTAGE ; UNSTAGE="yes" ; kerneltool_stage "${STAGING_ROOT}" ${OPT_arch:+"$OPT_arch"} "$@" ; return $? ;;
		depmod) shift ; kerneltool_depmod "${STAGING_ROOT}/${OPT_arch:-"$(_apk --print-arch)"}/merged-$1" "$1" ; return $? ;;
		mkmodsubset) shift ; kerneltool_mkmodsubset "${STAGING_ROOT}" "${OPT_arch:-"$(_apk --print-arch)"}" "$@" ; return $? ;;
		mkmodcpio) shift ; kerneltool_mkmodcpio "${STAGING_ROOT}" "${OPT_arch:-"$(_apk --print-arch)"}" "$@" ; return $? ;;
		mkmodloop) shift ; kerneltool_mkmodloop "${STAGING_ROOT}" "${OPT_arch:-"$(_apk --print-arch)"}" "$@" ; return $? ;;
		help) kerneltool_usage && return 0 ;;
		--*) warning "Unhandled global option '$1'!" ; return 1 ;;
		*) warning "Unknown command '$1'!" ; return 1 ;;
	esac
	return 1
}


kerneltool_usage() {

cat <<EOF
Usage: kerneltool <global opts> <command> <command opts>

Commands:
	stage <kernel spec> [<additional apk-file/kbuild-dir/apk-atom>...]
		Stage kernel components and build manifests for use by other kernel tools.
		The <kernel spec> may be: an apk file, kernel build directory, apk package atom;
		or, an already staged kernel release or <arch>/<kernel release> pair; or, the
		symbolic names 'current', 'latest' or 'latest-<flavor>'.

	restage <kernel spec> [<additional apk-files/kbuild-dirs/apk-atoms>...]
		Wipe staging directory and restage from scratch.

	unstage <kernel spec>
		Wipe staging directory for specified kernel spec.


	depmod <kernel release>
		Run depmod against the staging directory for specified kernel release.


	mkmodsubset <kernel release> <modsubset name> [<module names/globs>...]
		Build a subset of modules for the given release containing the specified
		modules and all their deps, including firmware.

	mkmodcpio <kernel release> [modsubset=<modsubset name>] [<module names/globs>...]
		Build a compressed cpio archive containg the specified subset of modules.
		An existing named subset may be used or a new one created using modsubset=<name>,
		otherwise a temporary subset will be created, used, and purged.

	mkmodloop <kernel release> [modsubset=<modsubset name>] [<module names/globs>...]
		Build a compressed squashfs filesystem for use as a modloop containing either
		the specified modules and their deps or all staged modules with needed firmware.
		Usage is the same as mkmodcpio.


EOF
	multitool_usage
	apkroottool_usage
}

###
## Kerneltool Commands
###


# Command: stage
# Usage: kerneltool_stage <staging basedir> [<arch>] <kernel (apk | build dir | package name | version) > [ other (build dirs | package names) ...]
kerneltool_stage() {
	info_prog_set "kerneltool-stage"
	info_func_set "stage"
	local stage_base="$1" ; shift
	local _arch _karch _krel k_pkg k_pkgname k_pkgver
	local _arch_krel _arch_pkg_ver
	local _flavor

	# Set our arch if it was explicitly specified, then shift if found.
	local _allarchsglob="$(get_all_archs_with_sep ' | ')"
	eval "case \"\$1\" in $_allarchsglob ) _arch=\"\$1\" ; shift ;; esac"
	
	# TODO: kerneltool_stage - Handle kernel images/tarballs.

	# Detect our arch and kernel release from the first argument.
	info_func_set "stage (detect arch/krel)"
	[ "$1" ] || set -- linux-vanilla linux-firmware
	case "$1" in current) shift ; set -- "$(uname -r)" "$@" ;; latest) shift ; set -- "linux-vanilla" "$@" ;; latest-*) _flavor="${1#latest-}" ; shift ; set -- "linux-${_flavor}" "$@" ;; esac

	case "$1" in
		*.apk)	# Handle explicit kernel .apk
			_arch_pkg_ver="$(apk_get_arch_package_version $1)"
			_arch_krel="$(kerneltool_apk_get_arch_kernel_release $1)"
			if ! [ "$_arch" ] ; then _arch="$_arch_krel%%/*}"
			elif [ "${_arch_krel%%/*}" = "$_arch" ] ; then warning "Kernel in apk '$1' is for arch '${_arch_krel%%/*}' but '$_arch' requested!" ; return 1 ; fi
			;;
		/*/*|./*|../*)	# Handle kernel build directory
			_arch_krel="$(kerneltool_custom_get_arch_kernel_release $1)"
			if ! [ "$_arch" ] ; then _arch="${_arch_krel%%/*}"
			elif [ "${_arch_krel%%/*}" = "$_arch" ] ; then warning "Kernel at '$1' configured for arch '${_arch_krel%%/*}' but '$_arch' requested!" ; return 1 ; fi
			;;
		*/*)  # Handle arch/krel pairs
			_arch_krel="$1"
			_arch="${_arch_krel%%/*}" && all_archs_has $_arch || ! warning "Specified arch '$_arch' not recognized!" || return 1
			_krel="${_arch_krel#*/}"
			;;
		# Handle packages with version
		linux-*-[0-9].*-r[0-9]*) k_pkg="$1" ;;
		linux-*-[0-9].*) k_pkg="$1-r0" ;;
		# Handle alpine package name with no version
		linux-*) k_pkgname="$1" ;;
		# Handle 'linux-<krel>' (with or without -r)
		linux-[0-9].*-r[0-9]*-*|linux-[0-9].*-r[0-9]*) _krel="${1#linux-}" ; _krel="${_krel/-r/-}" ;;
		linux-[0-9].*-*-*|linux-[0-9].*-*|linux-[0-9].*) _krel="${1#linux-}" ;;
		# Handle raw kernel version (uname -r)
		[0-9].*-r[0-9]*-*|[0-9].*-r[0-9]*) _krel="${1/-r/-}" ;;
		[0-9].*-*-*|[0-9].*-*|[0-9].*) _krel="$1" ;;
		*) warning "Unknown kernel spec: '$1'" ; return 1 ;;
	esac

	# If nothing has specified an arch yet, default to the system's arch.
	[ "$_arch" ] || _arch="$(_apk --print-arch)"
	
	info_func_set "stage (setup)"
	# Setup staging base directory.
	mkdir_is_writable "$stage_base" && stage_base="$(realpath $stage_base)" || ! warning "Failed to create staging base directory '$stage_base'" || return 1

	# Setup staging directory for this arch.
	mkdir_is_writable "$stage_base/$_arch" || ! warning "Failed to create writable directory for staging arch '$_arch'!" || return 1

	# Setup staging apkroot for this arch.
	local stage_apkroot="$stage_base/$_arch/apkroot"

	# Setup alpine-keys so we can actually fetch things for our desired arch. We do this BEFORE we setup our apkroot.
	if dir_not_exists "$stage_apkroot/etc/apk/keys" ; then
		mkdir_is_writable "$stage_apkroot/etc/apk/keys" || ! warning "Failed to setup staging apkroot at '$stage_apkroot'!" || return 1
		_apk fetch -s alpine-keys | tar -C "$stage_apkroot" -xz usr/share/apk/keys || ! warning "Could not fetch package 'alpine-keys' or extract '/usr/share/apk/keys' to '$stage_apkroot'!" || return 1
		cp -L "$stage_apkroot/usr/share/apk/keys/$_arch/"* "$stage_apkroot/etc/apk/keys"
	fi

	# Initilize our apk root
	apkroot_init "$_arch" "$stage_apkroot"
	apkroot_tool $OPT_apkroot_tool_cmdline
	info_func_set "stage (setup)"
	_apk update ${VERBOSE--q} || warning "Could not update apk database. Continuing..."

	# Setup apk storage dir.
	local stage_apkstore="$stage_base/$_arch/apks"
	mkdir_is_writable "$stage_apkstore" || ! warning "Failed to setup staging apkstore at '$stage_apkstore'!" || return 1
	
	# Create a manifests directory for this arch.
	local manifests="$stage_base/$_arch/manifests"
	mkdir_is_writable "$manifests" || ! warning "Failed to create directory for staging manifests '$manifests'" || return 1

	# Derive the full package atom when given a package name only.
	[ "$k_pkgname" ] && [ ! "$k_pkg" ] && k_pkg="$(apk_pkg_full "$k_pkgname")"
	# Split package atom to into package name and version.
	k_pkgname="${k_pkg%-*-*}"
	k_pkgver="${k_pkg#$k_pkgname-}"

	# Derrive the kernel release from the package (fetching if needed).
	if ! [ "$_krel" ] && [ "$k_pkgname" ] ; then
		file_is_readable "$stage_apkstore/$k_pkg.apk" || kerneltool_apk_fetch "$_arch" "$_krel" "$k_pkgname"  "$stage_apkstore" || ! warning "Could not fetch '$k_pkg'!" || return 1
		_arch_krel="$(kerneltool_apk_get_arch_kernel_release "$stage_apkstore/$k_pkg.apk")"
		[ "${_arch_krel%%/*}" != "$_arch" ] && warning "Kernel in apk '$1' is for arch '${_arch_krel%%/*}' but '$_arch' requested!" && return 1
		_krel="${_arch_krel#*/}"
	fi
	if ! [ "$_krel" ] ; then
		_krel="${k_pkgver/-r/-}-${k_pkgname#linux-}"
		warning "Could not determine kernel release for '$k_pkgname' in a reliable manner, falling back to using package version number."
	fi

	# Setup kernel staging for this arch and kernel release (restage/unstage here if requested); Set _kernpkg_ to the package name for the kernel if needed.
	local stage_kern="$stage_base/$_arch/$_krel"
	if [ "$RESTAGE" = "yes" ] || [ "$UNSTAGE" = "yes" ] ; then
		! dir_exists "$stage_kern" || rm -rf "$stage_kern" || ! warning "Could not purge staging directory at '$stage_kern'!" || return 1
		[ "$UNSTAGE" = "yes" ] && msg "Unstaged '$_arch/$_krel'." && return 0
	fi

	if dir_exists "$stage_kern" || mkdir_is_writable "$stage_kern" ; then _kernpkg_="${k_pkgname:-yes}"
	else warning "Failed to create staging kernel directory '$stage_kern'" ; return 1
	fi

	info_func_set "stage"
	# Loop over items to be staged
	local i _type _subdir
	for i do
		i="${i%/}"
		# Fix the mess if we gave it something other than a simple package name as our original arg
		[ "${_kernpkg_##yes}" ] && i="$_kernpkg_"

		# Figure out what type we're dealing with and set things up.
		case "$i" in
			*.apk)
				_type="apk"
				_subdir="${i##*/}" && _subdir="${_subdir%.apk}"
				cp -f "$i" "$stage_apkstore" && i="${i##*/}"
				;;
			*/*)	
				_type="kbuild"
				_subdir="kbuild-{i##*/}"
				;;
			*)
				_type="apk"
				local _i="$i"
				i="$(apk_pkg_full "${i%-*-*}")"
				if ! [ "$i" ] ; then warning "Could not find package matching '$_i'!" ; return 1
				elif [ "$_i" = "${i%-*-*}" ] ; then msg "Using '$i' for package '$_i'."
				elif [ "$i" != "$_i" ] ; then warning "Specified package '$_i' but found '$i'! Continuing with '$i'..." ; fi
				_subdir="apk-$i"
				
				;;
		esac


		# Handle fetching apks as needed.
		case "$_type" in
			apk)
				file_is_readable "$stage_apkstore/$i.apk" || kerneltool_apk_fetch "$_arch" "$_krel" "$i" "$stage_apkstore" || ! warning "Could not fetch '$i'!" || return 1
				i="$stage_apkstore/$i.apk"

				_apkmanifest="$manifests/${i##*/}.Manifest"
				if file_is_readable "$_apkmanifest" && verify_file_checksums "$i" "$(sed -n -e '2 p' "$_apkmanifest")" ; then
					msg "Checksum matches for '${i##*/}' in APK Manifest '$_apkmanifest'."
				elif file_is_readable "$_apkmanifest" ; then
					msg "Checksum found for '${i##*/}' in Manifest '$_apkmanifest' does not match actual checksum of verified apk in '${i}', regenerating."
					rm -f "$_apkmanifest" || ! warning "Could not remove stale '$_apkmanifest'!" || return 1
				elif file_exists "$_apkmanifest" ; then
					warning "Manifest '$_apkmanifest' exists, but is unreadable -- attempting to regenerate!"
					rm -f "$_apkmanifest" || ! warning "Could not remove bad '$_apkmanifest'!" || return 1
				fi

				if file_not_exists "$_apkmanifest" ; then 
					msg "Building APK Manifest for '$i'..."
					apk_build_apk_manifest "$manifests" "$i" || ! warning "Failed to create APK Manifest for '$i!'" || return 1
					msg2 "Done."
				fi

				;;
		esac

		# Set the list of sub-parts to be staged for each package, then iterate over it.
		kerneltool_stage_parts="${kerneltool_stage_parts:-"${_kernpkg_:+"kernel "} modules firmware dtbs headers"}"
		for p in $kerneltool_stage_parts ; do
			info_func_set "stage ($p)"
			_mymanifest="$manifests/$_subdir-$p.Manifest"
			_myddir="$stage_kern/$_subdir-$p"

			
			if dir_exists "$_myddir" ; then
				if file_exists "$_mymanifest" ; then
					info_func_set "stage ($p check-manifest)"
					msg "Directory '$_subdir-$p' exists in '$stage_kern', checking contents against manifest '$_mymanifest'..."
					kerneltool_verify_path_manifest "$_myddir" "$_mymanifest" && msg "Matched." && continue
					warning "Contents of directory '$_myddir' does not match manifest '$_mymanifest'!" 
				fi
				info_func_set "stage ($p)"
				msg "Rebuilding directory '$_subdir-$p' in '$stage_kern'."
				rm -rf "$_myddir" || ! warning "Could wipe destination directory for '$_subdir-$p' in '$stage_kern'!" || return 1
			fi
			info_func_set "stage ($p)"
			mkdir_is_writable "$_myddir" || ! warning "Could not create writable destination directory for '$_subdir-$p' in '$stage_kern'!" || return 1

			# Extract / install this subpart.
			case "$_type" in
				apk) 
					info_func_set "stage ($p-extract)"
					msg "Extracting '$i' to '$_subdir-$p' in '$stage_kern'."
					kerneltool_apk_extract_$p "$_arch" "$_krel" "$i" "$stage_kern/$_subdir-$p" || ! warning "Failed to extract $p from '$i' into '$_myddir'!" || return 1
					;;
				kbuild)
					info_func_set "stage ($p-install)"
					msg "Installing $p from '$i' into staging dir '$_myddir'."
					kerneltool_kbuild_make_${p}_install "$_arch" "$_krel" "$i" "$stage_kern/$_subdir-$p" || ! warning "Failed to stage $p from '$i' into '$_myddir'!" || return 1
					;;
			esac

			# Postprocess this subpart.
			case "$p" in
				kernel)
					if dir_exists "$_myddir/boot" ; then
						info_func_set "stage ($p-post)"
						( cd "$_myddir/boot" ; for _f in * ; do if file_exists "$_f" ; then mv "$_f" "${_f}-$_krel" && ln -s "${_f}-$_krel" "$_f" ; fi ; done) ;
					fi
				;;

				modules)
					if dir_exists "$_myddir/lib/modules" ; then
						info_func_set "stage ($p-post check-versions)"
						# Check that the vermagic version of the module matches the requested kernel release
						local _vermismatches="$( cd "$_myddir" \
							&& find -type f \( -iname '*.ko' -o -iname '*.ko.*' \) -exec sh -c "modinfo -F vermagic {} | cut -d' ' -f 1 | grep -q -v '^$_krel'" \; -print \
							| sed 's/^[[:space:]]*$//g' )"
						[ "$_vermismatches" ] && warning "Mismatch between kernel release '$_krel' and vermagic value in modules:" && warning2 "$_vermismatches" && return 1

						# Build kmod index.
						info_func_set "stage ($p-post build-index)"
						local _mymod _mymodname
						local _mymodindex="$manifests/${_myddir##*/}.kmod-INDEX"
						: > "$_mymodindex"
						file_is_writable "$_mymodindex" || ! warning "Could not write to module index at '$_mymodindex'!" || return 1

						(	cd "$_myddir"
							printf '# Module index for: %s/%s-%s\n' "$_arch" "$_subdir" "$p"
							printf '# Kernel: %s/%s\n' "$_arch" "$kver"

							find "lib/modules" -type f \( -iname '*.ko' -o -iname '*.ko.*' \) -print | while read _mymod; do
								_mymodname="${_mymod##*/}" && _mymodname="${_mymodname%.ko.*}" && _mymodname="${_mymodname%.ko}"
								printf 'kmod:%s:%s/%s:%s\t' "$_mymodname" "$_arch" "$_krel" "$(kerneltool_checksum_module "$_myddir/$_mymod")"
								printf 'kpkg:%s/%s-%s\t' "$_arch" "$_subdir" "$p"
								calc_file_checksums "$_mymod" sha512 ; printf '\n'
							done
						) >> "$_mymodindex" || ! warning "Failed to create module index '$_mymodindex' for '$_myddir'!" || return 1
						unset _mymod _mymodname _mymodindex
					fi
				;;

				firmware)
					if dir_exists "$_myddir/lib/firmware" ; then
						# Build firmware index.
						info_func_set "stage ($p-post build-index)"
						local _myfw
						local _myfwindex="$manifests/${_myddir##*/}.firmware-INDEX"
						: > "$_myfwindex"
						file_is_writable "$_myfwindex" || ! warning "Could not write to module index at '$_myfwindex'!" || return 1
						( 	cd "$_myddir"
							printf '# Firmware index for: %s/%s-%s\n' "$_arch" "$_subdir" "$p"
							find "lib/firmware" -type f -print | while read _myfw; do
								_myfw="${_myfw#./}"
								printf 'firmware:%s:%s:%s\t' "${_myfw#lib/firmware/}" "$_arch" "$(kerneltool_checksum_module "$_myfw")"
								printf 'kpkg:%s/%s-%s\t' "$_arch" "$_subdir" "$p"
								calc_file_checksums "$_myfw" sha512 ; printf '\n'
							done
						) >> "$_myfwindex" || ! warning "Failed to create firmware index '$_mymodindex' for '$_myddir'!" || return 1
					fi
				;;
			esac

			# Generate Manifest for this subpart.
			info_func_set "stage ($p-manifest)"
			if dir_exists "$_myddir" ; then
				msg "Building Manifest for '$_myddir' at '$_mymanifest'."
				kerneltool_calc_path_manifest "$_myddir" "kpkg:$_arch/$_subdir-$p" > "$_mymanifest"
			fi
		done

		# Don't try to extract multiple kernels.
		kerneltool_stage_parts="${kerneltool_stage_parts/kernel /}"	
		unset _kernpkg_

	done

	# Wipe and create merged-root for this arch and kernel release
	info_func_set "stage (merge)"
	msg "Merging contents of all staging subdirectiories under '$_arch/$_krel' into '$_arch/merged-$_krel'."
	local merged="$stage_base/$_arch/merged-$_krel"
	dir_not_exists "$merged" || rm -rf "$merged" || ! warning "Failed to wipe target directory before merging!" || return 1 # We want to recreate this every time even if we're only adding staged files.
	mkdir_is_writable "$merged" || ! warning "Failed to create directory for staging merged root '$merged'" || return 1

	# Create hardlinked copy of all contents of all subdirectories in stage_base into merged.
	(cd "$stage_kern" && cp -rl */* "$merged") || ! warning "Could not merge '$stage_kern/*' into '$merged'!" || return 1

	merged_manifest="$manifests/$_krel.Manifest" merged_kmod_index="$manifests/$_krel.kmod-INDEX" merged_firmware_index="$manifests/$_krel.firmware-INDEX"
	# Creat merged Manifest, kmod-INDEX, and firmware-INDEX
	printf '# Manifest for %s/%s\n' "$_arch"  "$_krel" > "$merged_manifest" && file_is_writable "$merged_manifest" || ! warning "Could not write to merged Manifest at '$merged_manifest'!" || return 1
	(cd "$stage_kern" && for _d in * ; do file_exists "$manifests/$_d.Manifest" && cat "$manifests/$_d.Manifest" ; done ) | grep -v '^#' | sort -u -k3 -k2 -k1 >> "$merged_manifest"
	printf '# kmod INDEX for %s/%s\n' "$_arch" "$_krel" > "$merged_kmod_index" && file_is_writable "$merged_kmod_index" || ! warning "Could not write to merged Manifest at '$merged_kmod_index'!" || return 1
	(cd "$stage_kern" && for _d in * ; do file_exists "$manifests/$_d.kmod-INDEX" && cat "$manifests/$_d.kmod-INDEX"; done ) | grep -v '^#' | sort -u -k3 -k2 -k1  >> "$merged_kmod_index"
	printf '# firmware INDEX for %s/%s\n' "$_arch" "$_krel" > "$merged_firmware_index" && file_is_writable "$merged_firmware_index" || ! warning "Could not write to merged Manifest at '$merged_firmware_index'!" || return 1
	(cd "$stage_kern" && for _d in * ; do file_exists "$manifests/$_d.firmware-INDEX" && cat "$manifests/$_d.firmware-INDEX" ; done ) | grep -v '^#' | sort -u -k3 -k2 -k1  >> "$merged_firmware_index"


	# Update module dependencies.
	info_func_set "stage (depmod)"
	msg "Running depmod against staged modules for '$_arch/$_krel'."
	kerneltool_depmod "$merged" "$_krel" || ! warning "depmod for '$_krel' failed in merged dir '$merged'!" || return 1

	# Create checksummed module and firmware deps for each module.
	info_func_set "stage (kmod-deps)"
	msg "Calculating checksummed module and firmware dependencies for all modules for '$_arch/$_krel'."
	_moduledepfile="$manifests/$_krel.kmod_fw-DEPS"
	( cd "$merged"
		: > "$_moduledepfile" && file_is_writable "$_moduledepfile" || ! warning "Could not write to module and firmware dependency dump at '$_moduledepfile'!" || return 1
		find "lib/modules" -type f \( -iname '*.ko' -o -iname '*.ko.*' \) -print | while read _mymod; do
			kerneltool_calc_module_fw_deps "$_arch" "$_krel" "$merged" "$_mymod"
		done
	) >> "$_moduledepfile" || ! warning "Failed to create checkesummed kernel module and firmware dependency dump!" || return 1


	info_prog_set "kerneltool-stage"
	msg "Staging complete for '$_arch/$_krel'."

	info_func_set "stage"
	msg "Done."
	return 0
}



# Command: depmod
# Usage: kerneltool_depmod <base dir> [<kernel release>]
kerneltool_depmod() {
	info_prog_set "kerneltool-depmod"
	local _bdir="$1" _krel="$2"
	shift 2
	depmod -a -e ${VERBOSE+-w }-b "$_bdir" -F "$_bdir/boot/System.map-$_krel" $_krel 
	#2>&1 > /dev/null | grep -e '^.+$' >&2 && warning "Errors encounterd by depmod in '$_bdir'!" && return 1
}


# Command: mkmodsubset
# Build module subset given a name and list of module names and/or globs.
# Usage: kerneltool_mkmodsubset <staging base> <arch> <kernel release> <subset name> [<list of modules/globs>...]
kerneltool_mkmodsubset() {
	info_prog_set "kerneltool-mkmodsubset"
	info_func_set "mkmodsubset"
	local stage_base="$1" _arch="$2" _krel="$3" _subname="$4"
	shift 4
	allmods="$@"
	local _merged="$stage_base/$_arch/merged-$_krel"
	local _modbase="$_merged/lib/modules"
	dir_is_readable "$_modbase" || ! warning "Could not read merged modules directory '$_modbase'" || return 1

	
	local _ddir="$stage_base/$_arch/$_krel-subsets/$_subname"
	dir_not_exists "$_ddir" || rm -rf "$_ddir" || ! Warning "Could not clean destination directory '$_ddir' to build module subeset '$_subname'!" || return 1
	mkdir_is_writable "$_ddir" || ! warning "Could not create destination directory '$_ddir' to build module subset '$_subname'!" || return 1

	local _modout="$_ddir/lib/modules"
	mkdir_is_writable "$_modout" || ! warning "Could not create temp output directory for modules at '$_modout'!" || return 1
	
	local _fwbase="$_merged/lib/firmware"
	local _fwout="$_ddir/lib/firmware"
	
	info_func_set "copy modules"
	local _kmod_index="$stage_base/$_arch/manifests/$_krel.kmod-INDEX"
	local _firmware_index="$stage_base/$_arch/manifests/$_krel.firmware-INDEX"
	local _kmod_fw_deps="$stage_base/$_arch/manifests/$_krel.kmod_fw-DEPS"
	local mod_subset_manifest
	mod_subset_manifest="$_ddir.kmod-Manifest"
		
	if [ $# -gt 0 ] ; then
		msg "Selecting requested modules and their deps from '$_modbase' into '$mod_subset_manifest'."
		local _kmod _kpkg _kfsum _kfile
		cat "$_kmod_index" | while read _kmod _kpkg _kfsum _kfile ; do
			for _mod in $allmods ; do
				#msg "_kmod: $_kmod"
				#msg "_file: $_kfile"
				#msg "_mod:$_mod"
				case "$_mod" in 
					*/*/) case "$_kfile" in lib/modules/*/$_mod* ) : ;; *) continue;; esac ;;
					*/*) case "$_kfile" in lib/modules/*/$_mod ) : ;; *) continue ;; esac ;;
					*) case "$_kmod" in "kmod:$_mod:"* | "kmod:${_mod%.ko*}:"* ) : ;; *) continue ;; esac ;;
				esac
				grep -e "^$_kmod" "$_kmod_fw_deps"
			done
		done | grep -v '^#' | tr -s '\t ' '\n' | sort -u > "$mod_subset_manifest"
	else
		msg "Selecting all staged modules found in '$_modbase' and their firmware deps into '$mod_subset_manifest'."
		cat "$_kmod_fw_deps" | grep -v '^#' | tr -s '\t ' '\n' | sort -u > "$mod_subset_manifest"
	fi

	file_exists "$mod_subset_manifest" || ! warning "No module-subset Manifest found at '$mod_subset_manifest'!" || return 1
	info_func_set "copy modules"
	if file_is_readable "$_kmod_index" ; then 
		grep -F -f "$mod_subset_manifest" "$_kmod_index" | grep -v '^#' | tr '\t' ' ' | while read _kmod _kpkg _kfsum _kfile ; do
			if [ "$_kmod" ] ; then 
				_filein="$stage_base/$_arch/$_krel/${_kpkg#kpkg:$_arch/}/$_kfile"
				_fileout="$_modout/$_kfile"
				[ "$VERBOSE" ] && msg "'$_filein' -> '$_fileout'"
				file_exists "$_filein" || ! warning "Could not read kernel module file '$_filein'!" || continue
				mkdir_is_writable "${_fileout%/*}" || ! warning "Could not make module output subdirectory '${_fileout%/*}'!" || return 1
				cp -L "$_filein" "$_fileout" || ! warning "Could not hardlink module '$_filein' to '$_fileout'!" || return 1
				echo $(( ++_modcount ))
			fi
		done | tail -n 1 | sed -E -e 's/[[:space:]]//g' | ( read _modcount && msg "Copied $_modcount kernel modules to '$_modout'." )
	else warning "Could not read kernel module index '$_kmod_index'!" ; return 1 ; fi

	info_func_set "copy firmware"
	if file_not_exists "$_firmware_index" ; then msg "No firmware index found at '$_firmware_index', not copying firmware."
	elif grep -q "^firmware:" "$mod_subset_manifest" ; then msg "Copying firmware needed by selected modules:"
		local _fwcount=0
		grep -F -f "$mod_subset_manifest" "$_firmware_index" | grep -v '^#' | tr '\t' ' ' | while read _fw _kpkg _fwsum _fwfile ; do
			if [ "$_fw" ] ; then
				: $(( _fwcount + 1 ))
				_filein="$stage_base/$_arch/$_krel/${_kpkg#kpkg:$_arch}/$_fwfile"
				_fileout="$_fwout/$_fwfile"
				[ "$VERBOSE" ] && msg "'$_filein' -> '$_fileout'"
				file_exists "$_filein" || ! warning "Could not read firmware file '$_filein'!" || continue
				mkdir_is_writable "${_fileout%/*}" || ! warning "Could not make firmware output subdirectory '${_fileout%/*}'!" || return 1
				cp -L "$_filein" "$_fileout" || ! warning "Could not hardlink firmware '$_filein' to '$_fileout'!" || return 1
				echo $(( ++_fwcount ))
			fi
		done | tail -n 1 | sed -E -e 's/[[:space:]]//g' | ( read _fwcount && msg "Copied $_fwcount firmware files to '$_fwout'." ) 
	else msg "No firmware to copy." ; fi
}


# Command: mkmodcpio
# Build module cpio from subset
# Usage: kerneltool_mkmodcpio <staging base> <arch> <kernel release> [modsubset=<subset name>] [<list of modules/globs>...]
kerneltool_mkmodcpio() {
	info_prog_set "kerneltool-mkmodcpio"
	info_func_set "mkmodcpio"
	local stage_base="$1" _arch="$2" _krel="$3" _subname="$4"
	shift 3

	local _tmp _keeptmp _subname _subexists
	case "$_subname" in
		modsubset=*)
			_keeptmp="yes"
			_subname="${_subname#*=}"
			shift
			;;
		*)
			_subname="modules-$_krel-$(echo "$*" | md5sum | cut -d' ' -f 1)"
			;;
	esac

	local _tmp="$stage_base/$_arch/$_krel-subsets/$_subname"
	local _outdir="$stage_base/$_arch/out-$_krel/boot"
	local _outname="modules-$_krel.cpio.gz"
	mkdir_is_writable "$_outdir" || ! warning "Could not create writable output directory '$_outdir'!" || return 1

	[ "$_keeptmp" = "yes" ] && dir_exists "$_tmp" || kerneltool_mkmodsubset "$stage_base" "$_arch" "$_krel" "$_subname" $@ || ! warning "Failed to make module subset '$_subname' needed to make '$_outname'!" || return 1

	info_func_set "create cpio"
	(cd "$_tmp" && find | sort -u | sed -e 's|\./||g' | cpio -H newc -o | gzip -9 ) > "$_outdir/$_outname" || ! warning "Failed to create '$_outname' in '$_outdir'!" || return 1
	[ "$_keeptmp" = "yes" ] || rm -rf  "$_tmp" || ! warning "Could not clean up tmp directory for mkmodcpio at '$_tmp'!" || return 1
	msg "mkmodcpio complete!"
	msg "Compressed module cpio file for '$_arch/$_krel' is at '$_outdir/$_outname'."
	return 0
}


# Command: mkmodloop
# Build modloop from subset
# Usage: kerneltool_mkmodloop <staging base> <arch> <kernel release> [modsubset=<subset name>] [<list of modules/globs>...]
kerneltool_mkmodloop() {
	info_prog_set "kerneltool-mkmodloop"
	info_func_set "mkmodloop"
	local stage_base="$1" _arch="$2" _krel="$3" _subname="$4"
	shift 3

	local _tmp _keeptmp _subname _subexists
	case "$_subname" in
		modsubset=*)
			_keeptmp="yes"
			_subname="${_subname#*=}"
			shift
			;;
		*)
			_subname="modloop-$_krel-$(echo "$*" | md5sum | cut -d' ' -f 1)"
			;;
	esac

	local _tmp="$stage_base/$_arch/$_krel-subsets/$_subname"
	local _outdir="$stage_base/$_arch/out-$_krel/boot"
	local _outname="modloop-$_krel"
	mkdir_is_writable "$_outdir" || ! warning "Could not create writable output directory '$_outdir'!" || return 1

	[ "$_keeptmp" = "yes" ] && dir_exists "$_tmp" || kerneltool_mkmodsubset "$stage_base" "$_arch" "$_krel" "$_subname" $@ || ! warning "Failed to make module subset '$_subname' needed to make '$_outname'!" || return 1

	info_func_set "create squashfs"
	mksquashfs "$_tmp/lib" "$_outdir/$_outname" -root-owned -no-recovery -noappend -progress -comp xz -exit-on-error ${VERBOSE:+-info} | cat ${QUIET:+/dev/null} \
		|| ! warning "Failed to mksqwashfs '$_tmp/lib' to '$_outdir/$_outname' with compression 'xz'!" || return 1
	[ "$_keeptmp" = "yes" ] || rm -rf  "$_tmp" || ! warning "Could not clean up tmp directory for mkmodloop at '$_tmp'!" || return 1
	msg "mkmodloop complete!"
	msg "Compressed squashfs modloop file for '$_arch/$_krel' is at '$_outdir/$_outname'."
	return 0
}



###
## Kerneltool Helper Functions
###

# Print kernel arch given system arch.
# Usage: get_karch_from_arch <arch>
kerneltool_get_karch_from_arch() {
	local _karch="$(getvar arch_$1_kernel_arch_name)"
	[ "$_karch" ] && printf '%s' "$_karch" && return 0
	warning "No \$arch_$1_kernel_arch_name set!" ; return 1
}


# Find system arch for given kernel arch.
# Usage: get_arch_from_karch <kernel arch>
kerneltool_get_arch_from_karch() {
	local a
	for a in $(get_all_archs) ; do
		[ "$(kerneltool_get_karch_from_arch "$a")" = "$1" ] && printf '%s' "$a" && return 0
	done
	return 1
}


# Get sha512 checksum of uncompressed module given a compressed or uncompressed module, or checksum of raw file (firmware) with no decompression applied.
# Usage: kerneltool_checksum_module <kernel module file>
kerneltool_checksum_module() {
	local _file="$1" _mc
	file_is_readable "$1" || ! warning "Could not read module '$1'!" || return 1
	case "$_file" in
		*.ko) : uncompressed module; _mc='cat';;
		*.ko.bz*) : compressed module; _mc='bzcat';; *.ko.gz)_mc='zcat';; *.ko.lz4)_mc='lz4cat';; *.ko.lzo*)_mc='lzopcat';; *.ko.xz|*.ko.lz*)_mc='xzcat';;
		*) : unrecognized module extension, checksum raw file ; _mc='cat'
	esac
	$_mc "$_file" | sha512sum | cut -d' ' -f 1 | sed 's/^/sha512:/g'
}


# Calculate complete module dependency tree (including firmware) for the given list of modules, with checksums.
# Usage: kerneltool_calc_module_fw_deps <arch> <kernel release> <base dir> <modules...>
kerneltool_calc_module_fw_deps() {
	local _arch="$1" _krel="$2" _bdir="$3"
	shift 3
	local _fwbase="$_bdir/lib/firmware"
	local _mod _myfile _mydeps _mydepfiles _vermagic _myfw _fw _mc _sums _file _mymod
	for _mymod in $@ ; do
		_sums="" _mydeps="" _mydepfiles="" _fw=""
		_myfile="$(modinfo -b "$_bdir" -k "$_krel" -F filename "$_mymod")"
		_mymod="${_myfile##*/}" && _mymod="${_mymod%%.ko*}"
		[ "$VERBOSE" ] && msg "Calculating module and firmware dependencies for '$_mymod'."

		# Get list of deps for mod and replace ',' with newline.
		_mydeps="$(modinfo -b "$_bdir" -k "$_krel" -F depends "$_myfile" | sed 's/,/\n/g' )"

		# Get filenames for each dep.
		for _mod in $_mydeps ; do _mydepfiles="${_mydepfiles+"$_mydepfiles "}$(printf '%s' $(modinfo -b "$_bdir" -k "$_krel" -F filename "$_mod"))"; done

		# Do some sanity checks, then get checksums for mod and deps (tab sep)
		for _file in $_myfile $_mydepfiles ; do
			# Parse module out of filename and make sure we can read file
			_mod="${_file##*/}" && _mod="${_mod%.ko*}"
			file_is_readable "$_file" || ! warning "Could not read file '$_file' for module '$_mod'!" || return 1

			# Check that the vermagic version of the module matches the requested kernel release
			_vermagic="$(modinfo -b "$_bdir" -k "$_krel" -F vermagic "$_file" | cut -d' ' -f 1)"
			[ "$_vermagic" = "$_krel" ] || ! warning "Mismatch between kernel release '$_krel' and module '$_file' vermagic value of '$_vermagic'!" || return 1
			[ "$VERBOSE" ] && msg "Module '$_mymod' depends on '$_mod'."

			# Determine which tool to use to cat compressed modules for checksumming
			case "$_file" in *.ko)_mc='cat';; *.ko.bz*)_mc='bzcat';; *.ko.gz)_mc='zcat';; *.ko.lz4)_mc='lz4cat';; *.ko.lzo*)_mc='lzopcat';; *.ko.xz|*.ko.lz*)_mc='xzcat';; esac
			# Checksum this module and add it to the end of the list
			_sums="${_sums}$(printf 'kmod:%s:%s/%s:%s\t' "$_mod" "$_arch" "$_krel" "$(kerneltool_checksum_module "$_file")" )"

			# Find list of required firmware for each module, if any.
			_fw="$(modinfo -b "$_bdir" -k "$_krel" -F firmware "$_file" )"
			for _myfw in $_fw ; do
				_file="$_fwbase/$_myfw"
				if file_is_readable "$_file" ; then 
					_sums="${_sums}$(printf 'firmware:%s:%s:%s\t' "$_myfw" "$_arch" "$(kerneltool_checksum_module "$_file")" )"
					[ "$VERBOSE" ] && msg "Module '$_mod' depends on '$_myfw'."
				else 
					_sums="${_sums}$(printf 'firmware:%s:%s:%s\t' "$_myfw" "$_arch" "UNRESOLVED" )"
					[ "$VERBOSE" ] && msg "Could not find firmware '$_myfw' in '$_fwbase' needed by module '$_mod'!"
				fi
			done
		done
		printf '%s\n' "$_sums"
	done
}

