@echo off
:: 开启全局延迟变量扩展
setlocal enabledelayedexpansion

:: =============================================================================================
:: 环境与 UI 初始化
:: =============================================================================================
title UFI001C Armbian 智能刷机控制台 v1.5
mode con cols=100 lines=40
color 0F

:: 自动检测并开启 ANSI 颜色支持
reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>nul

:: 获取 ANSI 转义字符
for /F "delims=#" %%E in ('"prompt #$E# & for %%E in (1) do rem"') do set "ESC=%%E"
set "RED=%ESC%[91m"
set "GREEN=%ESC%[92m"
set "YELLOW=%ESC%[93m"
set "BLUE=%ESC%[94m"
set "CYAN=%ESC%[96m"
set "RESET=%ESC%[0m"

:: =============================================================================================
:: 路径变量配置
:: =============================================================================================
set "FASTBOOT_PATH=%~dp0fastboot"
set "FIRMWARE_PATH=%~dp0firmware"
set "IMAGES_PATH=%~dp0images"
set "ADB=%FASTBOOT_PATH%\adb.exe"
set "JB=%FASTBOOT_PATH%\fastboot.exe"

:: --- 基础文件检查 ---
if not exist "%ADB%" (
    echo %RED%[!] 错误: 找不到 ADB 环境，请确认 %FASTBOOT_PATH% 目录下存在 adb.exe！%RESET%
    echo.
    echo %GREEN%[?] 按任意键退出...%RESET% & pause >nul
    exit
)
if not exist "%JB%" (
    echo %RED%[!] 错误: 找不到 Fastboot 环境，请确认 %FASTBOOT_PATH% 目录下存在 fastboot.exe！%RESET%
    echo.
    echo %GREEN%[?] 按任意键退出...%RESET% & pause >nul
    exit
)
if not exist "%IMAGES_PATH%" mkdir "%IMAGES_PATH%"

:main_menu
cls
:: --- 初始化设备与进程状态变量 ---
set "DEV_STATUS=%RED%未连接 / 未安装驱动%RESET%"
set "DEV_SN="
set "MULTI_DEV_WARN="
set "MULTI_PROCESS_WARN="

:: 检测后台是否存在其他 Fastboot 进程
tasklist /FI "IMAGENAME eq fastboot.exe" 2>nul | findstr /I "fastboot.exe" >nul
if !errorlevel! equ 0 set "MULTI_PROCESS_WARN=1"

:: 1. 检测 Fastboot 设备
for /f "tokens=1,2" %%A in ('"%JB%" devices 2^>nul') do (
    if /I "%%B"=="fastboot" (
        if defined DEV_SN set "MULTI_DEV_WARN=1"
        set "DEV_SN=%%A"
        set "DEV_STATUS=%YELLOW%Fastboot 刷机模式%RESET%"
    )
)

if defined DEV_SN goto :net_check_done

:: 2. 检测 ADB 设备
for /f "tokens=1,2" %%A in ('"%ADB%" devices 2^>nul') do (
    if /I "%%B"=="device" (
        if defined DEV_SN set "MULTI_DEV_WARN=1"
        set "DEV_SN=%%A"
        set "DEV_STATUS=%GREEN%ADB 联机模式%RESET%"
    )
)
if defined DEV_SN goto :net_check_done

:net_check_done

:: 3. 构造设备显示文本
if defined DEV_SN (
    set "DEV_DISPLAY=SN: %CYAN%!DEV_SN!%RESET% [!DEV_STATUS!]"
) else (
    set "DEV_DISPLAY=!DEV_STATUS!"
)

