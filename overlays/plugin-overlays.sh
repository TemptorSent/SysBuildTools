
plugin_overlays() {
	var_list_alias overlays
}


section_overlays() {
	[ "${overlays## }" ] || return 0
	local _id="$(echo "$hostname::$overlay_name::$overlays::$PROFILE::$ARCH" | checksum)"
	build_section overlays $hostname $overlay_name $_id
}


build_overlays() {
	local my_overlays="$overlays"
	local run_overlays=""
	ovl_hostname="$1"
	ovl_root_dir="${DESTDIR%.work}-ovlroot"
	mkdir_is_writable "$ovl_root_dir" \
		|| ! warning "build_overlays: Could not create writeable directory to build overlay root: '$ovl_root_dir'" || return 1

	local _err=0
	ovl_fkrt_inst="ovl"
	fkrt_faked_start "$ovl_fkrt_inst"
	
	local watchdog=20
	while [ $_err -eq 0 ] && [ "${my_overlays## }" ] && [ $watchdog -gt 0 ]; do
		for _overlay in $my_overlays ; do
			overlay_${_overlay}
			if [ "${_conflicts## }" ] && ( list_has_any "$_conflicts" "$overlays" ) ; then
				warning "overlay: Overlay conflict detected!"
				warning2 "    '$_overlay' conflicts with '$(list_filter "$_conflicts" "$overlays" )'"
				_err=1
				break
			fi
			if [ ! "${_needs## }" ] || list_has_all "$_needs" "$overlays" ; then
				[ "${_after## }" ] && list_has_any "$_after" "$my_overlays" && continue
				[ ! "${_before## }" ] || list_has_all "$(list_filter "$_before" "$overlays")" "$run_overlays" || continue

				local _func
				for _func in $_call ; do
					if [ "$_func" ] && [ "$(type -t $_func)" ] && ! $_func ; then
						_err=1 ; warning "Call to '$_func' failed in overlay '$_overlay'."
						break
					fi
				done
				[ $_err -eq 0 ] || break

				run_overlays="$run_overlays $_overlay"
				var_list_del my_overlays "$_overlay"

				watchdog=$(( $watchdog + 5 ))
			else
				if ( list_has_all "$_needs" "$all_overlays" ) ; then
					list_add "$_needs" "$my_overlays"
				else
					warning "Could not find the following overlays needed by overlay '$_overlay':"
					warning2 "$(list_del "$all_overlays" "$_needs" )"
					_err=1
					break
				fi
			fi
			unset _needs
			unset _conflicts
			unset _before
			unset _after
			unset _call
		done

		[ $_err -eq 0 ] || break

		watchdog=$(( $watchdog - 1 ))
		if [ $watchdog -lt 1 ] ; then
			warning "overlay: Watchdog counter expired!"
			warning "    This means we probably got stuck in an infinate loop resolving run order."
			warning "    The following were not resolved: $my_overlays"
			_err=1
			break
		fi
	done

	if [ $_err -eq 0 ] ; then
		if [ "$all_apks_in_world" = "true" ] ; then ovl_add_apks_world "$apks" "$(suffix_kernel_flavors $apks_flavored)" || _err=1 ; fi
		if [ "$rootfs_apks" ] ; then ovl_add_apks_world "$rootfs_apks" "$(suffix_kernel_flavors $rootfs_apks_flavored)" || _err=1 ; fi
		if [ "$run_overlays" ] ; then ovl_targz_create "${overlay_name:-$ovl_hostname}" "$ovl_root_dir" "etc/.." || _err=1 ; fi
	fi

	fkrt_faked_stop "$ovl_fkrt_inst"

	return $_err
}


ovl_add_apks_world() {
	local _ovlwld _err
	_ovlwld="$(ovl_path /etc/apk/world)"
	_err=0

	ovl_fkrt_enable
	if file_is_writable "$_ovlwld" ; then
		(IFS=$'\n\r ' ; cat "$_ovlwld" | xargs printf '%s\n' $@ > "$_ovlwld") || _err=1
	elif dir_is_writable "$(ovl_get_root)" ; then
		( mkdir_is_writable "${_ovlwld%/*}" || ! warning "ovl_add_apks_world - Could not create directory '${_ovlwld%/*}'." ) \
			&& (IFS=$'\n\r ' ; printf_n $@ > "$_ovlwld") \
			|| _err=1
	else
		_err=1 && warning "ovl_add_apks_world - Could not write world file '$_ovlwld'"
	fi
	ovl_fkrt_disable

	return $_err
}


