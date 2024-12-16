BOARD_NAME="LubanCat 5"
BOARD_MAKER="LubanCat"
UBOOT_PACKAGE="u-boot-lubancat-rk3588"
DEVICE_TREE_FILE="rk3588-lubancat-5.dtb"
OVERLAY_PREFIX="rk3588"
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