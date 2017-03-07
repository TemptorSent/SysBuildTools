# ZFS filesystem feature.
# Enables mkinitfs "zfs" feature by default use enable_rootfs_zfs="false" to disable.
feature_zfs() {

	enable_rootfs_zfs="${enable_rootfs_zfs:=true}"
	
	if [ "$enable_rootfs_zfs" = "true" ] ; then
		add_initfs_apks "zfs"
		add_initfs_apks_flavored "spl zfs"
		add_initfs_features "zfs"
		add_rootfs_apks "udev zfs zfs-udev"
		add_overlays "zfs"
	else
		apks_flavored "spl zfs"
		add_apks "udev zfs zfs-udev"
	fi

}
