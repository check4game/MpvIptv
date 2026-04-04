@echo OFF
@setlocal enabledelayedexpansion
pushd %~dp0

:: sync with MpvIptv version
set useragent="MpvIptv-Updater-Script/v1.2.6"

where pwsh >nul 2>nul
if %errorlevel% equ 0 (
	set ps=pwsh
) else (
	set ps=powershell
)

set ps=%ps% -NoProfile -NoLogo -ExecutionPolicy Bypass -Command

for /f %%i in ('%ps% "((Get-CimInstance Win32_OperatingSystem).Caption) -like '*Windows 1*'"') do set "Windows1X=%%i"

if not "!Windows1X!" == "True" (
	call :ShowErrorMessage "Only Windows 10 or Windows 11"
	goto :END
)

set 7zrUrl=https://www.7-zip.org/a/7zr.exe
set 7zaUrl=https://www.7-zip.org/a/7z2600-extra.7z
set curlUrl=https://curl.se/windows/dl-8.19.0_4/curl-8.19.0_4-win64-mingw.zip
set gzipUrl=https://github.com/ebiggers/libdeflate/releases/download/v1.25/libdeflate-1.25-windows-x86_64-bin.zip

:: direct link
set mpvUrl=https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260307/mpv-x86_64-20260307-git-f9190e5.7z
:set mpvUrl=https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260307/mpv-x86_64-v3-20260307-git-f9190e5.7z

:: repos api link
::set mpvApi=https://api.github.com/repos/zhongfly/mpv-winbuild/releases/latest
set mpvApi=https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest

:: main repos link
set mainUrl=https://raw.githubusercontent.com/check4game/MpvIptv/refs/heads/main
::: MpvIptv v1.2.3
set srcUrl=https://raw.githubusercontent.com/check4game/MpvIptv/5eb7ffbd95b7400208b1f33a9fce85d2cbd1a8ec
::: MpvIptv v1.2.4
set srcUrl=https://raw.githubusercontent.com/check4game/MpvIptv/8a8c49ed7831e67957b4ca52cdce632cca9a0443
::: MpvIptv v1.2.5
set srcUrl=https://raw.githubusercontent.com/check4game/MpvIptv/17540a841253ecfaf68901b93c7968c8aaad95dc
::: MpvIptv v1.2.6
set srcUrl=https://raw.githubusercontent.com/check4game/MpvIptv/4e6e3bd9f64d516d0520c018ee162c00ac85b06b

set configUrl=!srcUrl!/portable_config

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

call :CheckAndDownloadFile "!tempPath!\MpvIptv.bat.dummy" "!mainUrl!/MpvIptv.bat" "!tempPath!\MpvIptv.bat.temp"
if exist "!tempPath!\MpvIptv.bat.temp" (
    fc "!tempPath!\MpvIptv.bat.temp" "!curPath!\MpvIptv.bat" > nul 2>&1
    if errorlevel 1 (
		call :ShowMessage "New version found MpvIptv.bat"
        copy /Y "!tempPath!\MpvIptv.bat.temp" "!curPath!\MpvIptv.bat" > nul
	    del /Q "!tempPath!\MpvIptv.bat.temp" > nul 2>&1
		call "!curPath!\MpvIptv.bat" %*
        exit /b 1
    )
	call :ShowMessage !USERAGENT!
    del /Q "!tempPath!\MpvIptv.bat.temp" > nul 2>&1
) else (
	call :ShowMessage !USERAGENT!
)

call :CheckAndDownloadFile "!EXE7ZR!" "!7zrUrl!" "!EXE7ZR!"
if not exist "!EXE7ZR!" (
	call :ShowErrorMessage "no 7zr.exe in !binPath!"
	goto :END
) else (
	call :ShowMessage "7zr.exe OK in !binPath!"
)

for /f %%i in ('%ps% "('!7zaUrl!' -split '/')[-1]"') do set "7zaZip=%%i"
call :CheckAndDownloadFile "!EXE7ZA!" "!7zaUrl!" "!tempPath!\!7zaZip!"
if exist "!tempPath!\!7zaZip!" (
	call :ShowMessage "Extracting 7za.exe from !7zaZip!"
	"!EXE7ZR!" e -y "!tempPath!\!7zaZip!" 7za.exe -o"!binPath!" > nul
	del /Q "!tempPath!\!7zaZip!" > nul
)
if not exist "!EXE7ZA!" (
	call :ShowErrorMessage "no 7za.exe in !binPath!"
	goto :END
) else (
	call :ShowMessage "7za.exe OK in !binPath!"
)

