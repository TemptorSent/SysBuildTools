initfs_feature_fs_fat() { return 0 ; }

_initfs_feature_fs_fat_modules() {
	cat <<-'EOF'
		kernel/fs/fat/fat.ko
	EOF
}


initfs_feature_fs_vfat() { return 0 ; }

_initfs_feature_fs_vfat_modules() {
	cat <<-'EOF'
		kernel/fs/fat/vfat.ko
	EOF
}

