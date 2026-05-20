@echo off
:: =============================================================================================
:: 环境与 UI 初始化
:: =============================================================================================
title UFI001C Armbian 智能刷机控制台 v3.1
mode con cols=100 lines=40
color 0F

:: 自动检测并开启 ANSI 颜色支持
reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>nul

:: 获取 ANSI 转义字符
for /F "delims=#" %%E in ('"prompt #$E# & for %%E in (1) do rem"') do set "ESC=%%E"
set "RED=%ESC%[91m"
set "GREEN=%ESC%[92m"
set "YELLOW=%ESC%[93m"
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
    echo [错误] 找不到 ADB 环境，请确认 %FASTBOOT_PATH% 目录下存在 adb.exe！
    pause & exit
)
if not exist "%JB%" (
    echo [错误] 找不到 Fastboot 环境，请确认 %FASTBOOT_PATH% 目录下存在 fastboot.exe！
    pause & exit
)
if not exist "%IMAGES_PATH%" mkdir "%IMAGES_PATH%"

:main_menu
cls
echo %CYAN%=============================================================================================%RESET%
echo.
echo                       %GREEN%UFI001C Armbian 智能刷机控制台  v3.1%RESET%
echo.
echo %CYAN%=============================================================================================%RESET%
echo.
echo     [%CYAN% 1 %RESET%] 完整全能刷机 %YELLOW%(备份 + 底层固件 + Boot + Rootfs) - 适合救砖或首次安装%RESET%
echo     [%CYAN% 2 %RESET%] 仅刷入系统   %YELLOW%(Boot + Rootfs) - 不动底层和备份%RESET%
echo     [%CYAN% 3 %RESET%] 仅更新内核   %YELLOW%(仅刷入 Boot) - 适合更换 DTB%RESET%
echo     [%CYAN% 4 %RESET%] 仅更新系统   %YELLOW%(仅刷入 Rootfs) - 适合重置系统%RESET%
echo     [%CYAN% 5 %RESET%] 仅更新引导   %YELLOW%(单独刷入 lk1st.mbn) - 测试功能%RESET%
echo     [%CYAN% 6 %RESET%] 连接设备终端 %YELLOW%(一键进入 ADB Bash Shell 高级终端)%RESET%
echo     [%CYAN% Q %RESET%] 退出程序
echo.
echo %CYAN%=============================================================================================%RESET%

choice /C 123456Q /N /M "%GREEN%请按键盘对应按键选择操作模式:%RESET% "
set mode_choice=%errorlevel%

:: 初始化所有开关
set "DO_FIRMWARE=0" & set "DO_BOOT=0" & set "DO_ROOTFS=0" & set "DO_ABOOT=0"

if "%mode_choice%"=="7" exit
if "%mode_choice%"=="1" set "DO_FIRMWARE=1" & set "DO_BOOT=1" & set "DO_ROOTFS=1" & goto :find_images
if "%mode_choice%"=="2" set "DO_FIRMWARE=0" & set "DO_BOOT=1" & set "DO_ROOTFS=1" & goto :find_images
if "%mode_choice%"=="3" set "DO_FIRMWARE=0" & set "DO_BOOT=1" & set "DO_ROOTFS=0" & goto :find_images
if "%mode_choice%"=="4" set "DO_FIRMWARE=0" & set "DO_BOOT=0" & set "DO_ROOTFS=1" & goto :find_images
if "%mode_choice%"=="5" set "DO_ABOOT=1" & goto :confirm_aboot
if "%mode_choice%"=="6" goto :adb_shell_connect
goto main_menu

