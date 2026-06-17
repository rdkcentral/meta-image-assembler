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
# BAD_RECOMMENDATIONS prevents installation of packages that are only RRECOMMENDS
# this is used to remove packages provided by middleware feed but not needed on the actual product.
BAD_RECOMMENDATIONS += "${MIDDLEWARE_PACKAGES_TO_EXCLUDE}"

IMAGE_FSTYPES += "ext4 tar.gz"
IMAGE_INSTALL += "volatile-binds"
IMAGE_INSTALL:remove = "linux-meson"

inherit core-image custom-rootfs-creation rdk-assembler-post-rootfs-hooks

IMAGE_ROOTFS_SIZE ?= "8192"
IMAGE_ROOTFS_EXTRA_SPACE:append = "${@bb.utils.contains("DISTRO_FEATURES", "systemd", " + 4096", "" ,d)}"
