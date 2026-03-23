@echo OFF
@setlocal enabledelayedexpansion
pushd %~dp0

set useragent=MpvIptv-Updater

set 7zrUrl=https://www.7-zip.org/a/7zr.exe
set 7zaUrl=https://www.7-zip.org/a/7z2600-extra.7z
set curlUrl=https://curl.se/windows/dl-8.19.0_4/curl-8.19.0_4-win64-mingw.zip

set srcUrl=https://raw.githubusercontent.com/check4game/MpvIptv/refs/heads/main/portable_config

set curPath=%~dp0
set binPath=!curPath!\bin
set configPath=!curPath!\portable_config

where pwsh >nul 2>nul
if %errorlevel% equ 0 (
	set exec=pwsh
) else (
	set exec=powershell
)

set 7ZR=^
if (-not (Test-Path "!binPath!\7zr.exe")) {^
	$null = New-Item -ItemType Directory -Force (Split-Path "!binPath!\7zr.exe");^
	Write-Host "Downloading !7zrUrl!" -ForegroundColor Green;^
	Invoke-WebRequest -Uri "!7zrUrl!" -UserAgent "!useragent!" -OutFile "!binPath!\7zr.exe";^
}^
! 
%exec% -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "& {!7ZR!}"

if not exist "!binPath!\7zr.exe" (
	%exec% -Command "& { Write-Host "no 7zr.exe in !binPath!" -ForegroundColor Red; }"
    pause
    exit /b 1
)

for /f %%i in ('%exec% -Command "('!7zaUrl!' -split '/')[-1]"') do set "7zaZip=%%i"

set 7ZA=^
if (-not (Test-Path "!binPath!\7za.exe")) {^
	$null = New-Item -ItemType Directory -Force (Split-Path "!binPath!\7za.exe");^
	Write-Host "Downloading !7zaUrl!" -ForegroundColor Green;^
	Invoke-WebRequest -Uri "!7zaUrl!" -UserAgent "!useragent!" -OutFile "!binPath!\!7zaZip!";^
}^
! 
%exec% -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "& {!7ZA!}"

if exist "!binPath!\!7zaZip!" (
	%exec% -Command "& { Write-Host "Extracting 7za.exe from !7zaZip!" -ForegroundColor Green; }"
	"!binPath!\7zr.exe" e -y "!binPath!\!7zaZip!" 7za.exe -o"!binPath!" > nul
	del /Q "!binPath!\!7zaZip!" > nul
)

if not exist "!binPath!\7za.exe" (
	%exec% -Command "& { Write-Host "no 7za.exe in !binPath!" -ForegroundColor Red; }"
    pause
    exit /b 1
)

for /f %%i in ('%exec% -Command "('!curlUrl!' -split '/')[-1]"') do set "curlZip=%%i"

set CURL=^
if (-not (Test-Path "!binPath!\curl.exe")) {^
	$null = New-Item -ItemType Directory -Force (Split-Path "!binPath!\curl.exe");^
	Write-Host "Downloading !curlUrl!" -ForegroundColor Green;^
	Invoke-WebRequest -Uri "!curlUrl!" -UserAgent "!useragent!" -OutFile "!binPath!\!curlZip!";^
}^
! 

if not exist "!binPath!\curl.exe" (
	%exec% -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "& {!CURL!}"
)

if exist "!binPath!\!curlZip!" (
	%exec% -Command "& { Write-Host "Extracting curl.exe from !curlZip!" -ForegroundColor Green; }"
	"!binPath!\7za.exe" e -r -y "!binPath!\!curlZip!" curl.exe -o"!binPath!" > nul
	del /Q "!binPath!\!curlZip!" > nul
)

if not exist "!binPath!\curl.exe" (
	%exec% -Command "& { Write-Host "no curl.exe in !binPath!" -ForegroundColor Red; }"
    pause
    exit /b 1
)

set MVPEXIST=$false
if exist "%~dp0\mpv.com" if exist "%~dp0\mpv.exe" (
set MVPEXIST=$true
)

