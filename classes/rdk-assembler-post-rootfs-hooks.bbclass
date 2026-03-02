# RDK Image Post-Rootfs Processing
# This class provides rootfs post-processing functions for RDK images

# Include feature-based filtering configuration
require ../conf/middleware-feature-mapping.conf
require ../conf/middleware-file-filter.conf

# Middleware Package Filtering - determines which packages to exclude based on DISTRO_FEATURES
python () {
    """
    Filter middleware packages based on DISTRO_FEATURES
    """
    import bb
    
    distro_features = set((d.getVar('DISTRO_FEATURES') or '').split())
    available_features = (d.getVar('MIDDLEWARE_AVAILABLE_FEATURES') or '').split()
    
    bb.note('=== Middleware Feature Filtering ===')
    bb.note('Available features to filter: %s' % ', '.join(available_features))
    bb.note('Current DISTRO_FEATURES: %s' % ' '.join(sorted(distro_features)))
    
    packages_to_exclude = []
    
    for feature in available_features:
        required_distro_feature = d.getVar('MIDDLEWARE_FEATURE_' + feature)
        feature_packages = d.getVar('MIDDLEWARE_FEATURE_' + feature + '_PACKAGES')
        
        if not required_distro_feature or not feature_packages:
            bb.note('Skipping feature "%s" - no configuration found' % feature)
            continue
        
        feature_packages_list = feature_packages.split()
        
        if required_distro_feature in distro_features:
            bb.note('✓ Feature "%s" ENABLED (DISTRO_FEATURE "%s" present) - keeping packages: %s' % 
                   (feature, required_distro_feature, ', '.join(feature_packages_list)))
        else:
            bb.note('✗ Feature "%s" DISABLED (DISTRO_FEATURE "%s" missing) - excluding packages: %s' % 
                   (feature, required_distro_feature, ', '.join(feature_packages_list)))
            packages_to_exclude.extend(feature_packages_list)
    
    packages_str = ' '.join(packages_to_exclude)
    d.setVar('MIDDLEWARE_PACKAGES_TO_EXCLUDE', packages_str)
    
    if packages_to_exclude:
        bb.note('=== Final exclusion list: %s ===' % packages_str)
    else:
        bb.note('=== No packages to exclude ===')
}

# Middleware File Filtering - determines which files to remove from rootfs
python () {
    """
    Determine which files should be removed from rootfs based on missing DISTRO_FEATURES
    """
    import bb
    
    distro_features = set((d.getVar('DISTRO_FEATURES') or '').split())
    available_features = (d.getVar('MIDDLEWARE_FILE_FILTER_FEATURES') or '').split()
    
    bb.note('=== Middleware File Filtering ===')
    bb.note('Available file filter features: %s' % ', '.join(available_features))
    bb.note('Current DISTRO_FEATURES: %s' % ' '.join(sorted(distro_features)))
    
    files_to_remove = []
    
    for feature in available_features:
        required_distro_feature = d.getVar('MIDDLEWARE_FILE_FILTER_' + feature)
        feature_files = d.getVar('MIDDLEWARE_FILE_FILTER_' + feature + '_FILES')
        
        if not required_distro_feature or not feature_files:
            bb.note('Skipping file filter "%s" - no configuration found' % feature)
            continue
        
        file_patterns = feature_files.split()
        
        if required_distro_feature in distro_features:
            bb.note('✓ File filter "%s" KEEPING files (DISTRO_FEATURE "%s" present)' % 
                   (feature, required_distro_feature))
        else:
            patterns_preview = ', '.join(file_patterns[:3]) + ('...' if len(file_patterns) > 3 else '')
            bb.note('✗ File filter "%s" REMOVING files (DISTRO_FEATURE "%s" missing): %s' % 
                   (feature, required_distro_feature, patterns_preview))
            files_to_remove.extend(file_patterns)
    
    files_str = ' '.join(files_to_remove)
    d.setVar('MIDDLEWARE_FILES_TO_REMOVE', files_str)
    
    if files_to_remove:
        bb.note('=== Files marked for removal: %d patterns ===' % len(files_to_remove))
        bb.note('=== File patterns: %s ===' % (', '.join(files_to_remove[:5]) + ('...' if len(files_to_remove) > 5 else '')))
    else:
        bb.note('=== No files to remove ===')
}

# Register all post-process commands
ROOTFS_POSTPROCESS_COMMAND += "dobby_generic_config_patch; "
ROOTFS_POSTPROCESS_COMMAND += "create_NM_link; "
ROOTFS_POSTPROCESS_COMMAND += "create_init_link; "
ROOTFS_POSTPROCESS_COMMAND += "${@bb.utils.contains('DISTRO_FEATURES', 'debug-variant', 'wpeframework_binding_patch; ', '', d)}"
ROOTFS_POSTPROCESS_COMMAND += "validate_package_filtering; "
ROOTFS_POSTPROCESS_COMMAND += "remove_feature_filtered_files; "