echo %CYAN%=================================================================================================%RESET%
echo.
echo                       %GREEN%UFI001C Armbian 智能刷机控制台  v1.5%RESET%
echo.
echo %CYAN%=================================================================================================%RESET%
echo  [*] 当前设备状态: !DEV_DISPLAY!
if "!DEV_STATUS!"=="%GREEN%ADB 联机模式%RESET%" (
    echo  %GREEN%[*] 提示: 设备处于正常系统运行中，执行刷机会自动重启至 Fastboot 模式。%RESET%
)
if "!MULTI_DEV_WARN!"=="1" echo  %RED%[!] 警告: 检测到多台设备连接！请拔除无关设备，否则可能刷错或变砖！%RESET%
if "!MULTI_PROCESS_WARN!"=="1" echo  %RED%[!] 警告: 后台检测到其他刷机任务正在进行！请勿强行多开以免端口冲突！%RESET%
echo %CYAN%-------------------------------------------------------------------------------------------------%RESET%
echo.
echo     [%CYAN% 1 %RESET%] 完整全能刷机 %YELLOW%(底层固件 + Boot + Rootfs) - 适合救砖或首次安装%RESET%
echo     [%CYAN% 2 %RESET%] 仅刷入系统   %YELLOW%(Boot + Rootfs) - 不动底层和备份%RESET%
echo     [%CYAN% 3 %RESET%] 仅更新内核   %YELLOW%(仅刷入 Boot) - 适合更换 DTB%RESET%
echo     [%CYAN% 4 %RESET%] 仅更新系统   %YELLOW%(仅刷入 Rootfs) - 适合重置系统%RESET%
echo     [%CYAN% 5 %RESET%] 仅更新引导   %YELLOW%(选择并刷入 *lk1st.mbn) - 测试功能%RESET%
echo     [%CYAN% 6 %RESET%] 连接设备终端 %YELLOW%(一键进入 ADB Bash Shell 高级终端)%RESET%
echo     [%CYAN% Q %RESET%] 退出程序
echo.
echo %CYAN%=================================================================================================%RESET%
echo.

set "mode_choice="
set /p mode_choice="%GREEN%[?] 请输入对应按键并按回车 [默认: 1]: %RESET%"
if "!mode_choice!"=="" set "mode_choice=1"

:: 初始化刷机开关
set "DO_FIRMWARE=0" & set "DO_BOOT=0" & set "DO_ROOTFS=0" & set "DO_ABOOT=0"

:: 使用延迟变量判断，防止特殊字符注入报错
if /I "!mode_choice!"=="Q" exit
if "!mode_choice!"=="1" set "DO_FIRMWARE=1" & set "DO_BOOT=1" & set "DO_ROOTFS=1" & goto :find_images
if "!mode_choice!"=="2" set "DO_FIRMWARE=0" & set "DO_BOOT=1" & set "DO_ROOTFS=1" & goto :find_images
if "!mode_choice!"=="3" set "DO_FIRMWARE=0" & set "DO_BOOT=1" & set "DO_ROOTFS=0" & goto :find_images
if "!mode_choice!"=="4" set "DO_FIRMWARE=0" & set "DO_BOOT=0" & set "DO_ROOTFS=1" & goto :find_images
if "!mode_choice!"=="5" set "DO_ABOOT=1" & goto :select_aboot
if "!mode_choice!"=="6" goto :adb_shell_connect

goto main_menu

:: =============================================================================================
:: ADB Shell 模块
:: =============================================================================================
:adb_shell_connect
cls
echo %CYAN%-------------------------------------------------------%RESET%
echo               %YELLOW%正在准备连接 ADB Shell%RESET%
echo %CYAN%-------------------------------------------------------%RESET%
echo %YELLOW%[*] 等待中:%RESET% 正在等待设备连接...
"%ADB%" wait-for-device
echo %GREEN%[+] 成功:%RESET% 设备已连接！即将拉起终端...
echo %CYAN%[*] 提示:%RESET% 输入 exit 或按 Ctrl+D 可返回。
echo %CYAN%-------------------------------------------------------%RESET%
"%ADB%" shell -t "export TERM=xterm-256color; export LANG=zh_CN.UTF-8; stty rows 40 cols 120; exec bash -l"
echo.
echo %CYAN%[*] 提示:%RESET% 已断开 Shell 连接。
echo.
echo %GREEN%[?] 按任意键返回主菜单...%RESET% & pause >nul
goto main_menu

:: =============================================================================================
:: 引导选择与镜像扫描模块
:: =============================================================================================
:select_aboot
cls
echo %CYAN%[*] 请选择要刷入的引导层 (aboot) 文件:%RESET%
set count=0
for %%F in ("%FIRMWARE_PATH%\*lk1st.mbn") do (
    set /a count+=1
    set "aboot_file[!count!]=%%~fF"
    set "aboot_name[!count!]=%%~nxF"
    echo   [%CYAN% !count! %RESET%] %%~nxF
)
if !count!==0 (
    echo %RED%[!] 错误: 未在 %FIRMWARE_PATH% 目录下找到任何 *lk1st.mbn 文件！%RESET%
    echo.
    echo %GREEN%[?] 按任意键返回主菜单...%RESET% & pause >nul
    goto main_menu
)

echo.
set "ab_idx="
set /p ab_idx="%GREEN%[?] 请输入对应数字序号并按回车 [默认: 1]: %RESET%"
if "!ab_idx!"=="" set "ab_idx=1"

set "ABOOT_IMAGE_FILE=!aboot_file[%ab_idx%]!"
set "ABOOT_IMAGE_NAME=!aboot_name[%ab_idx%]!"

