@echo off
cd /d "%~dp0.."
echo === Evergreen Base — 重新编译 ===
echo 已安装插件:
dir /b plugins 2>nul
echo.
echo 重新获取依赖...
call flutter pub get
if %errorlevel% neq 0 (echo 失败! && pause && exit /b 1)
echo 编译中...
call flutter build windows --release
if %errorlevel% neq 0 (echo 编译失败! && pause && exit /b 1)
del plugins\_need_rebuild 2>nul
echo === 完成 ===
pause
