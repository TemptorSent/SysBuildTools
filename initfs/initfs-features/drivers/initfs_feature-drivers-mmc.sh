initfs_feature_drivers_mmc() { return 0 ; }

_initfs_feature_drivers_mmc_modules() {
	cat <<-'EOF'
		kernel/drivers/mmc/
	EOF
}