ovl_fkrt_enable() {
	fkrt_enable $ovl_fkrt_inst
}


ovl_fkrt_disable() {
	fkrt_disable
}


ovl_get_root() {
	printf '%s' $ovl_root_dir
}


ovl_path() {
	printf '%s' "${ovl_root_dir%%/}/${1##/}"
}

ovl_file_exists() {
	file_exists "$(ovl_get_root)/${1#/}"
}

ovl_file_not_exists() {
	file_not_exists "$(ovl_get_root)/${1#/}"
}

ovl_dir_exists() {
	dir_exists "$(ovl_get_root)/${1#/}"
}

ovl_dir_not_exists() {
	dir_not_exists "$(ovl_get_root)/${1#/}"
}


# Usage: targz_dir <output.tar.gz> <source directory> [<source objects>]
targz_dir() {
	local output_file="$1"
	local source_dir="$2"
	shift 2

	dir_is_writable "${output_file%/*}" || ! warning "targz_dir: Can not create writeable directory: '${outputfile%/*}'" || return 1

	tar -c --numeric-owner --xattrs -C "$source_dir" "$@" | gzip -9n > "$output_file"
}

ovl_targz_create() {
	local _name="$1"
	local _dir="$2"
	shift 2

	local _err=0
	ovl_fkrt_enable
	(	targz_dir "${DESTDIR%/}/${_name##*/}.apkovl.tar.gz" "$_dir" "$@" ) || _err=1
	ovl_fkrt_disable

	return $_err
}


# Create file with specified owner and mode taking content from stdin.
# Usage: '<cmd> | ovl_create_file <file> <owner> <mode>'
#      : ovl_create_file <file> <owner> <mode>' <<-EOF
#      :     [HERE DOCUMENT]
#      : EOF

ovl_create_file() {
	local owner perms file filename filedir _err
	owner="$1"
	perms="$2"
	file="${3}"
	file="$(ovl_get_root)/${file#/}"
	filename="${file##*/}"
	filedir="${file%$filename}"
	_err=0

	ovl_fkrt_enable
	(	( mkdir_is_writable "$filedir" || ! warning "ovl_create_file: Could not create writable directory: '$filedir'" ) \
			&& cat > "${filedir%/}/$filename" \
			&& chown "$owner" "$file" \
			&& chmod "$perms" "$file"
	) || _err=1
	ovl_fkrt_disable

	[ "$_err" -eq 0 ] || warning "ovl_create_file: Failed to create '$file'"
	return $_err
}

# Append content from stdin to file.
# Usage: '<cmd> | ovl_append_file <file>'
#      : ovl_append_file <file>' <<-EOF
#      :     [HERE DOCUMENT]
#      : EOF

ovl_append_file() {
	local file filename filedir _err
	file="${1}"
	file="$(ovl_get_root)/${file#/}"
	filename="${file##*/}"
	filedir="${file%$filename}"
	_err=0

	ovl_fkrt_enable
	(	( mkdir_is_writable "$filedir" || ! warning "ovl_append_file: Could not create writable directory: '$filedir'" ) \
		&& cat >> "${filedir%/}/$filename"
	) || _err=1
	ovl_fkrt_disable

	[ "$_err" -eq 0 ] || warning "ovl_append_file: Failed to append to '$file'"
	return $_err
}


