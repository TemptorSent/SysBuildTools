initfs_fs_squashfs() {
	return 0
}

_initfs_fs_squashfs_modules() {
	cat <<-'EOF'
		kernel/fs/squashfs/
	EOF
}
