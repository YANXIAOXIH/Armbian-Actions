# Armbian-Actions: 自动化 Armbian 构建平台

[![Build Status](https://github.com/YANXIAOXIH/Armbian-Actions/actions/workflows/Build-Armbian-Stable.yml/badge.svg)](https://github.com/YANXIAOXIH/Armbian-Actions/actions/workflows/Build-Armbian-Stable.yml)

### 📝 项目概述

**Armbian-Actions** 是一个基于 GitHub Actions 的自动化 Armbian 系统编译平台。它旨在为开发者提供一个高效、灵活且无需本地环境配置的云端编译解决方案，支持多种 ARM 开发板和定制化需求。

本项目最初为 `SOM3588-Cat` (基于 Rockchip RK3588) 开发，现已扩展为一个更通用的工具，方便任何希望通过云端自动化构建 Armbian 镜像的开发者。

---

### ✨ 平台优势

-   **🚀 云端自动化**：完全基于 GitHub Actions，一键触发编译，无需占用本地计算资源，随时随地构建您的系统。
-   **🧩 高度可定制**：轻松选择不同的桌面环境、内核分支、文件系统，并集成自定义的 Armbian 扩展包。
-   **📦 APT 仓库集成**：自动化构建和发布内核 `.deb` 包，并将其推送到一个多发行版（multi-distribution）的 APT 仓库，方便下游系统更新。
-   **🌐 灵活触发**：支持手动触发（`workflow_dispatch`）和定时触发（`schedule`），满足调试和每日构建的需求。
-   **⚙️ Armbian 官方框架**：基于官方的 [Armbian Build Framework](https://github.com/armbian/build)，确保构建过程的稳定性和可靠性。

---

### 🛠️ 如何使用

本平台的核心是一个强大的 GitHub Actions 工作流。您可以 Fork 本仓库，并根据您的需求进行配置。

#### 1. Fork 本仓库

点击页面右上角的 **Fork** 按钮，将此仓库复刻到您自己的 GitHub 账户下。

#### 2. 配置您的仓库

##### 添加 Secrets
为了让工作流能够正常发布 Release 和更新 APT 仓库，您需要在您的 Fork 仓库中设置以下 Secrets (`Settings > Secrets and variables > Actions`):

-   `GPG_PRIVATE_KEY`: 您的 GPG 私钥，用于签名镜像和 APT 仓库。
-   `GPG_PASSPHRASE`: 您的 GPG 私钥密码。
-   `GPG_SIGNING_KEY_ID`: 您的 GPG 密钥 ID (长ID)。

##### 定制构建目标
-   打开 `.github/workflows/Build-Armbian-CI.yml` 文件。
-   **修改开发板**: 在 `Build_Kernel` Job 的 `strategy.matrix` 下，找到 `BOARD` 列表，将其中的内容替换为您想构建的开发板型号。
  ```yaml
  # 示例:
  strategy:
    matrix:
      BOARD: [ orange-pi-5, rock-5b ] # 在这里修改
  ```
-   **修改发行版**: 在文件顶部的 `env` 部分，找到 `RELEASES` 变量，修改其值为您想要支持的 Debian/Ubuntu 发行版代号。
  ```yaml
  # 示例:
  env:
    RELEASES: "bookworm trixie" # 在这里修改
  ```

#### 3. 触发编译

进入您的 Fork 仓库的 **Actions** 页面，找到 "Armbian Build Kernel Image" 工作流，然后点击 **Run workflow**。您可以根据需要填写以下参数：

-   `DESKTOP`: 选择您想要的桌面环境，或选择 `server` / `minimal`。
-   `ROOTFS`: 选择根文件系统类型，如 `ext4` 或 `btrfs`。
-   `nightly`: 选择构建类型，`yes` 为每日构建，`no` 为稳定版。
-   ...以及其他自定义参数。

#### 4. 获取产物

编译完成后，您可以在两个地方找到构建产物：

-   **GitHub Releases**: 完整的镜像文件 (`.img.xz`) 和内核包 (`.deb`) 会被发布到您仓库的 **Releases** 页面。
-   **GitHub Pages APT 仓库**: 内核包会自动发布到由 GitHub Pages 托管的 APT 仓库中。

#### 5. 在您的设备上使用 APT 软件源

为了方便地接收内核更新，您可以将本项目生成的 APT 仓库添加到您的 Armbian 设备中。详细步骤请参考我们的 [**软件源配置指南**](./Keyrings/README.md)。

---

### 🤝 贡献

欢迎所有开发者一起改进这个自动化平台！如果您有新的想法、功能优化或 Bug 修复，请遵循以下步骤：

1.  Fork 本仓库。
2.  创建一个新的功能分支 (`git checkout -b feature/your-idea`)。
3.  提交您的代码更改。
4.  向本仓库 (`YANXIAOXIH/Armbian-Actions`) 提交一个 Pull Request。

---

### 💬 社区与支持

-   **GitHub 仓库**: [YANXIAOXIH/Armbian-Actions](https://github.com/YANXIAOXIH/Armbian-Actions)
-   **Armbian 社区**: [Armbian 论坛](https://forum.armbian.com/)
-   **Rockchip 开发者社区**: [Rockchip 开发者中心](https://www.rock-chips.com/)

通过 **Armbian-Actions**，我们希望将强大的 Armbian 生态与现代化的 CI/CD 流程结合，为嵌入式开发社区提供一个更加便捷、高效的工具。