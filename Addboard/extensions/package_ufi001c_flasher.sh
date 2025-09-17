#!/bin/bash

# --- 配置 ---
# 当任何命令失败时立即退出脚本
set -e
# 当使用未定义的变量时，视为错误并退出 (set -u)
# 管道中的任何命令失败，整个管道都视为失败 (set -o pipefail)
set -uo pipefail

# --- 变量定义 ---
WORKSPACE_ROOT=$(pwd)
BUILD_OUTPUT_DIR="${WORKSPACE_ROOT}/output/images"
FLASHER_DIR="${WORKSPACE_ROOT}/packages/bsp/UFI001C/Flasher"

# --- 权限检查 ---
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 错误：此脚本需要以 root 或 sudo 权限运行，因为它需要挂载文件系统。" >&2
  exit 1
fi

# --- 脚本开始 ---
echo "🚀 开始执行 Flasher 打包脚本..."

# 1. 查找源镜像文件
echo "--> 1. 正在搜索 Armbian 镜像文件..."
SOURCE_IMAGE_XZ=$(find "${BUILD_OUTPUT_DIR}" \( -name "*Ufi00*.img.xz" -o -name "*Uz801*.img.xz" \) -type f)
if [ -z "${SOURCE_IMAGE_XZ}" ]; then
  echo "❌ 错误：在目录 ${BUILD_OUTPUT_DIR} 中未找到匹配 'Ufi00*' 或 'Uz801*' 的 .img.xz 文件。"
  exit 1
fi

if [ $(echo "${SOURCE_IMAGE_XZ}" | wc -l) -gt 1 ]; then
  echo "⚠️ 警告：找到多个匹配的镜像文件，将使用第一个："
  echo "${SOURCE_IMAGE_XZ}"
  SOURCE_IMAGE_XZ=$(echo "${SOURCE_IMAGE_XZ}" | head -n 1)
fi
echo "    找到镜像文件: ${SOURCE_IMAGE_XZ}"

# 2. 创建临时打包工作目录
PACKAGING_TEMP_DIR=$(mktemp -d -p /tmp ufi-packaging.XXXXXX)
echo "--> 2. 创建临时打包目录: ${PACKAGING_TEMP_DIR}"

### MODIFIED ### - 移除了trap中的kpartx命令
trap 'echo "--> 正在清理所有临时文件和挂载点..."; \
      if mountpoint -q "${PACKAGING_TEMP_DIR}/Armbian_img"; then umount "${PACKAGING_TEMP_DIR}/Armbian_img"; fi; \
      if [ -n "${LOOP_DEVICE-}" ] && [ -b "${LOOP_DEVICE}" ]; then losetup -d "${LOOP_DEVICE}"; fi; \
      rm -rf "${PACKAGING_TEMP_DIR}"' EXIT 

# 3. 复制Flasher工具集
echo "--> 3. 正在复制 Flasher 文件..."
if [ ! -d "${FLASHER_DIR}" ]; then
  echo "❌ 错误：Flasher目录不存在: ${FLASHER_DIR}"
  exit 1
