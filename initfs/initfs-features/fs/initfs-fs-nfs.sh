initfs_fs_nfs_all() {
	initfs_fs_nfs
	initfs_fs_nfsd
}



initfs_fs_nfs() {
	return 0
}

_initfs_fs_nfs_modules() {
	cat <<-EOF
		kernel/fs/nfs/
	EOF
}

_initfs_fs_nfs_files() { return 0 ; }



initfs_fs_nfsd() {
	return 0
}

_initfs_fs_nfsd_modules() {
	cat <<-EOF
		kernel/fs/nfsd/
	EOF
}

_initfs_fs_nfsd_files() { return 0 ; }
