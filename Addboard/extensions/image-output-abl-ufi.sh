#!/bin/bash

function add_host_dependencies__abl_host_deps() {
    declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} mkbootimg android-sdk-libsparse-utils xz-utils"
}

function post_build_image__900_convert_to_abl_img() {
    display_alert "Starting ABL image conversion" "${EXTENSION}" "info"
    [[ -z "${version}" ]] && exit_with_error "version is not set"
    [[ -n "${UEFI_GRUB_TARGET}" ]] && return 0
    local ORIG_IMG="${DESTIMG}/${version}.img"
    if [[ ! -f "${ORIG_IMG}" && -f "${ORIG_IMG}.xz" ]]; then
        display_alert "Compressed image found, decompressing..." "${EXTENSION}" "info"
        unxz -f "${ORIG_IMG}.xz"
    fi
    local ROOTFS_RAW="${DESTIMG}/${version}.rootfs.raw.img"
    local ROOTFS_SPARSE="${DESTIMG}/${version}.rootfs.img"
    local MOUNT_DIR=$(mktemp -d)
    local BOOT_DIR=$(mktemp -d)
    cleanup() {
        mountpoint -q "${MOUNT_DIR}" && umount -l "${MOUNT_DIR}"
        [[ -n "${LOOP_DEV}" ]] && losetup -d "${LOOP_DEV}" 2>/dev/null
        rm -rf "${MOUNT_DIR}" "${BOOT_DIR}"
        rm -f "${ROOTFS_RAW}"
    }
    trap cleanup ERR EXIT
    local LOOP_DEV=$(losetup -f -P --show "${ORIG_IMG}")
    [[ -z "${LOOP_DEV}" ]] && exit_with_error "Failed to setup loop device"
    mount "${LOOP_DEV}p1" "${MOUNT_DIR}"
    local rootfs_uuid=$(blkid -s UUID -o value "${LOOP_DEV}p1")
    source "${MOUNT_DIR}/boot/armbianEnv.txt"
	declare -g cmdline="${BOOTIMG_CMDLINE_EXTRA} root=UUID=${rootfs_uuid} ${extraargs}"
    local vmlinuz=$(ls -1tr "${MOUNT_DIR}/boot"/vmlinu*-*-* 2>/dev/null | tail -n 1)
    local initrd=$(ls -1tr "${MOUNT_DIR}/boot"/initrd.img-*-* 2>/dev/null | tail -n 1)
    [[ -z "${vmlinuz}" || -z "${initrd}" ]] && exit_with_error "Kernel or initrd not found in image"
    if gzip -t "${vmlinuz}" 2>/dev/null; then
        cp "${vmlinuz}" "${BOOT_DIR}/Image.gz"
    else
        gzip -9 -c "${vmlinuz}" > "${BOOT_DIR}/Image.gz"
    fi
    if [[ ${#ABL_DTB_LIST[@]} -gt 0 ]]; then
        for dtb_name in "${ABL_DTB_LIST[@]}"; do
            local dtb_file=$(find "${MOUNT_DIR}/usr/lib/" -name "${dtb_name}.dtb" | head -n 1)
            [[ -z "$dtb_file" ]] && { display_alert "DTB ${dtb_name} not found, skipping" "" "warning"; continue; }
            cat "${BOOT_DIR}/Image.gz" "${dtb_file}" > "${BOOT_DIR}/kernel-dtb-${dtb_name}"
            mkbootimg \
                --base 0x80000000 \
                --kernel_offset 0x00080000 \
                --ramdisk_offset 0x04000000 \
                --tags_offset 0x03500000 \
                --pagesize 2048 \
                --second_offset 0x00f00000 \
                --ramdisk "${initrd}" \
                --cmdline "${cmdline}" \
                --kernel "${BOOT_DIR}/kernel-dtb-${dtb_name}" \
                -o "${DESTIMG}/${version}.boot_${dtb_name}.img"
                
        done
    else
        display_alert "ABL_DTB_LIST is empty, no boot.img will be generated." "" "warning"
    fi
    dd if="${LOOP_DEV}p1" of="${ROOTFS_RAW}" bs=4M status=none
    umount "${MOUNT_DIR}"
    losetup -d "${LOOP_DEV}"
    unset LOOP_DEV
    e2fsck -p -f "${ROOTFS_RAW}" || [[ $? -lt 4 ]]
    resize2fs -M "${ROOTFS_RAW}"
    local block_count=$(dumpe2fs -h "${ROOTFS_RAW}" 2>/dev/null | awk '/Block count:/{print $3}')
    local block_size=$(dumpe2fs -h "${ROOTFS_RAW}" 2>/dev/null | awk '/Block size:/{print $3}')
    truncate -s $((block_count * block_size)) "${ROOTFS_RAW}"
    img2simg "${ROOTFS_RAW}" "${ROOTFS_SPARSE}"
    rm -f "${ROOTFS_RAW}"
    local FLASHER_SRC="${SRC}/packages/bsp/UFI001C/Flasher"
    if [[ -d "${FLASHER_SRC}" ]]; then
        local PACK_DIR=$(mktemp -d)
        mkdir -p "${PACK_DIR}/images"
        cp -r "${FLASHER_SRC}"/* "${PACK_DIR}/"
        shopt -s nullglob
        mv "${DESTIMG}/${version}.boot_"*.img* "${PACK_DIR}/images/" 2>/dev/null
        mv "${ROOTFS_SPARSE}"* "${PACK_DIR}/images/" 2>/dev/null
        shopt -u nullglob
        local final_archive="${DESTIMG}/${version}.tar"
        tar -cf "${final_archive}" -C "${PACK_DIR}" .
        rm -f "${ORIG_IMG}"
        rm -rf "${PACK_DIR}"
    fi

    return 0
}