# Directories and links to be treated as directories must be specified with trailing slash
# Files and links to be created or overwritten without trailing slash
# i.e. ovl_ln /usr/include/ /opt/include
ovl_create_link() {
	local target targetname targetdir link linkname linkdir _err

	target="$1"
	targetname="${target##*/}"
	targetdir="${target%$targetname}"
	targetdir="${targetdir%/}"

	link="$2"
	linkname="${link##*/}"
	linkdir="${link%$linkname}"
	linkdir="${linkdir%/}"


	# If only link name given, create link with that name in target directory.
	[ "$linkdir" ] || linkdir="$targetdir"

	# If only link directory given, use target name as link name.
	[ "$linkname" ] || linkname="$targetname"

	# If both arguments are directories, use last portion of target directory as link name.
	[ ! "$targetname" ] && [ ! "$linkname" ] && linkname="${targetdir##*/}"

	# If neither argument has a directory component still, check if $PWD is within the overlay, othewise bail.
	if [ ! "$targetdir" ] && [ ! "$linkdir" ] ; then
		local mypwd="$(realpath "$PWD")"
		if [ "${mypwd#$(ovl_get_root)}" != "$mypwd" ] ; then 
			linkdir="${mypwd%/}"
		else
			warning "ovl_ln called with argument that could not be resolved: target:'$1' link:'$2'."
			return 1
		fi
	else
		# Prepend overlay root to linkdir.
		linkdir="$(ovl_get_root)/${linkdir#/}"
	fi

	# Build our link:

	link="${linkdir%/}/$linkname"
	

	_err=0
	ovl_fkrt_enable 
	(	( mkdir_is_writable "$linkdir" || ! warning: "ovl_create_link: Could not create writable directory: '$linkdir'" ) \
			&& ln -sfT "${target%/}" "$link"
	) || _err=1
	ovl_fkrt_disable

	[ "$_err" -eq 0 ] || warning "ovl_create_link: Failed to create link: '$link' --> '$target'"
	return $_err
}


ovl_cat() {
	local _err=0
	ovl_fkrt_enable
	(	printf "%s\n" "$@" | sed -e "/^-$/b; s/^/$(ovl_get_root)" | xargs cat ) || _err=1
	ovl_fkrt_disable

	return $_err
}

# Call sed -i with specified arguments on file specified.
# Usage: ovl_edit_file_sed <file> <sed options and commands>
ovl_edit_file_sed() {
	local _file _realfile _err
	_file="$1"
	shift

	_realfile="$(ovl_get_root)/${_file#/}"

	file_is_writable "$_realfile" && _realfile="$(realpath "$_realfile")" \
		|| ! warning "ovl_edit_file_sed: Can not write to file: '$_realfile'" \
		|| return 1

	_err=0
	ovl_fkrt_enable
	(	printf "%s" "$_realfile" | xargs sed -i "$@" ) || _err=1
	ovl_fkrt_disable

	return $_err
}


ovl_mkdir() {
	local opts _err
	opts=""
	while [ "$1" != "${1#-}" ] ; do opts="${opts:+$opts }$1" ; shift ; done

	_err=0
	ovl_fkrt_enable
	(	printf "$(ovl_get_root)/%s\\n" "${@#/}" | xargs mkdir $opts ) || _err=1
	ovl_fkrt_disable

	return $_err
}


ovl_rm() {
	local opts _err
	opts=""
	while [ "$1" != "${1#-}" ] ; do opts="$opts $1" ; shift ; done

	_err=0
	ovl_fkrt_enable
	(	printf "$(ovl_get_root)/%s\\n" "${@#/}" | xargs rm $opts ) || _err=1
	ovl_fkrt_disable

	return $_err
}