if "!ABOOT_IMAGE_FILE!"=="" (
    echo %RED%[!] 错误: 输入无效！%RESET%
    timeout /t 2 >nul
    goto select_aboot
)

cls
echo %RED%[!! 危险操作警告 !!]%RESET%
echo 您选择了单独刷入 %YELLOW%!ABOOT_IMAGE_NAME!%RESET%。
echo 如果文件损坏，设备将%RED%彻底变砖%RESET%！
echo.
set "confirm="
set /p confirm="%YELLOW%[?] 确定继续？[默认: Y] (Y/N): %RESET%"
if /I "!confirm!"=="" set "confirm=Y"
if /I not "!confirm!"=="Y" goto main_menu
goto execute_aboot

:find_images
cls
echo %CYAN%[*] 系统检测:%RESET% 正在自动扫描镜像文件...
echo.

set "ROOTFS_IMAGE_FILE="
for %%F in ("%IMAGES_PATH%\*.rootfs.img") do (
    set "ROOTFS_IMAGE_FILE=%%~fF"
    set "ROOTFS_IMAGE_NAME=%%~nxF"
)

if "!DO_ROOTFS!"=="1" (
    if not defined ROOTFS_IMAGE_FILE (
        echo %RED%[!] 错误: 未找到 *.rootfs.img 文件！%RESET%
        echo.
        echo %GREEN%[?] 按任意键返回主菜单...%RESET% & pause >nul
        goto main_menu
    )
)

if "!DO_BOOT!"=="0" goto confirm_execution

:select_boot
echo %CYAN%[*] 请选择要刷入的内核 Boot 版本:%RESET%
set count=0
for %%F in ("%IMAGES_PATH%\*.boot_*.img") do (
    set /a count+=1
    set "file[!count!]=%%~fF"
    set "tmpName=%%~nF"
    set "dtbName=!tmpName:*boot_=!"
    echo   [%CYAN% !count! %RESET%] !dtbName!
)
if !count!==0 (
    echo %RED%[!] 错误: 未找到任何 .boot_*.img 文件！%RESET%
    echo.
    echo %GREEN%[?] 按任意键返回主菜单...%RESET% & pause >nul
    goto main_menu
)

echo.
set "bt_idx="
set /p bt_idx="%GREEN%[?] 请输入对应数字序号并按回车 [默认: 1]: %RESET%"
if "!bt_idx!"=="" set "bt_idx=1"

set "BOOT_IMAGE_FILE=!file[%bt_idx%]!"
if "!BOOT_IMAGE_FILE!"=="" (
    echo %RED%[!] 错误: 输入无效！%RESET%
    timeout /t 2 >nul & cls
    goto select_boot
)
for %%I in ("!BOOT_IMAGE_FILE!") do set "BOOT_IMAGE_NAME=%%~nxI"

:confirm_execution
cls
echo %CYAN%===========================================================%RESET%
echo               %YELLOW%即将执行以下刷机任务%RESET%
echo %CYAN%===========================================================%RESET%
if "!DO_FIRMWARE!"=="1" echo   [%GREEN%OK%RESET%] 备份基带并刷写底层
if "!DO_BOOT!"=="1"     echo   [%GREEN%OK%RESET%] 刷入引导: %YELLOW%!BOOT_IMAGE_NAME!%RESET%
if "!DO_ROOTFS!"=="1"   echo   [%GREEN%OK%RESET%] 刷入系统: %YELLOW%!ROOTFS_IMAGE_NAME!%RESET%
echo %CYAN%===========================================================%RESET%
echo.

set "confirm_flash="
set /p confirm_flash="%GREEN%[?] 确认开始刷机？[默认: Y] (Y/N): %RESET%"
if /I "!confirm_flash!"=="" set "confirm_flash=Y"
if /I not "!confirm_flash!"=="Y" goto main_menu

:: =============================================================================================
:: 核心执行模块
:: =============================================================================================
call :check_and_reboot_fastboot

