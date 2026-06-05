# oss-dev-virtual-providers.bbclass
#
# When building in OSS_DEV mode (vendor + MW from source), MW recipes
# DEPENDS/RDEPENDS on virtual/vendor-* but vendor recipes don't declare
# PROVIDES for them (staging-ipk handles this in feed mode).
#
# This class auto-generates PROVIDES and RPROVIDES from existing
# PREFERRED_PROVIDER_virtual/* mappings in preferred_provider.inc.
#
# It also makes selected recipes' do_install a no-op when a vendor recipe
# installs the same files (prevents sysroot conflicts in
# do_prepare_recipe_sysroot). The recipes still parse and satisfy DEPENDS,
# but they install nothing.
#
# For recipes where the full MW version installs headers also provided by a
# halif-headers recipe, OSS_DEV_STRIP_HEADERS lists the files to remove
# from the MW recipe's ${D} after do_install, avoiding circular deps.

# Shell postfunc: remove duplicate headers from ${D} after do_install.
# Attached automatically for recipes that set OSS_DEV_STRIP_HEADERS.
oss_dev_strip_duplicate_headers() {
    for f in ${OSS_DEV_STRIP_HEADERS}; do
        rm -f "${D}${f}"
    done
}

python () {
    if d.getVar('OSS_LAYER_BUILD_TYPE') != 'OSS_DEV':
        return

    pn = d.getVar('PN')
    if not pn:
        return

    # Skip do_install for recipes whose output conflicts with another recipe
    # in the sysroot (e.g. halif-headers vs full MW, or MW ermgr vs vendor essosrmgr).
    # Only noexec do_install — other tasks (do_populate_sysroot, do_package,
    # do_packagedata) must still run so sstate manifests are created for
    # dependent recipes. Clear SYSTEMD_SERVICE so do_package doesn't fail
    # looking for service files that weren't installed.
    noop_list = (d.getVar('OSS_DEV_HALIF_HEADERS_NOOP') or '').split()
    noop_list += (d.getVar('OSS_DEV_INSTALL_NOOP') or '').split()
    if pn in noop_list:
        d.setVarFlag('do_install', 'noexec', '1')
        d.setVar('SYSTEMD_SERVICE:' + pn, '')
        d.setVar('INITSCRIPT_NAME', '')

    # For MW recipes that install headers also shipped by a halif-headers
    # recipe, strip those headers after do_install so both recipes can
    # coexist in the sysroot without conflicts.  This avoids the circular
    # dependency that would result from redirecting the halif-headers
    # consumers to DEPENDS on the full MW recipe.
    strip_files = (d.getVar('OSS_DEV_STRIP_HEADERS') or '').split()
    if strip_files:
        d.appendVarFlag('do_install', 'postfuncs', ' oss_dev_strip_duplicate_headers')

    # Collect virtuals first, then sort for deterministic PROVIDES order
    # (d.keys() iteration is non-deterministic and causes task hash changes)
    virtuals = []
    for key in d.keys():
        if not key.startswith('PREFERRED_PROVIDER_virtual/'):
            continue
        provider = d.getVar(key)
        if provider == pn:
            virtuals.append(key.replace('PREFERRED_PROVIDER_', ''))

    for virtual in sorted(virtuals):
        # Add build-time provider (for DEPENDS resolution)
        d.appendVar('PROVIDES', ' ' + virtual)
        # Add runtime provider (for RDEPENDS resolution)
        d.appendVar('RPROVIDES:' + pn, ' ' + virtual)
}
