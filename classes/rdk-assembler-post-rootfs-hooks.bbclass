# RDK Image Post-Rootfs Processing
# This class provides rootfs post-processing functions for RDK images

# Include feature-based filtering configuration
require ../conf/middleware-feature-mapping.conf

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

# Register all post-process commands
ROOTFS_POSTPROCESS_COMMAND += "dobby_generic_config_patch; "
ROOTFS_POSTPROCESS_COMMAND += "create_NM_link; "
ROOTFS_POSTPROCESS_COMMAND += "create_init_link; "
ROOTFS_POSTPROCESS_COMMAND += "${@bb.utils.contains('DISTRO_FEATURES', 'debug-variant', 'wpeframework_binding_patch; ', '', d)}"
ROOTFS_POSTPROCESS_COMMAND += "validate_package_filtering; "

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