SUMMARY = "A image just capable of allowing a device to boot."
LICENSE = "MIT"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

IMAGE_LINGUAS = " "

IMAGE_INSTALL = " \
                 packagegroup-vendor-layer \
                 packagegroup-middleware-layer \
                 packagegroup-application-layer \
                 "

IMAGE_FSTYPES += "ext4"
IMAGE_INSTALL += "volatile-binds"
IMAGE_INSTALL:remove = "linux-meson"

inherit core-image custom-rootfs-creation

IMAGE_ROOTFS_SIZE ?= "8192"
IMAGE_ROOTFS_EXTRA_SPACE:append = "${@bb.utils.contains("DISTRO_FEATURES", "systemd", " + 4096", "" ,d)}"

ROOTFS_POSTPROCESS_COMMAND += "dobby_generic_config_patch; "
ROOTFS_POSTPROCESS_COMMAND += "create_NM_link; "
ROOTFS_POSTPROCESS_COMMAND += "create_init_link; "
ROOTFS_POSTPROCESS_COMMAND += "wpeframework_binding_patch; "

create_init_link() {
        ln -sf /sbin/init ${IMAGE_ROOTFS}/init
}

# Required for NetworkManager
create_NM_link() {
        if ${@bb.utils.contains("DISTRO_FEATURES", "ENABLE_NETWORKMANAGER", "true", "false", d)}; then
            ln -sf /var/run/NetworkManager/no-stub-resolv.conf ${IMAGE_ROOTFS}/etc/resolv.dnsmasq
            ln -sf /var/run/NetworkManager/resolv.conf ${IMAGE_ROOTFS}/etc/resolv.conf
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
