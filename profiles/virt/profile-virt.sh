profile_virt() {
	set_profile_base_type "virtio"
	add_archs "x86_64 aarch64"
	profile_base
	append_kernel_cmdline "console=tty0 console=ttyS0,115200"
	set_syslinux_serial "0 115200"
	imagetype_iso
}
