@echo off
@title UFI001C Armbian ȫ��ˢ������
color 0A
mode con cols=105 lines=50

:: =============================================================================================
:: �����ļ�·������������ά��
:: =============================================================================================
set "FASTBOOT_PATH=%~dp0fastboot"
set "FIRMWARE_PATH=%~dp0firmware"
set "IMAGES_PATH=%~dp0images"

:main
cls
echo =============================================================================================
echo.
echo                   ��ӭʹ�� UFI001C Armbian ȫ��ˢ������
echo.
echo      ���ű���������������в��裬�������ݡ�ˢд�ײ�̼��Ͱ�װ Armbian ϵͳ��
echo     - �����桿��ȷ�� 'images' �ļ�����ֻ��һ�� Armbian �汾�� boot �� rootfs ����
echo.
echo =============================================================================================
echo.

:: 1. ����豸����
echo [���� 1/7] ���ڼ���豸����...
echo.
echo --- ���ADB�豸 (��׿ģʽ) ---
"%FASTBOOT_PATH%\adb.exe" devices -l | find "device product:" >nul
if errorlevel 1 (
    echo [��ʾ] ADB�豸δ���ӡ�����豸����Fastbootģʽ������ʾ�ɺ��ԡ�
) else (
    echo [�ɹ�] ADB�豸�����ӡ�
)
echo.
echo --- ���Fastboot�豸 (ˢ��ģʽ) ---
"%FASTBOOT_PATH%\fastboot.exe" devices
echo.

:: 2. �û�ȷ��
echo ------------------------------------- [ !! ��Ҫ���� !! ] --------------------------------------
echo.
echo   �˲���������ȫ�������豸�ϵ��������ݣ�ˢ���з��գ������������
echo   ��ȷ���ѱ��ݺø������ݣ�������USB�����ȶ���
echo.
echo -----------------------------------------------------------------------------------------------
echo.
set /p confirm="׼���������밴 �س���(Enter) ֱ�ӿ�ʼ�������� N �˳�: "
if /i "%confirm%"=="N" (
    echo.
    echo [����ȡ��] �û���ѡ���˳�ˢ����
    pause
    exit
)

:: ===================================================================================================
::  �ؼ����裺ˢд lk2nd �Խ��а�ȫ����
:: ===================================================================================================
echo.
echo [���� 2/7] ����ˢд��ʱ�������� (lk2nd) �Խ��а�ȫ����...
echo.
"%FASTBOOT_PATH%\adb.exe" reboot bootloader >nul 2>&1
timeout /t 2 /nobreak >nul

"%FASTBOOT_PATH%\fastboot.exe" flash boot "%FIRMWARE_PATH%\lk2nd.img"
echo ���������� lk2nd ��ʱ����...
"%FASTBOOT_PATH%\fastboot.exe" reboot
echo.
echo �����Զ�����豸���������Ժ� (��ȴ� 30 ��)...
set /a countdown=30

:waitForLk2nd
if %countdown% leq 0 (
    echo.
    echo.
    echo [����] �ȴ��豸�������ӳ�ʱ��
    echo ����USB���Ӻ���������Ȼ���������нű���
    pause
    goto :eof
)
"%FASTBOOT_PATH%\fastboot.exe" devices | findstr "fastboot" > nul
if %errorlevel% equ 0 (
echo.
    echo [�ɹ�] �豸���� lk2nd Fastboot ģʽ�����ӣ�
    goto :continueToBackup
)
set /p ".=." <nul
timeout /t 1 /nobreak >nul
set /a countdown-=1
goto waitForLk2nd

:continueToBackup
echo.
echo [���� 3/7] ���ڱ�����ƵУ׼���� (fsc, fsg, modemst1, modemst2)...
echo.
"%FASTBOOT_PATH%\fastboot.exe" oem dump fsc && "%FASTBOOT_PATH%\fastboot.exe" get_staged "%FIRMWARE_PATH%\fsc.bin"
"%FASTBOOT_PATH%\fastboot.exe" oem dump fsg && "%FASTBOOT_PATH%\fastboot.exe" get_staged "%FIRMWARE_PATH%\fsg.bin"
"%FASTBOOT_PATH%\fastboot.exe" oem dump modemst1 && "%FASTBOOT_PATH%\fastboot.exe" get_staged "%FIRMWARE_PATH%\modemst1.bin"
"%FASTBOOT_PATH%\fastboot.exe" oem dump modemst2 && "%FASTBOOT_PATH%\fastboot.exe" get_staged "%FIRMWARE_PATH%\modemst2.bin"
echo.
echo [�ɹ�] �ؼ������ѱ����� 'firmware' �ļ��С�
timeout /t 2 /nobreak
echo.

:: ===================================================================================================
::  ������ʱ��������ʼˢд�ײ�
:: ===================================================================================================
echo [���� 4/7] ����ˢд�ײ�̼��ͷ�����...
echo.
echo ������ʱ������������Bootloader...
"%FASTBOOT_PATH%\fastboot.exe" erase boot
"%FASTBOOT_PATH%\fastboot.exe" reboot bootloader
echo �ȴ��豸�ٴν���Bootloader...
timeout /t 5 /nobreak >nul

