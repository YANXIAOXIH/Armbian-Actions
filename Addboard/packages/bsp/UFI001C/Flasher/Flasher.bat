@echo off
@title UFI001C Armbian 全能刷机工具 v2.1
color 0A
mode con cols=105 lines=55

:: =============================================================================================
set "FASTBOOT_PATH=%~dp0fastboot"
set "FIRMWARE_PATH=%~dp0firmware"
set "IMAGES_PATH=%~dp0images"
set "ADB=%FASTBOOT_PATH%\adb.exe"
set "JB=%FASTBOOT_PATH%\fastboot.exe"

:main_menu
cls
echo =============================================================================================
echo.
echo                   欢迎使用 UFI001C Armbian 全能刷机工具  v2.1
echo.
echo    [ 1 ] 完整全能刷机 (备份 + 底层固件 + Boot + Rootfs) - 适合救砖或首次安装
echo    [ 2 ] 仅刷入系统 (Boot + Rootfs) - 不动底层和备份
echo    [ 3 ] 仅更新内核 (仅刷入 Boot) - 测试功能
echo    [ 4 ] 仅更新系统 (仅刷入 Rootfs) - 测试功能
echo    [ 5 ] 仅更新引导程序 (单独刷入 lk1st.mbn) - 测试功能
echo    [ Q ] 退出
echo.
echo =============================================================================================
set /p mode_choice="请选择操作模式 [1-5, Q]: "

:: 初始化所有开关
set "DO_FIRMWARE=0" & set "DO_BOOT=0" & set "DO_ROOTFS=0" & set "DO_ABOOT=0"

if /i "%mode_choice%"=="Q" exit
if "%mode_choice%"=="1" set "DO_FIRMWARE=1" & set "DO_BOOT=1" & set "DO_ROOTFS=1" & goto :find_images
if "%mode_choice%"=="2" set "DO_FIRMWARE=0" & set "DO_BOOT=1" & set "DO_ROOTFS=1" & goto :find_images
if "%mode_choice%"=="3" set "DO_FIRMWARE=0" & set "DO_BOOT=1" & set "DO_ROOTFS=0" & goto :find_images
if "%mode_choice%"=="4" set "DO_FIRMWARE=0" & set "DO_BOOT=0" & set "DO_ROOTFS=1" & goto :find_images
if "%mode_choice%"=="5" set "DO_ABOOT=1" & goto :confirm_aboot
goto main_menu

:confirm_aboot
cls
echo [!! 警告 !!]
echo 您选择了单独刷入 lk1st.mbn。
echo 如果 lk1st.mbn 文件损坏或与硬件不匹配，设备将彻底黑屏且无法进入 Fastboot！
echo 届时只能通过 9008 (EDL) 模式救砖。
echo.
set "abconfirm="
set /p abconfirm="确定继续？(Y/N): "
if /i "%abconfirm%"=="N" goto main_menu
goto :execute_aboot

:find_images
cls
echo [检测中...] 正在扫描镜像文件...
echo.

:: --- 查找 Rootfs ---
set "ROOTFS_IMAGE_FILE="
set "ROOTFS_IMAGE_NAME="
for %%F in ("%IMAGES_PATH%\*.rootfs.img") do (
    set "ROOTFS_IMAGE_FILE=%%~fF"
    set "ROOTFS_IMAGE_NAME=%%~nxF"
)

if "%DO_ROOTFS%"=="1" (
    if not defined ROOTFS_IMAGE_FILE (
        echo [错误] 未找到 *.rootfs.img 文件！
        pause
        goto main_menu
    )
)

:: --- 动态查找 Boot 列表 ---
if "%DO_BOOT%"=="0" goto :confirm_execution

:select_boot
echo 请选择要刷入的 Boot (DTB) 版本:
setlocal enabledelayedexpansion
set count=0
for %%F in ("%IMAGES_PATH%\*.boot_*.img") do (
    set /a count+=1
    set "file[!count!]=%%~fF"
    set "tmpName=%%~nF"
    set "dtbName=!tmpName:*boot_=!"
    echo   [ !count! ] !dtbName!
)

if !count!==0 (
    echo [错误] 在 images 文件夹下未找到任何 .boot_*.img 文件！
    endlocal
    pause
    goto main_menu
)

set /p bt_idx="选择编号: "

:: 安全读取数组变量
set "TEMP_FILE="
for %%i in (!bt_idx!) do set "TEMP_FILE=!file[%%i]!"

if "!TEMP_FILE!"=="" (
    echo [错误] 选择无效，请输入正确的数字！
    endlocal
    pause
    cls
    goto :select_boot
)

:: 将变量安全导出 setlocal 作用域
for /f "delims=" %%A in ("!TEMP_FILE!") do (
    endlocal
    set "BOOT_IMAGE_FILE=%%A"
)

:confirm_execution
:: 获取仅带文件名的变量用于展示UI
if defined BOOT_IMAGE_FILE for %%I in ("%BOOT_IMAGE_FILE%") do set "BOOT_IMAGE_NAME=%%~nxI"

