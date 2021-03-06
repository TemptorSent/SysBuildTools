initfs_feature_md_raid() { return 0 ; }

_initfs_feature_md_raid_modules() {
	cat <<-'EOF'
		kernel/drivers/md/raid*
	EOF

	_initfs_feature_crypto_crc32_modules
}

_initfs_feature_md_raid_pkgs() {
	cat <<-'EOF'
		mdadm
	EOF
}

_initfs_feature_md_raid_files() {
	cat <<-'EOF'
		/etc/mdadm.conf
		/sbin/mdadm
	EOF
}

_initfs_feature_md_raid_hostcfg() {
	cat <<-'EOF'
		/etc/mdadm.conf
	EOF
}
