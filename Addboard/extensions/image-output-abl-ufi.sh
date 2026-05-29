#!/bin/bash

function add_host_dependencies__abl_host_deps() {
    # Append required packages for processing sparse images and decompression
    declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} android-sdk-libsparse-utils xz-utils"

    # Check and install mkbootimg tool if missing on the build host
    if [[ ! -x "/usr/local/bin/mkbootimg" ]]; then
        display_alert "UFI Build" "Downloading compatible mkbootimg..." "info"
        mkdir -p /usr/local/bin
        if wget -q -O /usr/local/bin/mkbootimg https://launchpadlibrarian.net/810765814/mkbootimg; then
            chmod +x /usr/local/bin/mkbootimg
            display_alert "UFI Build" "mkbootimg installed successfully" "info"
        else
            exit_with_error "Failed to download mkbootimg. Build cannot proceed."
        fi
    fi
}

function post_build_image__900_convert_to_abl_img() {
    display_alert "Image Processing" "Starting ABL image conversion" "info"
    
    # Validation & Preparation
    [[ -z "${version}" ]] && exit_with_error "Build version variable is not set"
    [[ -n "${UEFI_GRUB_TARGET}" ]] && return 0 # Skip if UEFI target

    local ORIG_IMG="${DESTIMG}/${version}.img"
    if [[ ! -f "${ORIG_IMG}" && -f "${ORIG_IMG}.xz" ]]; then
        display_alert "Image Processing" "Compressed image found, decompressing..." "info"
        unxz -f "${ORIG_IMG}.xz"
    fi

    local ROOTFS_RAW="${DESTIMG}/${version}.rootfs.raw.img"
    local ROOTFS_SPARSE="${DESTIMG}/${version}.rootfs.img"
    local MOUNT_DIR=$(mktemp -d)
    local BOOT_DIR=$(mktemp -d)

    # Cleanup function to ensure loop devices and mounts are released on exit or error
    cleanup_abl_conversion() {
        mountpoint -q "${MOUNT_DIR}" && umount -l "${MOUNT_DIR}"
        [[ -n "${LOOP_DEV}" ]] && losetup -d "${LOOP_DEV}" 2>/dev/null
        rm -rf "${MOUNT_DIR}" "${BOOT_DIR}"
        rm -f "${ROOTFS_RAW}"
    }
    trap cleanup_abl_conversion ERR EXIT

    # Mount Loop Device & Extract Boot Parameters
    local LOOP_DEV=$(losetup -f -P --show "${ORIG_IMG}")
    [[ -z "${LOOP_DEV}" ]] && exit_with_error "Failed to setup loop device"
    
    mount "${LOOP_DEV}p1" "${MOUNT_DIR}"
    local rootfs_uuid=$(blkid -s UUID -o value "${LOOP_DEV}p1")
    
    # Source armbianEnv.txt to retrieve extraargs and custom kernel parameters
    source "${MOUNT_DIR}/boot/armbianEnv.txt"
    declare -g cmdline="${BOOTIMG_CMDLINE_EXTRA} root=UUID=${rootfs_uuid} ${extraargs}"
    
    local vmlinuz=$(ls -1tr "${MOUNT_DIR}/boot"/vmlinu*-*-* 2>/dev/null | tail -n 1)
    local initrd=$(ls -1tr "${MOUNT_DIR}/boot"/initrd.img-*-* 2>/dev/null | tail -n 1)
    [[ -z "${vmlinuz}" || -z "${initrd}" ]] && exit_with_error "Kernel or initrd not found in the mounted image"

    # Compress kernel if it's uncompressed (avoids bloated boot.img)
    if gzip -t "${vmlinuz}" 2>/dev/null; then
        cp "${vmlinuz}" "${BOOT_DIR}/Image.gz"
    else
        gzip -9 -c "${vmlinuz}" > "${BOOT_DIR}/Image.gz"
    fi

    # Generate Boot Images for each Target DTB
    if [[ ${#ABL_DTB_LIST[@]} -gt 0 ]]; then
        display_alert "Boot Image" "Generating ABL boot images for specific boards" "info"
        for dtb_name in "${ABL_DTB_LIST[@]}"; do
            local dtb_file=$(find "${MOUNT_DIR}/usr/lib/" -name "${dtb_name}.dtb" | head -n 1)
            if [[ -z "$dtb_file" ]]; then
                display_alert "Boot Image" "DTB ${dtb_name} not found, skipping" "warning"
                continue
            fi
            
            # Append DTB to the kernel payload
            cat "${BOOT_DIR}/Image.gz" "${dtb_file}" > "${BOOT_DIR}/kernel-dtb-${dtb_name}"
            
            /usr/local/bin/mkbootimg \
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
        display_alert "Boot Image" "ABL_DTB_LIST is empty, skipping boot.img generation" "warning"
    fi

    # Extract RootFS & Convert to Sparse Format
    display_alert "Sparse Image" "Dumping and converting rootfs..." "info"
    dd if="${LOOP_DEV}p1" of="${ROOTFS_RAW}" bs=4M status=none
    
    umount "${MOUNT_DIR}"
    losetup -d "${LOOP_DEV}"
    unset LOOP_DEV

    # Note: e2fsck/resize2fs omitted; relying on precise block math to truncate unused space
    local block_count=$(dumpe2fs -h "${ROOTFS_RAW}" 2>/dev/null | awk '/Block count:/{print $3}')
    local block_size=$(dumpe2fs -h "${ROOTFS_RAW}" 2>/dev/null | awk '/Block size:/{print $3}')
    truncate -s $((block_count * block_size)) "${ROOTFS_RAW}"
    
    img2simg "${ROOTFS_RAW}" "${ROOTFS_SPARSE}"
    rm -f "${ROOTFS_RAW}"

    # Final Packaging
    local FLASHER_SRC="${SRC}/packages/bsp/UFI001C/Flasher"
    if [[ -d "${FLASHER_SRC}" ]]; then
        display_alert "Packaging" "Creating flashable release tarball" "info"
        local PACK_DIR=$(mktemp -d)
        mkdir -p "${PACK_DIR}/images"
        
        # Copy flasher tools and move generated images
        cp -r "${FLASHER_SRC}"/* "${PACK_DIR}/"
        shopt -s nullglob
        mv "${DESTIMG}/${version}.boot_"*.img* "${PACK_DIR}/images/" 2>/dev/null
        mv "${ROOTFS_SPARSE}"* "${PACK_DIR}/images/" 2>/dev/null
        shopt -u nullglob
        
        # Create final package and remove the original large Armbian image
        local final_archive="${DESTIMG}/${version}.tar"
        tar -cf "${final_archive}" -C "${PACK_DIR}" .
        rm -f "${ORIG_IMG}"
        rm -rf "${PACK_DIR}"
    else
        display_alert "Packaging" "Flasher directory not found, skipping tarball creation" "warning"
    fi

    display_alert "Image Processing" "ABL image conversion completed" "info"
    return 0
}