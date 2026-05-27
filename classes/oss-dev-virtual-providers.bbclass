# oss-dev-virtual-providers.bbclass
#
# When building in OSS_DEV mode (vendor + MW from source), MW recipes
# DEPENDS/RDEPENDS on virtual/vendor-* but vendor recipes don't declare
# PROVIDES for them (staging-ipk handles this in feed mode).
#
# This class auto-generates PROVIDES and RPROVIDES from existing
# PREFERRED_PROVIDER_virtual/* mappings in preferred_provider.inc.

python () {
    if d.getVar('OSS_LAYER_BUILD_TYPE') != 'OSS_DEV':
        return

    pn = d.getVar('PN')
    if not pn:
        return

    for key in d.keys():
        if not key.startswith('PREFERRED_PROVIDER_virtual/'):
            continue
        provider = d.getVar(key)
        if provider == pn:
            virtual = key.replace('PREFERRED_PROVIDER_', '')
            # Add build-time provider (for DEPENDS resolution)
            d.appendVar('PROVIDES', ' ' + virtual)
            # Add runtime provider (for RDEPENDS resolution)
            d.appendVar('RPROVIDES:' + pn, ' ' + virtual)
}