:: =============================================================================================
:: 一键连接 ADB Shell 模块
:: =============================================================================================
:adb_shell_connect
cls
echo %CYAN%-------------------------------------------------------%RESET%
echo               %YELLOW%正在准备连接 ADB Shell%RESET%
echo %CYAN%-------------------------------------------------------%RESET%
echo %YELLOW%[等待中]%RESET% 正在等待设备连接...
"%ADB%" wait-for-device
echo %GREEN%[成功]%RESET% 设备已连接！即将拉起终端...
echo %CYAN%[提示]%RESET% 在终端内无法使用图形界面...
echo %CYAN%[提示]%RESET% 在终端内输入 exit 或按 Ctrl+D 可返回。
echo %CYAN%-------------------------------------------------------%RESET%
"%ADB%" shell -t "export TERM=xterm-256color; export LANG=zh_CN.UTF-8; stty rows 40 cols 120; exec bash -l"
echo.
echo %CYAN%[提示]%RESET% 已断开 Shell 连接。
pause
goto main_menu

:: =============================================================================================
:: 刷机准备与文件确认模块
:: =============================================================================================
:confirm_aboot
cls
echo %RED%[!! 危险操作警告 !!]%RESET%
echo 您选择了单独刷入 %YELLOW%lk1st.mbn%RESET%。
echo 如果文件损坏，设备将%RED%彻底变砖%RESET%！
echo.
choice /C YN /N /M "%YELLOW%确定继续？(Y=继续 / N=返回):%RESET% "
if "%errorlevel%"=="2" goto main_menu
goto :execute_aboot

:find_images
cls
echo %CYAN%[系统检测]%RESET% 正在自动扫描镜像文件...
echo.

set "ROOTFS_IMAGE_FILE="
for %%F in ("%IMAGES_PATH%\*.rootfs.img") do (
    set "ROOTFS_IMAGE_FILE=%%~fF"
    set "ROOTFS_IMAGE_NAME=%%~nxF"
)

if "%DO_ROOTFS%"=="1" (
    if not defined ROOTFS_IMAGE_FILE (
        echo %RED%[错误]%RESET% 未找到 *.rootfs.img 文件！
        pause & goto main_menu
    )
)

if "%DO_BOOT%"=="0" goto :confirm_execution

:select_boot
echo %CYAN%请选择要刷入的内核 Boot 版本:%RESET%
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
    echo %RED%[错误]%RESET% 未找到任何 .boot_*.img 文件！
    endlocal & pause & goto main_menu
)

echo.
set "bt_idx="
set /p bt_idx="%GREEN%请输入对应数字序号并按回车:%RESET% "
if "%bt_idx%"=="" endlocal & cls & goto :select_boot
set "TEMP_FILE="
for %%i in (!bt_idx!) do set "TEMP_FILE=!file[%%i]!"
if "!TEMP_FILE!"=="" (
    echo %RED%[错误] 输入无效！%RESET%
    endlocal & timeout /t 2 >nul & cls & goto :select_boot
)
for /f "delims=" %%A in ("!TEMP_FILE!") do (
    endlocal
    set "BOOT_IMAGE_FILE=%%A"
)

:confirm_execution
if defined BOOT_IMAGE_FILE for %%I in ("%BOOT_IMAGE_FILE%") do set "BOOT_IMAGE_NAME=%%~nxI"
cls
echo %CYAN%=======================================================%RESET%
echo               %YELLOW%即将执行以下刷机任务%RESET%
echo %CYAN%=======================================================%RESET%
if "%DO_FIRMWARE%"=="1" echo   [%GREEN%OK%RESET%] 备份基带并刷写底层
if "%DO_BOOT%"=="1"     echo   [%GREEN%OK%RESET%] 刷入引导: %YELLOW%%BOOT_IMAGE_NAME%%RESET%
if "%DO_ROOTFS%"=="1"   echo   [%GREEN%OK%RESET%] 刷入系统: %YELLOW%%ROOTFS_IMAGE_NAME%%RESET%
echo %CYAN%=======================================================%RESET%
echo.
choice /C YN /N /M "%GREEN%确认开始刷机？(Y/N):%RESET% "
if "%errorlevel%"=="2" goto main_menu

:: =============================================================================================
:: 核心执行模块
:: =============================================================================================

call :check_and_reboot_fastboot