"%FASTBOOT_PATH%\fastboot.exe" flash partition "%FIRMWARE_PATH%\gpt_both0.bin"
"%FASTBOOT_PATH%\fastboot.exe" flash hyp "%FIRMWARE_PATH%\hyp.mbn"
"%FASTBOOT_PATH%\fastboot.exe" flash rpm "%FIRMWARE_PATH%\rpm.mbn"
"%FASTBOOT_PATH%\fastboot.exe" flash sbl1 "%FIRMWARE_PATH%\sbl1.mbn"
"%FASTBOOT_PATH%\fastboot.exe" flash tz "%FIRMWARE_PATH%\tz.mbn"
"%FASTBOOT_PATH%\fastboot.exe" flash aboot "%FIRMWARE_PATH%\aboot.bin"
"%FASTBOOT_PATH%\fastboot.exe" flash cdt "%FIRMWARE_PATH%\sbc_1.0_8016.bin"
echo.

echo [���� 5/7] ���ڻָ��ؼ�������������ϵͳ...
echo.
"%FASTBOOT_PATH%\fastboot.exe" flash fsc "%FIRMWARE_PATH%\fsc.bin"
"%FASTBOOT_PATH%\fastboot.exe" flash fsg "%FIRMWARE_PATH%\fsg.bin"
"%FASTBOOT_PATH%\fastboot.exe" flash modemst1 "%FIRMWARE_PATH%\modemst1.bin"
"%FASTBOOT_PATH%\fastboot.exe" flash modemst2 "%FIRMWARE_PATH%\modemst2.bin"
echo.
echo ���ڲ���boot��rootfs�����Ա�ˢд...
"%FASTBOOT_PATH%\fastboot.exe" erase boot
"%FASTBOOT_PATH%\fastboot.exe" erase rootfs
echo.

echo ���������豸��Ӧ���µķ�����... �뱣�����ӣ�
echo.
"%FASTBOOT_PATH%\fastboot.exe" reboot bootloader
echo.
echo �����Զ�����豸���������Ժ� (��ȴ� 30 ��)...
set /a countdown=30

:waitForFinalBootloader
if %countdown% leq 0 (
    echo.
    echo.
    echo [����] �ȴ��豸�������ӳ�ʱ��
    echo ����USB���Ӻ���������Ȼ���������нű���
    pause
    goto :eof
)
"%FASTBOOT_PATH%\fastboot.exe" devices | findstr "fastboot" > nul
if %errorlevel% equ 0 (
    echo.
    echo [�ɹ�] �豸�����·����������ӣ�׼��ˢ�� Armbian ϵͳ...
    goto :continueToFlashArmbian
)
set /p ".=." <nul
timeout /t 1 /nobreak >nul
set /a countdown-=1
goto waitForFinalBootloader

:continueToFlashArmbian
echo.

:: ===================================================================================================
::  �Զ����Ҳ�ˢд Armbian
:: ===================================================================================================
echo [���� 6/7] �����Զ����� Armbian ϵͳ����...
echo.
set "ROOTFS_IMAGE_FILE="
set "BOOT_IMAGE_FILE="

:: ������������ boot.img �ļ�
for %%F in ("%IMAGES_PATH%\Armbian*.boot.img") do (
    set "BOOT_IMAGE_FILE=%%~fF"
)

:: ���� rootfs.img �ļ� (·����ʽ��Ϊ %%~fF)
for %%F in ("%IMAGES_PATH%\Armbian*.rootfs.img") do (
    set "ROOTFS_IMAGE_FILE=%%~fF"
)

:: ���޸ġ���� boot.img �Ƿ��ҵ�
if not defined BOOT_IMAGE_FILE (
    echo [����] �� 'images' �ļ�����û���ҵ�ƥ�� 'Armbian*.boot.img' ���ļ���
    echo �����ļ����Ƿ���ȷ�������ļ��Ƿ���ڡ�
    pause
    exit
)
if not defined ROOTFS_IMAGE_FILE (
    echo [����] �� 'images' �ļ�����û���ҵ�ƥ�� 'Armbian*.rootfs.img' ���ļ���
    echo �����ļ����Ƿ���ȷ�������ļ��Ƿ���ڡ�
    pause
    exit
)

echo [�ɹ�] �Զ���⵽ϵͳ����Ϊ:
echo   Boot   : "%BOOT_IMAGE_FILE%"
echo   Rootfs : "%ROOTFS_IMAGE_FILE%"
echo.

echo [���� 7/7] ����ˢ���µ� Armbian ϵͳ...
echo   �˹��̿�����Ҫ�����ӣ������ĵȴ�����Ҫ�Ͽ�USB���ӣ�
echo.
echo --- ����ˢ�� boot ���� ---
"%FASTBOOT_PATH%\fastboot.exe" flash boot "%BOOT_IMAGE_FILE%"
echo.
echo --- ����ˢ�� rootfs ���� (���ļ��������ĵȴ�) ---
"%FASTBOOT_PATH%\fastboot.exe" -S 200m flash rootfs "%ROOTFS_IMAGE_FILE%"
echo.

:: ===================================================================================================
::  ���
:: ===================================================================================================
echo ===================================================================================================
echo.
echo [�ɹ�] ˢ��������ȫ����ɣ�
echo.
echo �豸���� 5 ����Զ�����������ϵͳ��ף��ʹ����죡
echo.
echo ===================================================================================================

timeout /t 5 /nobreak
"%FASTBOOT_PATH%\fastboot.exe" reboot

echo.
echo ������ɣ���������˳����ڡ�
pause >nul

exit