for /f %%i in ('%ps% "('!curlUrl!' -split '/')[-1]"') do set "curlZip=%%i"
call :CheckAndDownloadFile "!EXECURL!" "!curlUrl!" "!tempPath!\!curlZip!"
if exist "!tempPath!\!curlZip!" (
	call :ShowMessage "Extracting curl.exe from !curlZip!"
	"!EXE7ZA!" e -r -y "!tempPath!\!curlZip!" curl.exe -o"!binPath!" > nul
	del /Q "!tempPath!\!curlZip!" > nul
)
if not exist "!EXECURL!" (
	call :ShowErrorMessage "no curl.exe in !binPath!"
	goto :END
) else (
	call :ShowMessage "curl.exe OK in !binPath!"
)

for /f %%i in ('%ps% "('!gzipUrl!' -split '/')[-1]"') do set "gzipZip=%%i"
call :CheckAndDownloadFile "!EXEGZIP!" "!gzipUrl!" "!tempPath!\!gzipZip!"
if exist "!tempPath!\!gzipZip!" (
	call :ShowMessage "Extracting gzip.exe from !gzipZip!"
	"!EXE7ZA!" e -r -y "!tempPath!\!gzipZip!" gzip.exe -o"!binPath!" > nul
	del /Q "!tempPath!\!gzipZip!" > nul
)
if not exist "!EXEGZIP!" (
	call :ShowErrorMessage "no gzip.exe in !binPath!"
	goto :END
) else (
	call :ShowMessage "gzip.exe OK in !binPath!"
)

set mpvZip=mpv.last.7z

if defined mpvUrl (
	for /f %%i in ('%ps% "('!mpvUrl!' -split '/')[-1]"') do set "mpvZip=%%i"
	set bDownloadMpv=True
	if not "%mpvUrl%" == "%mpvUrl:shinchiro=%" (
		if exist "!curPath!\mpv.com" if exist "!curPath!\mpv.exe" if exist "!curPath!\d3dcompiler_43.dll" (
			set bDownloadMpv=False
		)
	) else (
		if exist "!curPath!\mpv.com" if exist "!curPath!\mpv.exe" (
			set bDownloadMpv=False
		)
	)
	if "!bDownloadMpv!" == "True" (
		call :CheckAndDownloadFile "!tempPath!\!mpvZip!.dummy" "!mpvUrl!" "!tempPath!\!mpvZip!"
	)
) else (
	set mpvUrl="!mpvApi!"
	call :CheckMpvLastBuild
)

if exist "!tempPath!\!mpvZip!" (
	%ps% "& { Write-Host "Extracting mpv.exe from !mpvZip!" -ForegroundColor Green; }"
	"!EXE7ZA!" e -r -y "!tempPath!\!mpvZip!" mpv.exe -o"!curPath!" > nul
	%ps% "& { Write-Host "Extracting mpv.com from !mpvZip!" -ForegroundColor Green; }"
	"!EXE7ZA!" e -r -y "!tempPath!\!mpvZip!" mpv.com -o"!curPath!" > nul
	if not "%mpvUrl%" == "%mpvUrl:shinchiro=%" (
		%ps% "& { Write-Host "Extracting d3dcompiler_43.dll from !mpvZip!" -ForegroundColor Green; }"
		"!EXE7ZA!" e -r -y "!tempPath!\!mpvZip!" d3dcompiler_43.dll -o"!curPath!" > nul
	)
	del /Q "!tempPath!\!mpvZip!" > nul
)

set bMpvOK=False
if not "%mpvUrl%" == "%mpvUrl:shinchiro=%" (
	if exist "!curPath!\mpv.com" if exist "!curPath!\mpv.exe" if exist "!curPath!\d3dcompiler_43.dll" (
		set bMpvOK=True
	)
) else (
	if exist "!curPath!\mpv.com" if exist "!curPath!\mpv.exe" (
		set bMpvOK=True
	)
)

if "!bMpvOK!" == "False" (
	call :ShowErrorMessage "no mpv in !curPath!"
	goto :END
)

set folders=fonts scripts script-opts
for %%f in (%folders%) do (
	if not exist "!configPath!\%%f" (
		mkdir "!configPath!\%%f" > nul
	)
)

