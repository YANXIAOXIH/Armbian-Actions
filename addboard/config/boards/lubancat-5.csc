BOARD_NAME="LubanCat 5"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="SOM3588_defconfig"
KERNEL_TARGET="vendor,current,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588-lubancat-5.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SOC="rk3588"
IMAGE_PARTITION_TABLE="gpt"
function config_image_hook__lubancat-5() {
    # Create udev audio rules
    echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > ${chroot_dir}/etc/udev/rules.d/90-naming-audios.rules
    echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi1-sound", ENV{SOUND_DESCRIPTION}="HDMI1 Audio"' >> ${chroot_dir}/etc/udev/rules.d/90-naming-audios.rules
    echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmiin-sound", ENV{SOUND_DESCRIPTION}="HDMI-In Audio"' >> ${chroot_dir}/etc/udev/rules.d/90-naming-audios.rules
    echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> ${chroot_dir}/etc/udev/rules.d/90-naming-audios.rules
    echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8388-sound", ENV{SOUND_DESCRIPTION}="ES8388 Audio"' >> ${chroot_dir}/etc/udev/rules.d/90-naming-audios.rules

    # Fix WiFi not working when bluetooth enabled for the official RTL8852BE WiFi + BT card
    cp ${overlay_dir}/usr/lib/systemd/system/rtl8852be-reload.service ${chroot_dir}/usr/lib/systemd/system/rtl8852be-reload.service
    chroot ${chroot_dir} /bin/bash -c "systemctl enable rtl8852be-reload"

    # Fix and configure audio device
    mkdir -p ${chroot_dir}/usr/lib/scripts
    cp ${overlay_dir}/usr/lib/scripts/alsa-audio-config ${chroot_dir}/usr/lib/scripts/alsa-audio-config
    cp ${overlay_dir}/usr/lib/systemd/system/alsa-audio-config.service ${chroot_dir}/usr/lib/systemd/system/alsa-audio-config.service
    chroot ${chroot_dir} /bin/bash -c "systemctl enable alsa-audio-config"

    return 0
}
