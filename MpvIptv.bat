@echo OFF
@setlocal enabledelayedexpansion
pushd %~dp0

set useragent=MpvIptv-Updater

where pwsh >nul 2>nul
if %errorlevel% equ 0 (
	set exec=pwsh
) else (
	set exec=powershell
)

%exec% -Command "& { Write-Host "!useragent! script v1.4.6" -ForegroundColor Green; }"

set 7zrUrl=https://www.7-zip.org/a/7zr.exe
set 7zaUrl=https://www.7-zip.org/a/7z2600-extra.7z
set curlUrl=https://curl.se/windows/dl-8.19.0_4/curl-8.19.0_4-win64-mingw.zip
set gzipUrl=https://github.com/ebiggers/libdeflate/releases/download/v1.25/libdeflate-1.25-windows-x86_64-bin.zip

set srcUrl=https://raw.githubusercontent.com/check4game/MpvIptv/refs/heads/main
set configUrl=!srcUrl!/portable_config

::set mpvApi=https://api.github.com/repos/zhongfly/mpv-winbuild/releases/latest
set mpvApi=https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest

set curPath=%~dp0
set binPath=!curPath!bin
set tempPath=!curPath!temp
set configPath=!curPath!portable_config

set EXECURL=!binPath!\curl.exe
set EXE7ZR=!binPath!\7zr.exe
set EXE7ZA=!binPath!\7za.exe
set EXEGZIP=!binPath!\gzip.exe

if not exist "!binPath!" (
	mkdir "!binPath!" > nul
)

if not exist "!tempPath!" (
	mkdir "!tempPath!" > nul
)

set 7ZR=^
if (-not (Test-Path "!EXE7ZR!")) {^
	Write-Host "Downloading !7zrUrl!" -ForegroundColor Green;^
	Invoke-WebRequest -Uri "!7zrUrl!" -UserAgent "!useragent!" -OutFile "!EXE7ZR!";^
}^
! 
%exec% -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "& {!7ZR!}"

if not exist "!EXE7ZR!" (
	%exec% -Command "& { Write-Host "no 7zr.exe in !binPath!" -ForegroundColor Red; }"
    pause
    exit /b 1
)

for /f %%i in ('%exec% -Command "('!7zaUrl!' -split '/')[-1]"') do set "7zaZip=%%i"

set 7ZA=^
if (-not (Test-Path "!EXE7ZA!")) {^
	Write-Host "Downloading !7zaUrl!" -ForegroundColor Green;^
	Invoke-WebRequest -Uri "!7zaUrl!" -UserAgent "!useragent!" -OutFile "!tempPath!\!7zaZip!";^
}^
! 
%exec% -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "& {!7ZA!}"

if exist "!tempPath!\!7zaZip!" (
	%exec% -Command "& { Write-Host "Extracting 7za.exe from !7zaZip!" -ForegroundColor Green; }"
	"!EXE7ZR!" e -y "!tempPath!\!7zaZip!" 7za.exe -o"!binPath!" > nul
	del /Q "!tempPath!\!7zaZip!" > nul
)

if not exist "!EXE7ZA!" (
	%exec% -Command "& { Write-Host "no 7za.exe in !binPath!" -ForegroundColor Red; }"
    pause
    exit /b 1
)

for /f %%i in ('%exec% -Command "('!curlUrl!' -split '/')[-1]"') do set "curlZip=%%i"

set CURL=^
if (-not (Test-Path "!EXECURL!")) {^
	Write-Host "Downloading !curlUrl!" -ForegroundColor Green;^
	Invoke-WebRequest -Uri "!curlUrl!" -UserAgent "!useragent!" -OutFile "!tempPath!\!curlZip!";^
}^
! 
%exec% -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "& {!CURL!}"

if exist "!tempPath!\!curlZip!" (
	%exec% -Command "& { Write-Host "Extracting curl.exe from !curlZip!" -ForegroundColor Green; }"
	"!EXE7ZA!" e -r -y "!tempPath!\!curlZip!" curl.exe -o"!binPath!" > nul
	del /Q "!tempPath!\!curlZip!" > nul
)

if not exist "!EXECURL!" (
	%exec% -Command "& { Write-Host "no curl.exe in !binPath!" -ForegroundColor Red; }"
    pause
    exit /b 1
)

"!EXECURL!" --compressed --no-progress-meter --user-agent "!useragent!" -RLo "!tempPath!\MpvIptv.bat" --fail "!srcUrl!/MpvIptv.bat"

if exist "!tempPath!\MpvIptv.bat" (
    fc "!tempPath!\MpvIptv.bat" "!curPath!\MpvIptv.bat" > nul 2>&1
    if errorlevel 1 (
		%exec% -Command "& { Write-Host "New version MpvIptv.bat" -ForegroundColor Green; }"
        copy /Y "!tempPath!\MpvIptv.bat" "!curPath!\MpvIptv.bat" > nul
	    del /Q "!tempPath!\MpvIptv.bat" > nul 2>&1
		call "!curPath!\MpvIptv.bat" %*
        exit /b
    )
    del /Q "!tempPath!\MpvIptv.bat" > nul 2>&1
)