ovl_ln() {
	local output outdir opts _err

	output="$(ovl_get_root)/$(eval "echo \${$##/}")"
	outdir="${outdir%${outdir##*/}}"

	opts=""
	while [ "$1" != "${1#-}" ] ; do opts="$opts $1" ; shift ; done

	_err=0
	ovl_fkrt_enable
	(	( mkdir_is_writable "$outdir" || ! warning "ovl_ln: Can not create writable directory: '$outdir'" ) \
			&& printf "$(ovl_get_root)/%s\\n" "${@#/}" | xargs ln $opts
	) || _err=1
	ovl_fkrt_disable

	return $_err
}


ovl_cp() {
	local output outdir opts _err

	output="$(ovl_get_root)/$(eval "echo \${$##/}")"
	outdir="${outdir%${outdir##*/}}"

	opts=""
	while [ "$1" != "${1#-}" ] ; do opts="$opts $1" ; shift ; done

	_err=0
	ovl_fkrt_enable
	(	( mkdir_is_writable "$outdir" || ! warning "ovl_cp: Can not create writable directory: '$outdir'" ) \
			&& printf "$(ovl_get_root)/%s\\n" "${@#/}" | xargs cp $opts
	) || _err=1
	ovl_fkrt_disable

	return $_err
}


ovl_mv() {
	local output outdir opts _err

	output="$(ovl_get_root)/$(eval "echo \${$##/}")"
	outdir="${outdir%${outdir##*/}}"

	opts=""
	while [ "$1" != "${1#-}" ] ; do opts="$opts $1" ; shift ; done

	_err=0
	ovl_fkrt_enable
	(	( mkdir_is_writable "$outdir" || ! warning "ovl_mv: Can not create writable directory: '$outdir'" ) \
			&& printf "$(ovl_get_root)/%s\\n" "${@#/}" | xargs mv $opts
	) || _err=1
	ovl_fkrt_disable

	return $_err
}


ovl_chown() {
	local opts owner _err
	opts=""
	while [ "$1" != "${1#-}" ] ; do opts="$opts $1" ; shift ; done

	owner="$1"
	shift

	_err=0
	ovl_fkrt_enable
	(	printf "$(ovl_get_root)/%s\\n" "${@#/}" | xargs chown $opts "$owner" ) || _err=1
	ovl_fkrt_disable

	return $_err
}


ovl_chmod() {
	local opts perms _err
	opts=""
	while [ "$1" != "${1#-}" ] ; do opts="$opts $1" ; shift ; done
	
	perms="$1"
	shift

	_err=0
	ovl_fkrt_enable
	( 	printf "$(ovl_get_root)/%s\\n" "${@#/}" | xargs chmod $opts $perms ) || _err=1
	ovl_fkrt_disable

	return $_err
}

ovl_runlevel_add() {
	local _lvl="$1"
	local _srv
	shift
	local outdir="$(ovl_get_root)/etc/runlevels/$_lvl/" 
	mkdir_is_writable "$outdir" || ! warning "ovl_runlevl_add: Can not create writable directory: '$outdir'" || return 1
	for _srv in "$@" ; do
		ln -sfT "/etc/init.d/$_srv" "$outdir/$_srv" \
			|| ! warning "ovl_runlevel_add: Could not create link '$outdir/$srv' --> '/etc/init.d/$_srv'" || return 1
	done
}

ovl_conf_d_file_setting() {
	ovl_conf_file_setting_add_or_replace "/etc/conf.d/$1" "$2" "$3"
}

# TODO: overlays - Move conf_file_add_or_replace functionality to more general util.
ovl_conf_file_setting_add_or_replace() {
	local _file="$1"
	local _key="$2"
	local _v="$3"
	local _old="${_key}="
	local _new="${_key}=\"${_v}\""

	[ "$_file" ] || ! warning "ovl_conf_file_setting_add_or_replace called with no file!" || return 1

	if ovl_file_not_exists "$_file" ; then
		( printf '# %s\n# Generated by mkimage.\n\n# %s\n%s' "$_file" "$_key" "$_new" | ovl_create_file "root:root" "0644" "$_file" ) && return 0
		warning "ovl_conf_file_setting_add_or_replace: Could not create conf file: '$_file'"
		return 1
	fi

	local _err=0
	if grep -q "^${_key}=" "${_file}" ; then
		ovl_edit_file_sed "${_file}" -E -e 's|^('"${_key}"'=.*)|#\1\n'"${_new}"'|' || _err=1
	elif grep -q "^#[[:space:]]*${_new}" "${_file}" ; then
		ovl_edit_file_sed "${_file}" -e "s|^#[[:space:]]*${_key}=.*|${_new}|" || _err=1
	elif grep -q "^#[[:space:]]*${_key}=" "${_file}" ; then
		ovl_edit_file_sed "${_file}" -e '\|^#[[:space:]]*'"${_key}"'=.*|a'"${_new}" || _err=1
	elif grep -q "^#.*${_key}.*" "${_file}" ; then
		ovl_edit_file_sed "${_file}" -e '\|^#.*'"${_key}"'.*|a'"${_new}" || _err=1
	else
		ovl_edit_file_sed "${_file}" -e '$a# '"${_key}" -e '$a'"${_new}" || _err=1
	fi

	return $_err
}