:: ===================================================================================================
:: 确认与执行
:: ===================================================================================================
cls
echo -------------------------------------------------------
echo   准备就绪，即将开始执行:
if "%DO_FIRMWARE%"=="1" echo   - 备份分区并刷写底层固件
if "%DO_BOOT%"=="1"     echo   - 刷入引导: %BOOT_IMAGE_NAME%
if "%DO_ROOTFS%"=="1"   echo   - 刷入系统: %ROOTFS_IMAGE_NAME%
echo -------------------------------------------------------
set "confirm="
set /p confirm="确认开始？(Y/N): "
if /i "%confirm%"=="N" goto main_menu

:: --- 检测设备 ---
echo [步骤] 正在检测设备连接...
"%ADB%" devices | find "device" >nul
if %errorlevel% equ 0 (
    echo 设备处于安卓模式，正在重启至 Fastboot...
    "%ADB%" reboot bootloader
    timeout /t 5 >nul
)

:: --- 逻辑分区执行 ---

if "%DO_FIRMWARE%"=="1" (
    echo [步骤] 执行安全备份与底层固件刷写...
    "%JB%" flash boot "%FIRMWARE_PATH%\lk2nd.img"
    "%JB%" reboot
    echo 等待进入 lk2nd 模式...
    timeout /t 15
    
    "%JB%" oem dump fsc && "%JB%" get_staged "%FIRMWARE_PATH%\fsc.bin"
    "%JB%" oem dump fsg && "%JB%" get_staged "%FIRMWARE_PATH%\fsg.bin"
    "%JB%" oem dump modemst1 && "%JB%" get_staged "%FIRMWARE_PATH%\modemst1.bin"
    "%JB%" oem dump modemst2 && "%JB%" get_staged "%FIRMWARE_PATH%\modemst2.bin"
    
    echo 正在刷写底层分区表...
    "%JB%" flash partition "%FIRMWARE_PATH%\gpt_both0.bin"
    "%JB%" flash hyp "%FIRMWARE_PATH%\hyp.mbn"
    "%JB%" flash rpm "%FIRMWARE_PATH%\rpm.mbn"
    "%JB%" flash sbl1 "%FIRMWARE_PATH%\sbl1.mbn"
    "%JB%" flash tz "%FIRMWARE_PATH%\tz.mbn"
    "%JB%" flash aboot "%FIRMWARE_PATH%\aboot.bin"
    "%JB%" flash cdt "%FIRMWARE_PATH%\sbc_1.0_8016.bin"
    
    echo 恢复基带备份...
    "%JB%" flash fsc "%FIRMWARE_PATH%\fsc.bin"
    "%JB%" flash fsg "%FIRMWARE_PATH%\fsg.bin"
    "%JB%" flash modemst1 "%FIRMWARE_PATH%\modemst1.bin"
    "%JB%" flash modemst2 "%FIRMWARE_PATH%\modemst2.bin"
    
    echo 重启至 Bootloader 以应用分区表...
    "%JB%" reboot bootloader
    timeout /t 8
)

if "%DO_BOOT%"=="1" (
    echo [步骤] 正在刷入 Boot 分区...
    "%JB%" flash boot "%BOOT_IMAGE_FILE%"
    if errorlevel 1 echo [错误] Boot 刷写失败！ && pause
)

if "%DO_ROOTFS%"=="1" (
    echo [步骤] 正在刷入 Rootfs 分区...
    "%JB%" -S 200m flash rootfs "%ROOTFS_IMAGE_FILE%"
    if errorlevel 1 echo [错误] Rootfs 刷写失败！ && pause
)

goto :finish_all

:execute_aboot
:: 1. 首先尝试进入 Fastboot
echo [步骤] 正在检测设备状态...
"%ADB%" devices | find "device" >nul
if %errorlevel% equ 0 (
    echo 设备处于正常模式，正在重启至 Fastboot...
    "%ADB%" reboot bootloader
    timeout /t 5 >nul
)

:: 2. 刷写 aboot
echo [步骤] 正在刷入底层引导程序 (lk1st.mbn)...
:: 注意：这里必须指定确切的文件名，不要带通配符
"%JB%" flash aboot "%FIRMWARE_PATH%\lk1st.mbn"
if errorlevel 1 (
    echo [错误] aboot 刷写失败！
    echo 请检查设备是否已进入 Fastboot 模式(屏幕应显示 Fastboot 文字)
    pause
    goto main_menu
)
:: 3. 刷完必须重启，否则不生效
echo [步骤] 刷写完成，正在重启至 Bootloader...
"%JB%" reboot
pause
goto main_menu

:finish_all
echo.
echo ======================================================
echo           所有选定操作已完成！
echo ======================================================
set "last_choice="
set /p last_choice="直接回车 [Enter] 重启设备，按 M 返回主菜单: "
if /i "%last_choice%"=="M" goto main_menu

:: 只要不是输入 M，无论用户直接按回车还是乱打字，都执行重启
echo [正在重启设备...]
"%JB%" reboot
if errorlevel 1 (
    echo [提示] 重启命令发送失败，请手动拔插设备。
    pause
)
goto main_menu