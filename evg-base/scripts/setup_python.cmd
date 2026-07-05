@echo off
echo === Evergreen Base — Setup Python ===
set PYDIR=%~dp0python
if exist "%PYDIR%\python.exe" (
  echo Python already installed at %PYDIR%
  goto :deps
)

echo Downloading Python 3.10 embed...
curl -L -o python-embed.zip https://www.python.org/ftp/python/3.10.11/python-3.10.11-embed-amd64.zip
powershell -Command "Expand-Archive -Path python-embed.zip -DestinationPath '%PYDIR%' -Force"
del python-embed.zip

:: Enable pip
for %%f in ("%PYDIR%\python*._pth") do (
  powershell -Command "(Get-Content '%%f') -replace '#import site', 'import site' | Set-Content '%%f'"
)
curl -L -o "%PYDIR%\get-pip.py" https://bootstrap.pypa.io/get-pip.py
"%PYDIR%\python.exe" "%PYDIR%\get-pip.py" --no-warn-script-location

:deps
echo Installing OCR dependencies...
"%PYDIR%\python.exe" -m pip install -r "%~dp0requirements.txt" --no-warn-script-location
echo === Done ===
pause