# Validate that package filtering worked correctly
validate_package_filtering() {
    bbnote "=== Validating package exclusion filtering ==="
    
    if [ -z "${MIDDLEWARE_PACKAGES_TO_EXCLUDE}" ]; then
        bbnote "No packages were marked for exclusion"
        return 0
    fi
    
    bbnote "Checking if excluded packages are absent: ${MIDDLEWARE_PACKAGES_TO_EXCLUDE}"
    
    # Get list of installed packages from opkg status file
    local status_file="${IMAGE_ROOTFS}${OPKGLIBDIR}/opkg/status"
    if [ ! -f "$status_file" ]; then
        # Try alternative location
        status_file="${IMAGE_ROOTFS}/usr/lib/opkg/status"
    fi
    
    if [ ! -f "$status_file" ]; then
        bbwarn "Cannot validate package filtering - opkg status file not found"
        return 0
    fi
    
    local installed_excluded=""
    local validation_failed=false
    
    for pkg in ${MIDDLEWARE_PACKAGES_TO_EXCLUDE}; do
        # Check if package is listed in opkg status (use fixed-string grep to avoid regex issues)
        if grep -qF "Package: $pkg" "$status_file" 2>/dev/null; then
            installed_excluded="$installed_excluded $pkg"
            validation_failed=true
        fi
    done
    
    if [ "$validation_failed" = "true" ]; then
        bbwarn "================================================"
        bbwarn "PACKAGE FILTERING FAILED!"
        bbwarn "================================================"
        bbwarn "The following packages should have been excluded but are still installed:"
        for pkg in $installed_excluded; do
            bbwarn "  - $pkg"
        done
        bbwarn ""
        bbwarn "This usually means the package is added as RDEPENDS instead of RRECOMMENDS."
        bbwarn "BAD_RECOMMENDATIONS only works for packages listed as RRECOMMENDS."
        bbwarn ""
        bbwarn "================================================"
    else
        bbnote "✓ Package filtering validation passed - all excluded packages are absent"
    fi
}

create_init_link() {
    ln -sf /sbin/init ${IMAGE_ROOTFS}/init
}

# Required for NetworkManager
create_NM_link() {
    touch ${R}/etc/resolv.conf
    echo "nameserver 127.0.0.1" > ${R}/etc/resolv.conf
    echo "options timeout:1" >> ${R}/etc/resolv.conf
    echo "options attempts:2" >> ${R}/etc/resolv.conf
    ln -sf /var/run/NetworkManager/no-stub-resolv.conf ${R}/etc/resolv.dnsmasq
}

# If vendor layer provides dobby configuration, then remove the generic config
dobby_generic_config_patch(){
    if [ -f "${IMAGE_ROOTFS}/etc/dobby.generic.json" ]; then
        if [ -f "${IMAGE_ROOTFS}/etc/dobby.json" ]; then
            rm ${IMAGE_ROOTFS}/etc/dobby.generic.json
        else
            mv ${IMAGE_ROOTFS}/etc/dobby.generic.json ${IMAGE_ROOTFS}/etc/dobby.json
        fi
    fi
}

wpeframework_binding_patch(){
    sed -i "s/127.0.0.1/0.0.0.0/g" ${IMAGE_ROOTFS}/etc/WPEFramework/config.json
}

# Validate file pattern to prevent command injection
validate_file_pattern() {
    local pattern="$1"
    # Allow only safe characters: alphanumeric, forward slash, asterisk, dot, dash, underscore
    # This prevents command substitution (e.g., $(command), `command`) and other shell metacharacters
    if echo "$pattern" | grep -qE '[^a-zA-Z0-9/_.*-]'; then
        return 1
    fi
    return 0
}

# Remove files from installed packages based on DISTRO_FEATURES
remove_feature_filtered_files() {
    bbnote "=== Starting feature-based file removal ==="
    bbnote "MIDDLEWARE_FILES_TO_REMOVE: '${MIDDLEWARE_FILES_TO_REMOVE}'"
    
    if [ -z "${MIDDLEWARE_FILES_TO_REMOVE}" ]; then
        bbnote "No files to remove (MIDDLEWARE_FILES_TO_REMOVE is empty)"
        return 0
    fi
    
    bbnote "Files to remove: ${MIDDLEWARE_FILES_TO_REMOVE}"
    
    for file_pattern in ${MIDDLEWARE_FILES_TO_REMOVE}; do
        bbnote "Processing pattern: $file_pattern"
        
        # Validate pattern to prevent command injection
        if ! validate_file_pattern "$file_pattern"; then
            bbwarn "Skipping invalid file pattern (contains unsafe characters): $file_pattern"
            continue
        fi
        
        # Use find with wildcards to handle glob patterns
        if echo "$file_pattern" | grep -q '\*'; then
            # Pattern contains wildcard, use find
            found_files=$(find ${IMAGE_ROOTFS} -path "${IMAGE_ROOTFS}$file_pattern" 2>/dev/null || true)
            if [ -n "$found_files" ]; then
                find ${IMAGE_ROOTFS} -path "${IMAGE_ROOTFS}$file_pattern" -exec rm -f {} \; 2>/dev/null || true
                bbnote "  Removed files matching: $file_pattern"
            else
                bbnote "  No files found matching: $file_pattern"
            fi
        else
            # Exact path
            if [ -e "${IMAGE_ROOTFS}$file_pattern" ] || [ -L "${IMAGE_ROOTFS}$file_pattern" ]; then
                rm -rf "${IMAGE_ROOTFS}$file_pattern"
                bbnote "  Removed: $file_pattern"
            else
                bbnote "  File not found: $file_pattern"
            fi
        fi
    done
    
    # Remove empty directories
    bbnote "Cleaning up empty directories..."
    find ${IMAGE_ROOTFS}/usr/share/WPEFramework -type d -empty -delete 2>/dev/null || true
    find ${IMAGE_ROOTFS}/etc/WPEFramework -type d -empty -delete 2>/dev/null || true
    find ${IMAGE_ROOTFS}/usr/lib/wpeframework -type d -empty -delete 2>/dev/null || true
    
    bbnote "=== Feature-filtered file removal complete ==="
}