if "!DO_FIRMWARE!"=="1" (
    echo.
    echo %CYAN%--- [阶段 1] 刷写底层 ---%RESET%
    "%JB%" flash boot "%FIRMWARE_PATH%\lk2nd.img"
    "%JB%" reboot
    echo %YELLOW%[*] 等待:%RESET% 正在等待重启至 lk2nd...
    timeout /t 12 /nobreak >nul
    
    echo %CYAN%[*] 执行:%RESET% 提取基带...
    "%JB%" oem dump fsc && "%JB%" get_staged "%FIRMWARE_PATH%\fsc.bin"
    "%JB%" oem dump fsg && "%JB%" get_staged "%FIRMWARE_PATH%\fsg.bin"
    "%JB%" oem dump modemst1 && "%JB%" get_staged "%FIRMWARE_PATH%\modemst1.bin"
    "%JB%" oem dump modemst2 && "%JB%" get_staged "%FIRMWARE_PATH%\modemst2.bin"
    
    echo %CYAN%[*] 执行:%RESET% 刷写分区表与底层...
    "%JB%" flash partition "%FIRMWARE_PATH%\gpt_both0.bin"
    "%JB%" flash hyp "%FIRMWARE_PATH%\hyp.mbn"
    "%JB%" flash rpm "%FIRMWARE_PATH%\rpm.mbn"
    "%JB%" flash sbl1 "%FIRMWARE_PATH%\sbl1.mbn"
    "%JB%" flash tz "%FIRMWARE_PATH%\tz.mbn"
    "%JB%" flash aboot "%FIRMWARE_PATH%\ufi001c-lk1st.mbn"
    "%JB%" flash cdt "%FIRMWARE_PATH%\sbc_1.0_8016.bin"
    
    echo %CYAN%[*] 执行:%RESET% 恢复基带...
    if exist "%FIRMWARE_PATH%\fsc.bin" "%JB%" flash fsc "%FIRMWARE_PATH%\fsc.bin"
    if exist "%FIRMWARE_PATH%\fsg.bin" "%JB%" flash fsg "%FIRMWARE_PATH%\fsg.bin"
    if exist "%FIRMWARE_PATH%\modemst1.bin" "%JB%" flash modemst1 "%FIRMWARE_PATH%\modemst1.bin"
    if exist "%FIRMWARE_PATH%\modemst2.bin" "%JB%" flash modemst2 "%FIRMWARE_PATH%\modemst2.bin"
    
    "%JB%" reboot bootloader
    timeout /t 8 /nobreak >nul
)

if "!DO_BOOT!"=="1" (
    echo.
    echo %CYAN%--- [阶段 2] 刷入内核 ---%RESET%
    "%JB%" flash boot "!BOOT_IMAGE_FILE!"
)

if "!DO_ROOTFS!"=="1" (
    echo.
    echo %CYAN%--- [阶段 3] 刷入系统 ---%RESET%
    "%JB%" -S 200m flash rootfs "!ROOTFS_IMAGE_FILE!"
)

goto finish_all

:execute_aboot
call :check_and_reboot_fastboot
echo %CYAN%[*] 正在刷入:%RESET% !ABOOT_IMAGE_NAME!
"%JB%" flash aboot "!ABOOT_IMAGE_FILE!"
"%JB%" reboot
echo.
echo %GREEN%[?] 操作完成，按任意键返回主菜单...%RESET% & pause >nul
goto cleanup_and_return

:: --- 公共检测模块 ---
:check_and_reboot_fastboot
echo %CYAN%[*] 检测设备:%RESET% 正在扫描连接状态...
"%JB%" devices | findstr /I "fastboot" >nul
if !errorlevel! equ 0 exit /b
"%ADB%" devices | findstr /I "device" | findstr /V "List" >nul
if !errorlevel! equ 0 (
    echo %YELLOW%[*] 检测到设备处于 ADB 模式，正在重启至 Bootloader...%RESET%
    "%ADB%" reboot bootloader
)
echo %YELLOW%[*] 等待中:%RESET% 请确保设备已连接并进入 Fastboot 模式...
:wait_fastboot_loop
timeout /t 1 /nobreak >nul
"%JB%" devices | findstr /I "fastboot" >nul
if !errorlevel! equ 0 exit /b
goto wait_fastboot_loop

:: --- 完成处理模块 ---
:finish_all
echo.
echo %GREEN%===========================================================%RESET%
echo               %GREEN%★★ 所有选定操作已顺利完成 ★★%RESET%
echo %GREEN%===========================================================%RESET%
echo.

set "finish_act="
set /p finish_act="%GREEN%[?] 下一步操作 [默认: R] (R=重启设备 / M=返回主菜单): %RESET%"
if /I "!finish_act!"=="" set "finish_act=R"

if /I "!finish_act!"=="M" goto cleanup_and_return

echo %CYAN%[*] 正在重启设备...%RESET%
"%JB%" reboot

:: --- 公共清理模块 (DRY 核心) ---
:cleanup_and_return
"%ADB%" kill-server >nul 2>nul
taskkill /f /im fastboot.exe >nul 2>nul
goto main_menu