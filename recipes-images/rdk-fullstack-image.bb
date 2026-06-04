SUMMARY = "A image just capable of allowing a device to boot."
LICENSE = "MIT"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

IMAGE_LINGUAS = " "

DEPENDS += "nss-native"

IMAGE_INSTALL = " \
                 packagegroup-vendor-layer \
                 packagegroup-middleware-layer \
                 packagegroup-application-layer \
                 "

IMAGE_FSTYPES += "ext4 tar.gz"
IMAGE_INSTALL += "volatile-binds"
IMAGE_INSTALL:remove = "linux-meson"

inherit core-image custom-rootfs-creation

IMAGE_ROOTFS_SIZE ?= "8192"
IMAGE_ROOTFS_EXTRA_SPACE:append = "${@bb.utils.contains("DISTRO_FEATURES", "systemd", " + 4096", "" ,d)}"

ROOTFS_POSTPROCESS_COMMAND += "dobby_generic_config_patch; "
ROOTFS_POSTPROCESS_COMMAND += "create_NM_link; "
ROOTFS_POSTPROCESS_COMMAND += "create_init_link; "
ROOTFS_POSTPROCESS_COMMAND += "setup_core_dumps; "
ROOTFS_POSTPROCESS_COMMAND += "enable_gst_debug; "
ROOTFS_POSTPROCESS_COMMAND += "${@bb.utils.contains('DISTRO_FEATURES', 'debug-variant', 'wpeframework_binding_patch; ', '', d)}"

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

    if [ -f "${R}/lib/systemd/system/NetworkManager.service" ]; then
        sed -i 's/\/opt\/NetworkManager/\/opt\/secure\/NetworkManager/g' ${R}/lib/systemd/system/NetworkManager.service
    fi

    if [ -L "${R}/etc/NetworkManager/system-connections" ]; then
        rm -f ${R}/etc/NetworkManager/system-connections
        ln -s /opt/secure/NetworkManager/system-connections ${R}/etc/NetworkManager/
    fi
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

# Setup core dump configuration
setup_core_dumps(){
    mkdir -p ${IMAGE_ROOTFS}/lib/systemd/system
    mkdir -p ${IMAGE_ROOTFS}/lib/rdk/
    mkdir -p ${IMAGE_ROOTFS}/etc/systemd/system/multi-user.target.wants

    install -m 0644 ${THISDIR}/files/core-dumps-setup.service ${IMAGE_ROOTFS}/lib/systemd/system/
    install -m 0755 ${THISDIR}/files/setup-core-dumps.sh ${IMAGE_ROOTFS}/lib/rdk/

    # Enable the service to run on boot
    ln -sf /lib/systemd/system/core-dumps-setup.service ${IMAGE_ROOTFS}/etc/systemd/system/multi-user.target.wants/core-dumps-setup.service
}

# Enable GST_DEBUG=5 in configuration files
enable_gst_debug(){
    # Enable GST_DEBUG=5 in aisettings.json extraEnvVars
    sed -i '/"apps": {/a\    "extraEnvVars": ["GST_DEBUG=5"],' ${IMAGE_ROOTFS}/etc/sky/aisettings.json

    # Enable GST_DEBUG=5 in rialto-config.json environmentVariables
    sed -i 's/"environmentVariables" : \[/"environmentVariables" : ["GST_DEBUG=5",/' ${IMAGE_ROOTFS}/etc/sky/rialto-config.json
}