if not exist "!configPath!\MpvIptv.json" (
	call :SyncOrDownloadFile "MpvIptv.json"
)

if not exist "!configPath!\mpv.conf" (
	call :SyncOrDownloadFile "mpv.conf"
)

call :SyncOrDownloadFile "MpvIptv.mp4"
call :SyncOrDownloadFile "fonts/modernz-icons.ttf"

set scripts=modernz.lua MpvIptv.lua pip_lite.lua
for %%f in (%scripts%) do (
	call :SyncOrDownloadFile "scripts/%%f"
)

set script-opts=dkjson.lua htmlEntities.lua modernz.conf modernz-locale.json MpvIptvGroups.lua MpvIptvString.lua MpvIptvUtf8.lua MpvIptvUtils.lua sha2.lua
for %%f in (%script-opts%) do (
	call :SyncOrDownloadFile "script-opts/%%f"
)

goto :END

:ShowMessage
%ps% ". { Write-Host '%~1' -ForegroundColor Green; }"
exit /b 1
goto :eof

:ShowErrorMessage
%ps% ". { Write-Host '%~1' -ForegroundColor Red; }"
exit /b 1
goto :eof

:CheckAndDownloadFile
set SCRIPT=^
if (-not (Test-Path '%~1')) {^
	Write-Host 'Downloading %~2' -ForegroundColor Green;^
	Invoke-WebRequest -Uri '%~2' -UserAgent '!USERAGENT!' -OutFile '%~3';^
}^
! 
%ps% ". {!SCRIPT!}"
exit /b 1
goto :eof

:SyncOrDownloadFile
set "etag=%~1"
set "etag=!etag:/=.!.etag"

if exist "!configPath!\%~1" if exist "!tempPath!\!etag!" (
	%ps% ". { Write-Host 'Syncing %~1' -ForegroundColor Green; }"
	"!EXECURL!" --compressed --no-progress-meter --user-agent "!USERAGENT!" --etag-save "!tempPath!\!etag!" --etag-compare "!tempPath!\!etag!" -RLo "!configPath!\%~1" --fail "!configUrl!/%~1"
) else (
	%ps% ". { Write-Host 'Downloading %~1' -ForegroundColor Green; }"
	"!EXECURL!" --compressed --no-progress-meter --user-agent "!USERAGENT!" --etag-save "!tempPath!\!etag!" -RLo "!configPath!\%~1" --fail "!configUrl!/%~1"
)

exit /b 1
goto :eof

:CheckMpvLastBuild
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

set MPV=^
$filename = '';^
$downloadUrl = '';^
Write-Host 'Checking !mpvApi!' -ForegroundColor Green;^
$json = Invoke-WebRequest '!mpvApi!' -MaximumRedirection 0 -ErrorAction Ignore -UseBasicParsing -UserAgent '!USERAGENT!' ^| ConvertFrom-Json;^
$filename = $json.assets ^| where { $_.name -Match 'mpv-x86_64-[0-9]{8}' } ^| Select-Object -ExpandProperty name;^
$downloadUrl = $json.assets ^| where { $_.name -Match 'mpv-x86_64-[0-9]{8}' } ^| Select-Object -ExpandProperty browser_download_url;^
if ($filename -is [array]) {^
	$filename = $filename[0];^
	$downloadUrl = $downloadUrl[0];^
}^
$bDownload=$true;^
if (!MVPEXIST!) {^
	$stripped = .\mpv --no-config ^| select-string 'mpv' ^| select-object -First 1;^
	$bool = $stripped -match '-g([a-z0-9-]{7})';^
	$lBuild =$matches[1];^
	$bool = $filename -match '-git-([a-z0-9-]{7})';^
	$gBuild =$matches[1];^
	if ($lBuild -match $gBuild) { $bDownload=$false; } else { Write-Host 'Local build is ' $lBuild -ForegroundColor Green; }^
}^
if ($bDownload) {^
	Write-Host 'Downloading' $downloadUrl -ForegroundColor Green;^
	Invoke-WebRequest -Uri $downloadUrl -UserAgent '!USERAGENT!' -OutFile '!tempPath!\!mpvZip!';^
}^
! 
%ps% ". {!MPV!}"

exit /b 1
goto :eof

:END
pause
exit /b 1
