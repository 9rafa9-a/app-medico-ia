@echo off
set ADB_PATH=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
echo Looking for ADB at: %ADB_PATH%

if exist "%ADB_PATH%" (
    echo ADB Found! Listing devices:
    "%ADB_PATH%" devices
    
    echo.
    echo Capturing Logcat (Buffer)...
    "%ADB_PATH%" logcat -d -v time > android_debug.log
    
    echo.
    echo DONE. Log saved to android_debug.log
) else (
    echo ADB NOT FOUND at path.
)