fi
cp -r "${FLASHER_DIR}"/* "${PACKAGING_TEMP_DIR}/"

IMAGE_FULL_FILENAME=$(basename "${SOURCE_IMAGE_XZ}")
TEMP_BASENAME=${IMAGE_FULL_FILENAME%.img.xz}


# 4. 解压镜像文件
echo "--> 4. 正在解压镜像文件..."
unxz -c "${SOURCE_IMAGE_XZ}" > "${PACKAGING_TEMP_DIR}/${TEMP_BASENAME}.system.img"
DECOMPRESSED_IMG_PATH="${PACKAGING_TEMP_DIR}/${TEMP_BASENAME}.system.img"
echo "    解压完成: ${DECOMPRESSED_IMG_PATH}"

# ==============================================================================
# ###  生成 boot.img 的核心逻辑 ###
# ==============================================================================
echo "--> 5. 开始生成 boot.img..."

# 5.1 设置挂载点和临时构建目录
MOUNT_POINT="${PACKAGING_TEMP_DIR}/Armbian_img"
BOOT_BUILD_DIR="${PACKAGING_TEMP_DIR}/boot_build"
mkdir -p "${MOUNT_POINT}" "${BOOT_BUILD_DIR}"
echo "    - 挂载点: ${MOUNT_POINT}"
echo "    - boot构建目录: ${BOOT_BUILD_DIR}"

### MODIFIED ### - 实现了智能挂载逻辑
# 5.2 挂载原始镜像文件
echo "    正在设置循环设备并扫描分区..."
LOOP_DEVICE=$(losetup -f --show -P "${DECOMPRESSED_IMG_PATH}")
# 定义两种可能的挂载设备
PARTITION_DEV="${LOOP_DEVICE}p1" # 带分区表的设备 (e.g. /dev/loop0p1)
RAW_DEV="${LOOP_DEVICE}"         # 裸文件系统设备 (e.g. /dev/loop0)

# 添加短暂延时，给udev时间创建节点
sleep 1

echo "    正在尝试智能挂载..."
if [ -b "${PARTITION_DEV}" ]; then
    # 优先尝试挂载第一个分区
    echo "    检测到分区表，正在挂载 ${PARTITION_DEV}..."
    mount "${PARTITION_DEV}" "${MOUNT_POINT}"
elif [ -b "${RAW_DEV}" ]; then
    # 如果分区不存在，则回退到直接挂载整个循环设备
    echo "    未检测到分区表，回退到直接挂载裸文件系统 ${RAW_DEV}..."
    mount "${RAW_DEV}" "${MOUNT_POINT}"
else
    # 如果两种设备都找不到，则报错
    echo "❌ 致命错误：无法找到可挂载的设备节点！" >&2
    exit 1
fi
echo "    镜像已成功挂载。"

# 5.3 从挂载的系统中提取文件
echo "    正在从挂载的镜像中提取组件..."
ENV_FILE="${MOUNT_POINT}/boot/armbianEnv.txt"
if [ ! -f "${ENV_FILE}" ]; then
    echo "❌ 错误：在挂载的镜像中未找到 ${ENV_FILE}。"
    exit 1
fi
source "${ENV_FILE}"
if [ -z "$fdtfile" ]; then
    echo "❌ 错误：在 ${ENV_FILE} 中未设置 'fdtfile' 变量。"
    exit 1
fi
KERNEL_FILE=$(find "${MOUNT_POINT}/boot" -name "vmlinuz-*" | sort -V | tail -n 1)
INITRD_FILE=$(find "${MOUNT_POINT}/boot" -name "initrd.img-*" | sort -V | tail -n 1)
KERNEL_VERSION=$(basename "${KERNEL_FILE}" | sed 's/vmlinuz-//')
DTB_FILE="${MOUNT_POINT}/usr/lib/linux-image-${KERNEL_VERSION}/${fdtfile}"
echo "      - 内核: $(basename ${KERNEL_FILE})"
echo "      - Initrd: $(basename ${INITRD_FILE})"
echo "      - DTB: ${fdtfile}"
if ! [ -f "${KERNEL_FILE}" ] || ! [ -f "${INITRD_FILE}" ] || ! [ -f "${DTB_FILE}" ]; then
    echo "❌ 错误：一个或多个必要文件未找到！"
    exit 1
fi

# 5.4 准备构建boot.img的组件
echo "    正在准备组件..."
gzip -9 -c "${KERNEL_FILE}" > "${BOOT_BUILD_DIR}/Image.gz"
cat "${BOOT_BUILD_DIR}/Image.gz" "${DTB_FILE}" > "${BOOT_BUILD_DIR}/kernel-dtb"
cp "${INITRD_FILE}" "${BOOT_BUILD_DIR}/initrd.img"

# 5.5 使用mkbootimg生成boot.img
echo "    正在构建新的 boot.img..."
# 使用您提供的参数
CMDLINE="earlycon root=PARTUUID=a7ab80e8-e9d1-e8cd-f157-93f69b1d141e console=ttyMSM0,115200 no_framebuffer=true rw"

FINAL_BASENAME=${TEMP_BASENAME%.rootfs}
GENERATED_BOOT_IMG_PATH="${BOOT_BUILD_DIR}/${FINAL_BASENAME}.boot.img"
mkbootimg \
    --base 0x80000000 \
    --kernel_offset 0x00080000 \
    --ramdisk_offset 0x02000000 \
    --tags_offset 0x01e00000 \
    --pagesize 2048 \
    --second_offset 0x00f00000 \
    --ramdisk "${BOOT_BUILD_DIR}/initrd.img" \
    --cmdline "${CMDLINE}" \
    --kernel "${BOOT_BUILD_DIR}/kernel-dtb" \
    -o "${GENERATED_BOOT_IMG_PATH}"
echo "    ${FINAL_BASENAME}.boot.img 生成成功！"

# 5.6 卸载镜像
echo "    正在卸载镜像..."
umount "${MOUNT_POINT}"
losetup -d "${LOOP_DEVICE}"
LOOP_DEVICE=""
# ==============================================================================

# 6. 将生成的boot.img和system.simg放入Flasher的images目录 (此部分逻辑不变)
echo "--> 6. 正在处理镜像并放置到Flasher目录..."
TARGET_IMAGES_DIR="${PACKAGING_TEMP_DIR}/images"
if [ ! -d "${TARGET_IMAGES_DIR}" ]; then
  echo "⚠️ 警告：在 Flasher 文件中未找到 'images' 子目录，将自动创建。"
  mkdir -p "${TARGET_IMAGES_DIR}"
fi
# 复制boot.img
echo "    复制 boot.img..."
cp "${GENERATED_BOOT_IMG_PATH}" "${TARGET_IMAGES_DIR}/"
# 转换system.img
echo "    转换 system.img 为稀疏格式..."
SPARSE_IMG_PATH="${TARGET_IMAGES_DIR}/${TEMP_BASENAME}.img"
img2simg "${DECOMPRESSED_IMG_PATH}" "${SPARSE_IMG_PATH}"
# 清理临时文件
rm "${DECOMPRESSED_IMG_PATH}"
rm -rf "${MOUNT_POINT}" 
rm -rf "${BOOT_BUILD_DIR}"
echo "    临时目录清理完毕。"

# 7. 创建最终的发布包
echo "--> 7. 正在创建最终的发布包..."
FINAL_ARCHIVE_PATH="${BUILD_OUTPUT_DIR}/${FINAL_BASENAME}.tar.xz"
(cd "${PACKAGING_TEMP_DIR}" && tar -cJf "${FINAL_ARCHIVE_PATH}" .)

# 8. 验证并替换原始文件
echo "--> 8. 正在验证并替换原始文件..."
if [ -f "${FINAL_ARCHIVE_PATH}" ]; then
  echo "    新包创建成功。"
  echo "    正在删除原始镜像: ${SOURCE_IMAGE_XZ}"
  rm "${SOURCE_IMAGE_XZ}"
  echo "    替换完成。"
  if [ -f "${SOURCE_IMAGE_XZ}.sha" ]; then
    rm "${SOURCE_IMAGE_XZ}.sha"
  else
    echo "⚠️ 警告：未找到 SHA 文件: ${SOURCE_IMAGE_XZ}.sha"
  fi
  
  echo "正在为新的发布包生成SHA256校验和..."
  sha256sum "${FINAL_ARCHIVE_PATH}" | awk '{print $1}' > "${FINAL_ARCHIVE_PATH}.sha"
  echo "    SHA 文件已创建: ${FINAL_ARCHIVE_PATH}.sha"
  
else
  echo "❌ 严重错误：最终包未能创建，原始镜像已被保留。"
  exit 1
fi

echo "✅ 打包成功完成！"
echo "🎉 最终发布包位于: ${FINAL_ARCHIVE_PATH}"

# trap命令会在脚本退出时自动执行清理工作
exit 0
