# MpvIptv Player v1.2.6
Приложение просмотра IPTV потоков для Windows

![MpvIptv Player main screen](/screenshots/s01.png)

## Установка и запуск приложения
1. достаточно создать папку на локальном диске C:\MpvIptv или с любым другим названием, папку также можно создать на рабочем столе и сохранить последнюю версию файла MpvIptv.bat
2. Запустить MpvIptv.bat, скрипт установки/обновления до актуальной версии приложения
3. Запустить mpv.exe (Mpv Player)

## Списки m3u IPTV потоков
1. Конфигурация списков m3u IPTV находится в файле portable_config\MpvIptv.json, можно добавлять свои.
2. Списки по умолчанию взяты из репозитария https://github.com/smolnp/IPTVru

## Программа для IPTV потоков
1. Поддерживается EPG в формате xml или xml.gz
2. Ссылка на файл EPG автоматически выбирается из файла со списком m3u IPTV потоков.

## Внешние скрипты, библиотеки, утилиты и приложения:
1. Mpv Player, https://github.com/mpv-player/mpv, исполняемые файлы загружаются из репозитария [shinchiro/mpv-winbuild-cmake](https://github.com/shinchiro/mpv-winbuild-cmake/releases)<br>
3. ModernZ script, Атернативная OSC для Mpv Player, https://github.com/Samillion/ModernZ<br>
Набор скриптов находится в репозитарии MpvIptv, базируется на версии ModernZ v0.3.1 с небольшими доработками<br>
5. Библиотека [dkjson.lua](https://dkolf.de/dkjson-lua), v2.8, находится в репозитарии MpvIptv<br>
6. Библиотека [htmlEntities.lua](https://github.com/TiagoDanin/htmlEntities-for-lua), v1.3.1, находится в репозитарии MpvIptv<br>
7. Библиотека [sha2.lua](https://github.com/Egor-Skriptunoff/pure_lua_SHA), v12/2022-02-23, находится в репозитарии MpvIptv<br>
8. Утилита [7zr.exe](https://www.7-zip.org/a/7zr.exe), загружается при установке<br>
9. Утилита [7za.exe](https://www.7-zip.org/a/7z2600-extra.7z), загружается при установке из архива<br>
10. Утилита [curl.exe](https://curl.se/windows/dl-8.19.0_4/curl-8.19.0_4-win64-mingw.zip), загружается при установке из архива<br>
11. Утилита [gzip.exe](https://github.com/ebiggers/libdeflate/releases/download/v1.25/libdeflate-1.25-windows-x86_64-bin.zip), загружается при установке из архива <br>