for /f %%i in ('%exec% -Command "('!gzipUrl!' -split '/')[-1]"') do set "gzipZip=%%i"

set GZIP=^
if (-not (Test-Path "!EXEGZIP!")) {^
	Write-Host "Downloading !gzipUrl!" -ForegroundColor Green;^
	Invoke-WebRequest -Uri "!gzipUrl!" -UserAgent "!useragent!" -OutFile "!tempPath!\!gzipZip!";^
}^
! 
%exec% -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "& {!GZIP!}"

if exist "!tempPath!\!gzipZip!" (
	%exec% -Command "& { Write-Host "Extracting gzip.exe from !gzipZip!" -ForegroundColor Green; }"
	"!EXE7ZA!" e -r -y "!tempPath!\!gzipZip!" gzip.exe -o"!binPath!" > nul
	del /Q "!tempPath!\!gzipZip!" > nul
)

if not exist "!EXEGZIP!" (
	%exec% -Command "& { Write-Host "no gzip.exe in !binPath!" -ForegroundColor Red; }"
    pause
    exit /b 1
)

set MVPEXIST=$false

if not "%mpvApi%" == "%mpvApi:shinchiro=%" (
	if exist "!curPath!\mpv.com" if exist "!curPath!\mpv.exe" if exist "!curPath!\d3dcompiler_43.dll" (
		set MVPEXIST=$true
	)
) else (
	if exist "!curPath!\mpv.com" if exist "!curPath!\mpv.exe" (
		set MVPEXIST=$true
	)
)

set mpvZip=mpv.last.7z

set MPV=^
$filename = '';^
$downloadUrl = '';^
$apiUrl = '!mpvApi!';^
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
	Invoke-WebRequest -Uri $downloadUrl -UserAgent "!useragent!" -OutFile "!tempPath!\!mpvZip!";^
}^
! 
%exec% -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "& {!MPV!}"

if exist "!tempPath!\!mpvZip!" (
	%exec% -Command "& { Write-Host "Extracting mpv.exe from !mpvZip!" -ForegroundColor Green; }"
	"!EXE7ZA!" e -r -y "!tempPath!\!mpvZip!" mpv.exe -o"!curPath!" > nul
	%exec% -Command "& { Write-Host "Extracting mpv.com from !mpvZip!" -ForegroundColor Green; }"
	"!EXE7ZA!" e -r -y "!tempPath!\!mpvZip!" mpv.com -o"!curPath!" > nul
	if not "%mpvApi%" == "%mpvApi:shinchiro=%" (
		%exec% -Command "& { Write-Host "Extracting d3dcompiler_43.dll from !mpvZip!" -ForegroundColor Green; }"
		"!EXE7ZA!" e -r -y "!tempPath!\!mpvZip!" d3dcompiler_43.dll -o"!curPath!" > nul
	)
	del /Q "!tempPath!\!mpvZip!" > nul
)

set folders=fonts scripts script-opts
for %%f in (%folders%) do (
	if not exist "!configPath!\%%f" (
		mkdir "!configPath!\%%f" > nul
	)
)

if not exist "!configPath!\MpvIptv.json" (
	call :DownloadFile "MpvIptv.json"
)

if not exist "!configPath!\mpv.conf" (
	call :DownloadFile "mpv.conf"
)

call :DownloadFile "MpvIptv.mp4"
call :DownloadFile "fonts/modernz-icons.ttf"

set scripts=modernz.lua MpvIptv.lua pip_lite.lua
for %%f in (%scripts%) do (
	call :DownloadFile "scripts/%%f"
)

set script-opts=dkjson.lua htmlEntities.lua modernz.conf modernz-locale.json MpvIptvGroups.lua MpvIptvString.lua MpvIptvUtf8.lua MpvIptvUtils.lua sha2.lua
for %%f in (%script-opts%) do (
	call :DownloadFile "script-opts/%%f"
)

pause
goto :eof

:DownloadFile
set "etag=%~1"
set "etag=!etag:/=.!.etag"

if exist "!tempPath!\!etag!" (
	%exec% -Command "& { Write-Host "Updating %~1" -ForegroundColor Green; }"
	"!EXECURL!" --compressed --no-progress-meter --user-agent "!useragent!" --etag-save "!tempPath!\!etag!" --etag-compare "!tempPath!\!etag!" -RLo "!configPath!\%~1" --fail "!configUrl!/%~1"
) else (
	%exec% -Command "& { Write-Host "Downloading %~1" -ForegroundColor Green; }"
	"!EXECURL!" --compressed --no-progress-meter --user-agent "!useragent!" --etag-save "!tempPath!\!etag!" -RLo "!configPath!\%~1" --fail "!configUrl!/%~1"
)

exit /b 1
goto :eof