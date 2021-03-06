overlay_base() {
	_call="ovl_script_base"
}


ovl_script_base() {
	# TODO: overlay_base - Split into appropriate common overlays.
	ovl_runlevel_add sysinit devfs dmesg mdev hwdrivers modloop
	ovl_runlevel_add boot hwclock modules sysctl hostname bootmisc syslog
	ovl_runlevel_add shutdown mount-ro killprocs savecache

	ovl_create_file root:root 0644 /etc/hostname <<-EOF
	$HOSTNAME
	EOF

	if ovl_file_not_exists "/etc/network/interfaces" ; then
		ovl_create_file root:root 0644 "/etc/network/interfaces" <<-EOF
		auto lo
		iface lo inet loopback
		EOF
	fi
}