if "%DO_FIRMWARE%"=="1" (
    echo.
    echo %CYAN%--- [阶段 1] 刷写底层 ---%RESET%
    "%JB%" flash boot "%FIRMWARE_PATH%\lk2nd.img"
    "%JB%" reboot
    echo %YELLOW%[等待]%RESET% 正在等待重启至 lk2nd...
    timeout /t 12 /nobreak >nul
    
    echo %CYAN%[执行]%RESET% 提取基带...
    "%JB%" oem dump fsc && "%JB%" get_staged "%FIRMWARE_PATH%\fsc.bin"
    "%JB%" oem dump fsg && "%JB%" get_staged "%FIRMWARE_PATH%\fsg.bin"
    "%JB%" oem dump modemst1 && "%JB%" get_staged "%FIRMWARE_PATH%\modemst1.bin"
    "%JB%" oem dump modemst2 && "%JB%" get_staged "%FIRMWARE_PATH%\modemst2.bin"
    
    echo %CYAN%[执行]%RESET% 刷写分区表与底层...
    "%JB%" flash partition "%FIRMWARE_PATH%\gpt_both0.bin"
    "%JB%" flash hyp "%FIRMWARE_PATH%\hyp.mbn"
    "%JB%" flash rpm "%FIRMWARE_PATH%\rpm.mbn"
    "%JB%" flash sbl1 "%FIRMWARE_PATH%\sbl1.mbn"
    "%JB%" flash tz "%FIRMWARE_PATH%\tz.mbn"
    "%JB%" flash aboot "%FIRMWARE_PATH%\aboot.bin"
    "%JB%" flash cdt "%FIRMWARE_PATH%\sbc_1.0_8016.bin"
    
    echo %CYAN%[执行]%RESET% 恢复基带...
    if exist "%FIRMWARE_PATH%\fsc.bin" "%JB%" flash fsc "%FIRMWARE_PATH%\fsc.bin"
    if exist "%FIRMWARE_PATH%\fsg.bin" "%JB%" flash fsg "%FIRMWARE_PATH%\fsg.bin"
    if exist "%FIRMWARE_PATH%\modemst1.bin" "%JB%" flash modemst1 "%FIRMWARE_PATH%\modemst1.bin"
    if exist "%FIRMWARE_PATH%\modemst2.bin" "%JB%" flash modemst2 "%FIRMWARE_PATH%\modemst2.bin"
    
    "%JB%" reboot bootloader
    timeout /t 8 /nobreak >nul
)

if "%DO_BOOT%"=="1" (
    echo %CYAN%--- [阶段 2] 刷入内核 ---%RESET%
    "%JB%" flash boot "%BOOT_IMAGE_FILE%"
)

if "%DO_ROOTFS%"=="1" (
    echo %CYAN%--- [阶段 3] 刷入系统 ---%RESET%
    "%JB%" -S 180m flash rootfs "%ROOTFS_IMAGE_FILE%"
)

goto :finish_all

:execute_aboot
call :check_and_reboot_fastboot
"%JB%" flash aboot "%FIRMWARE_PATH%\lk1st.mbn"
"%JB%" reboot
pause & goto main_menu

:check_and_reboot_fastboot
echo %CYAN%[检测设备]%RESET% 正在扫描连接状态...
"%JB%" devices | find "fastboot" >nul
if %errorlevel% equ 0 exit /b
"%ADB%" devices | find "device" | find /v "List" >nul
if %errorlevel% equ 0 ("%ADB%" reboot bootloader)
:wait_fastboot_loop
ping 127.0.0.1 -n 2 >nul
"%JB%" devices | find "fastboot" >nul
if %errorlevel% equ 0 exit /b
goto wait_fastboot_loop

:finish_all
echo.
echo %GREEN%★★ 所有选定操作已顺利完成 ★★%RESET%
echo.
choice /C RM /N /M "%GREEN%下一步操作 (R=重启设备 / M=返回主菜单):%RESET% "
if "%errorlevel%"=="2" goto main_menu
"%JB%" reboot
goto main_menu