set mpvZip=mpv.last.7z

set MPV=^
$filename = '';^
$downloadUrl = '';^
$apiUrl = 'https://api.github.com/repos/zhongfly/mpv-winbuild/releases/latest';^
Write-Host "Checking" $apiUrl -ForegroundColor Green;^
$json = Invoke-WebRequest $apiUrl -MaximumRedirection 0 -ErrorAction Ignore -UseBasicParsing -UserAgent "!useragent!" ^| ConvertFrom-Json;^
$filename = $json.assets ^| where { $_.name -Match 'mpv-x86_64-[0-9]{8}' } ^| Select-Object -ExpandProperty name;^
$downloadUrl = $json.assets ^| where { $_.name -Match 'mpv-x86_64-[0-9]{8}' } ^| Select-Object -ExpandProperty browser_download_url;^
if ($filename -is [array]) {^
$filename = $filename[0];^
$downloadUrl = $downloadUrl[0];^
}^
$bDownload=$true;^
if (!MVPEXIST!) {^
	$stripped = .\mpv --no-config ^| select-string "mpv" ^| select-object -First 1;^
	$bool = $stripped -match '-g([a-z0-9-]{7})';^
	$lBuild =$matches[1];^
	$bool = $filename -match '-git-([a-z0-9-]{7})';^
	$gBuild =$matches[1];^
	if ($lBuild -match $gBuild) { $bDownload=$false; } else { Write-Host "Local build is " $lBuild -ForegroundColor Green; }^
}^
if ($bDownload) {^
	Write-Host 'Downloading' $downloadUrl -ForegroundColor Green;^
	Invoke-WebRequest -Uri $downloadUrl -UserAgent "!useragent!" -OutFile "!binPath!\!mpvZip!";^
}^
! 

%exec% -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "& {!MPV!}"

if exist "!binPath!\!mpvZip!" (
	%exec% -Command "& { Write-Host "Extracting mpv.exe from !mpvZip!" -ForegroundColor Green; }"
	"!binPath!\7za.exe" e -r -y "!binPath!\!mpvZip!" mpv.exe -o"!curPath!" > nul
	%exec% -Command "& { Write-Host "Extracting mpv.com from !mpvZip!" -ForegroundColor Green; }"
	"!binPath!\7za.exe" e -r -y "!binPath!\!mpvZip!" mpv.com -o"!curPath!" > nul
	del /Q "!binPath!\!mpvZip!" > nul
)

set dirs=temp fonts scripts script-opts
for %%f in (%scripts%) do (
	if not exist "!configPath!\%%f" (
		mkdir "!configPath!\%%f" > nul
	)
)

if not exist "!configPath!\MpvIptv.json" (
	call :DownloadFile "MpvIptv.json"
)

call :DownloadFile "mpv.conf"
call :DownloadFile "MpvIptv.mp4"
call :DownloadFile "fonts/modernz-icons.ttf"
set scripts=modernz.lua MpvIptv.lua pip_lite.lua
for %%f in (%scripts%) do (
	call :DownloadFile "scripts/%%f"
)
set script-opts=dkjson.lua htmlEntities.lua modernz-locale.json MpvIptvGroups.lua MpvIptvString.lua MpvIptvUtf8.lua MpvIptvUtils.lua sha2.lua
for %%f in (%script-opts%) do (
	call :DownloadFile "script-opts/%%f"
)

pause
goto :eof

:DownloadFile
if exist "!configPath!\%~1" (
	%exec% -Command "& { Write-Host "Updating %~1" -ForegroundColor Green; }"
	"!binPath!\curl.exe" --compressed --no-progress-meter -RLo "!configPath!\%~1" --fail -z "!configPath!\%~1" "!srcUrl!/%~1"
) else (
	%exec% -Command "& { Write-Host "Downloading %~1" -ForegroundColor Green; }"
	"!binPath!\curl.exe" --compressed --no-progress-meter -RLo "!configPath!\%~1" --fail "!srcUrl!/%~1"
)

exit /b 1
goto :eof