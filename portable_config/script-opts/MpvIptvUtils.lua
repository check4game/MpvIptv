local MpvIptvUtils = {}

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

package.path = mp.command_native({ "expand-path", "~~/script-opts/?.lua;" }) .. package.path

local IPTV_BIN_DIR  = mp.command_native({ "expand-path", "~~/../" })
local IPTV_TEMP_DIR  = mp.command_native({ "expand-path", "~~/temp/" })

local hash = require('sha2').md5

local json_encode = require('dkjson').encode
utils.format_json = function(tbl)
    return json_encode (tbl, { indent = true })
end

local function remove_file(file_path)
    if utils.file_info(file_path) then
        local s, error = os.remove(file_path)
        if not s then
            msg.error("remove: "..(error or "неизвестно"))
            return false
        end
    end
    return true
end

local function rename_file(src, dst)
    if utils.file_info(src) then
        remove_file(dst)
        local s, error = os.rename(src, dst)
        if not s then
            msg.error("rename: "..(error or "неизвестно"))
            return false
        end
    end    
    return true
end

local function copy_file(src, dst)

    local src_file, src_err = io.open(src, "rb")
    if not src_file then
        msg.error("copy: Ошибка чтения файла, " .. (src_err or "неизвестно"))
        return false
    end
    
    local dst_file, dst_err = io.open(dst, "wb")
    if not dst_file then
        src_file:close()
        msg.error("copy: Ошибка чтения файла, " .. (dst_err or "неизвестно"))
        return false
    end

    local total_bytes = 0
    local block_size = 32 * 1024
    
    while true do
        local block = src_file:read(block_size)
        if not block then break end
        dst_file:write(block)
        total_bytes = total_bytes + #block
    end
    
    src_file:close()
    dst_file:close()

    return true
end

local function is_gzip_file(checkFile)

    if not utils.file_info(checkFile) or utils.file_info(checkFile).size < 1024 then return false end

    local file, err = io.open(checkFile, "rb")
    if not file then
        msg.error("is_gzip: Ошибка чтения файла, " .. (err or "неизвестно"))
        return nil
    end

    local header = file:read(2)
    local b1, b2 = header:byte(1, 2)
    file:close()

    return (b1 == 0x1F) and (b2 == 0x8B)
end

function MpvIptvUtils.ReadAllStrings(file_path)

    local file, err = io.open(file_path, "r")
    if not file then
        msg.error("Ошибка открытия файла: " .. (err or "неизвестно"))
        return false
    end
    
    lines = {}

    while true do
        line = file:read("*line")
        if line == nil then break end

        line = line:trim()

        if line ~= "" then
            table.insert(lines, line)
        end
    end

    file:close()

    return lines
end

function MpvIptvUtils.gunzip(gzFile, resultFile)

    if not is_gzip_file(gzFile) then
        return copy_file(gzFile, resultFile)
    end

    local gzip = utils.join_path(IPTV_BIN_DIR, 'gzip.exe')
    if not utils.file_info(gzip) then gzip = 'gzip.exe' end

    local result = mp.command_native({
        name = "subprocess",
        playback_only = false,
        args = { gzip, '-dkf', gzFile},
        --capture_stdout = true,
        --capture_stderr = true
    })

    if not result or not result['status'] or result['status'] ~= 0 then
        msg.error("gunzip: "..select(2, utils.split_path(gzFile)))
        return false
    end

    return true
end

function MpvIptvUtils.LoadJsonFile(jsonFile)

    local file, err = io.open(jsonFile, "r")
    if not file then
        msg.error("LoadJsonFile: Ошибка чтения файла, " .. (err or "неизвестно"))
    else
        local str = file:read('*all')
        file:close()

        local tbl, parse_error = utils.parse_json(str)
        if not tbl then
            msg.error("LoadJsonFile: Ошибка декодирования файла, " .. parse_error)
        else
            return tbl
        end
    end

    return {}
end

function MpvIptvUtils.SaveJsonFile(tbl, jsonFile)

    local str = utils.format_json(tbl)

    if not utils.file_info(jsonFile) or utils.file_info(jsonFile).size ~= str:len() then
        local file, err = io.open(jsonFile, "wb")
        if not file then
            msg.error("SaveJsonFile: Ошибка записи файла, " .. (err or "неизвестно"))
        else
            file:write(str)
            file:close()
        end
    end
end

function MpvIptvUtils.GetLinkByUrl(config, url)
    for _, entry in ipairs(config.links) do
        if entry.url == url then
            return entry
        end
    end
    return nil
end

function MpvIptvUtils.AddEpgLinkFromFile(m3uFile, config, timeout)

    local epgUrl = MpvIptvUtils.GetEpgUrl(m3uFile)

    if epgUrl and not MpvIptvUtils.GetLinkByUrl(config, epgUrl) then
        --msg.warn("Добавлена ссылка на EPG, "..epgUrl)
        table.insert(config.links,  { url=epgUrl, isEpg=true, timeout=timeout })
    end

    return epgUrl
end

function MpvIptvUtils.GetEpgUrl(m3uFile)

    if not utils.file_info(m3uFile) or utils.file_info(m3uFile).size == 0 then
        msg.error("GetEpgUrl: Файл отсутствует или пустой, "..select(2, utils.split_path(m3uFile)))
        return nil
    end

    if is_gzip_file(m3uFile) then
        msg.error("GetEpgUrl: Файл является архивом .gz, "..select(2, utils.split_path(m3uFile)))
        return nil 
    end

    local file, err = io.open(m3uFile, "r")
    if not file then
        msg.error("GetEpgUrl: Ошибка чтения файла, " .. (err or "неизвестно"))
        return nil
    end

    local line = file:read("*line"):trim()

    if line == "" then
        line = file:read("*line") or ""
        line = line:trim()
    end

    file:close()

    if line:startswith("#EXTM3U") then
        local url = line:match('url%-tvg="([^"]+)"') or ""
        if url:trim() == "" then 
            msg.warn("Файл не содержит url-tvg, "..select(2, utils.split_path(m3uFile)))
            return nil
        end
        return url:trim()
    end

    msg.error("Файл не содержит #EXTM3U, "..select(2, utils.split_path(m3uFile)))
    if line ~= "" then
        msg.error(line)
    end

    return nil
end

function MpvIptvUtils.GetFilePath(url, bEpg, bGzip)
     return utils.join_path(IPTV_TEMP_DIR, MpvIptvUtils.GetFileName(url, bEpg, bGzip))
end

function MpvIptvUtils.GetName(url)
    return url:match("://([^:/]+)") ..'.' .. hash(url)
end

function MpvIptvUtils.GetFileName(url, bEpg, bGzip)

    local name = MpvIptvUtils.GetName(url)

    if bEpg and bGzip then
        return name..'.xml.gz'
    elseif bEpg then
        return name..'.xml'
    else
        return name..'.m3u'
    end
end

local urlTimeout, epgTimeout = 120, 720

function MpvIptvUtils.LoadAndUpdatePlaylistAndEpg(config, configFile, bReload)

    config.links = nil

    if config and config.m3uInit then

        if not config.links then config.links = {} end

        if config.m3uInit then

            for _, initEntry in ipairs(config.m3uInit) do
                if initEntry.name and initEntry.url then
                    local entry = MpvIptvUtils.GetLinkByUrl(config, initEntry.url)
                    if entry then
                        entry.name = initEntry.name
                        if initEntry.epgUrl and initEntry.epgUrl ~= '' and not entry.epgUrl then
                            entry.epgUrl = initEntry.epgUrl
                            if not MpvIptvUtils.GetLinkByUrl(config, initEntry.epgUrl) then
                                --msg.warn("Добавлена ссылка на EPG, "..initEntry.epgUrl)

                                local entry = {
                                    url = initEntry.epgUrl,
                                    timeout=initEntry.epgTimeout and initEntry.epgTimeout or epgTimeout,
                                    isEpg = true
                                }

                                table.insert(config.links, entry)
                            end
                        end
                    else
                        local entry = {
                            name = initEntry.name,
                            url = initEntry.url,
                            timeout=initEntry.urlTimeout and initEntry.urlTimeout or urlTimeout,
                            epgTimeout=initEntry.epgTimeout and initEntry.epgTimeout or epgTimeout,
                            isEpg = false
                        }

                        if initEntry.epgUrl and initEntry.epgUrl ~= '' then
                             entry.epgUrl = initEntry.epgUrl
                        end

                        table.insert(config.links, entry)

                        if initEntry.epgUrl and initEntry.epgUrl ~= '' and not MpvIptvUtils.GetLinkByUrl(config, initEntry.epgUrl) then
                            --msg.warn("Добавлена ссылка на EPG, "..initEntry.epgUrl)
                            local entry = {
                                url = initEntry.epgUrl,
                                timeout=initEntry.epgTimeout and initEntry.epgTimeout or epgTimeout,
                                isEpg = true
                            }

                            table.insert(config.links, entry)
                        end
                    end
                end
            end
        end

        msg.warn("Загрузка/Обновление playlists и epgs, Начинаем...")
        
        MpvIptvUtils.DownloadLinks(config.links, nil, config, configFile, bReload)
    end
end

local KeySelectPlaylist = "F12"

function MpvIptvUtils.BindKeySelectPlaylist(bBind)

    if bBind then
        mp.add_forced_key_binding(KeySelectPlaylist, KeySelectPlaylist.."-select-iptv-self", function ()
            mp.commandv("script-binding", "select-iptv-self")
        end)
    else
        mp.remove_key_binding(KeySelectPlaylist.."-select-iptv-self")
    end
end

function MpvIptvUtils.DownloadLinks(links, index, config, configFile, bReload)

    -- 1 timeout, 2 time & etag, 3 reload
    bReload = bReload or 1
    index = index or 1

    if not links or not links[index] then
        if config and configFile then
            MpvIptvUtils.SaveJsonFile(config, configFile..".bak")
            --MpvIptvUtils.SaveJsonFile(config, configFile)
        end

        msg.warn("> Нажмите "..KeySelectPlaylist.." для загрузки потоков <")

        MpvIptvUtils.BindKeySelectPlaylist(true)

        return
    end

    local unpack_table = function(t)
        return t.url, t.isEpg
    end

    local url, bEpg = unpack_table(links[index])

    local name = MpvIptvUtils.GetName(url)

    if not links[index].name or links[index].name == '' then
        links[index].name = name
    end

    local etagFile = utils.join_path(IPTV_TEMP_DIR, name..'.etag')
    local headerFile = utils.join_path(IPTV_TEMP_DIR, name..'.header')
    local traceFile = utils.join_path(IPTV_TEMP_DIR, name..'.trace')
    
    local fileName = MpvIptvUtils.GetFileName(url, bEpg, false)

    if not links[index].fileName then
        links[index].fileName = fileName
    end

    local resultFile = MpvIptvUtils.GetFilePath(url, bEpg, true)
    local resultFileTemp = MpvIptvUtils.GetFilePath(url, bEpg, true)..".temp"
    local xmlFile = MpvIptvUtils.GetFilePath(url, bEpg, false)

    local fiResultFile = utils.file_info(resultFile)
    local fiHeaderFile = utils.file_info(headerFile)
    local fiEtagFile = utils.file_info(etagFile)
    local fiXmlFile = utils.file_info(xmlFile)

    local bXmlFileExist = not bEpg or (fiXmlFile and fiXmlFile.size ~=0)
    
    local resultFileTime = fiResultFile and fiResultFile.size ~=0 and fiResultFile.mtime

    local headerFileTime = fiHeaderFile and fiHeaderFile.size ~=0 and fiHeaderFile.mtime

    local bEtagFileHasData = fiEtagFile and fiEtagFile.size ~= 0

    local bUpdate = bXmlFileExist and resultFileTime and headerFileTime

    local bTimeOut = bUpdate and links[index].timeout and (os.time() - headerFileTime) < (links[index].timeout * 60)

    -- bReload == 1, timeout / bReload == 2, Etag or timeout
    if bTimeOut and (bReload == 1 or (bReload == 2 and not bEtagFileHasData)) then

        msg.info("Проверка через "..math.ceil(links[index].timeout - (os.time() - headerFileTime) / 60).." минут, "..MpvIptvUtils.GetFileName(url, bEpg, false))

        if not bEpg then
            if (not links[index].epgUrl or links[index].epgUrl == '') then
                local epgUrl = MpvIptvUtils.AddEpgLinkFromFile(resultFile, config, links[index].epgTimeout)
                if epgUrl then
                    links[index].epgUrl = epgUrl
                end
            else --проверям что файл похож на .m3u
                MpvIptvUtils.GetEpgUrl(resultFile)
            end
        end

        MpvIptvUtils.DownloadLinks(links, index + 1, config, configFile, bReload)

        return
    end

    local curl = utils.join_path(IPTV_BIN_DIR, 'curl.exe')
    
    if not utils.file_info(curl) then curl = 'curl.exe' end

    if bUpdate and bReload ~= 3 then
        msg.info("Обновляем из "..url)
    else
        msg.info("Загружаем из "..url)
    end

    curl_args = { curl,
        '--compressed',
        '--no-progress-meter',
        --'--trace-ascii', traceFile,
        --'--trace-time', '--trace-ascii', traceFile,
        '--etag-save', etagFile,
        '-D', headerFile,
        '-RLo', resultFile..".temp",
        '--fail'}

    --table.insert(curl_arg, "--http1.1") -- протокол

    if resultFileTime and bReload ~= 3 then
        table.insert(curl_args, '-z')
        table.insert(curl_args, resultFile)
    end

    if bEtagFileHasData and bReload ~= 3 then
        table.insert(curl_args, '--etag-compare')
        table.insert(curl_args, etagFile)
    end

    table.insert(curl_args, url)

    remove_file(resultFileTemp)
    
    mp.command_native_async({
        name = "subprocess", playback_only = false, args=curl_args,
        --capture_stdout = true,
        --capture_stderr = true
    }, function(success, result)

        if not result then
            result = { success=success, status = -999 }
        else
            result.success = success
            result["killed_by_us"] = nil
        end

        if not result.success or result.status ~= 0 then
            msg.error("Ошибка загрузки "..url..", "..utils.format_table(result))
            if result.status < 0 then result.success = false end
        elseif utils.file_info(resultFileTemp) then
            if not resultFileTime then
                msg.info("Данные из источника загружены успешно.")
                rename_file(resultFileTemp, resultFile)
                if bEpg then MpvIptvUtils.gunzip(resultFile, xmlFile) end
            elseif resultFileTime ~= utils.file_info(resultFileTemp).mtime then
                msg.info("Данные из источника обновлены успешно.")
                rename_file(resultFileTemp, resultFile)
                if bEpg then MpvIptvUtils.gunzip(resultFile, xmlFile) end
            else
                msg.info("+Данные для этого источника не изменились.")
            end
        else
            msg.info("-Данные для этого источника не изменились.")
        end
        
        remove_file(resultFileTemp)

        if success and not bEpg then
            if not links[index].epgUrl or links[index].epgUrl == '' then
                local epgUrl = MpvIptvUtils.AddEpgLinkFromFile(resultFile, config, links[index].epgTimeout)
                if epgUrl then
                    links[index].epgUrl = epgUrl
                end
            else --проверям что файл похож на .m3u
                MpvIptvUtils.GetEpgUrl(resultFile)
            end
        end

        MpvIptvUtils.DownloadLinks(links, index + 1, config, configFile, bReload)

    end)
end

local dummy_overlay = mp.create_osd_overlay("ass-events")

local function get_osd_overlay_box(text, id, hidden)

    local result = mp.command_native({
        name = "osd-overlay",
        id = id,
        hidden = hidden == nil or hidden,
        format = "ass-events",
        data = text,
        compute_bounds = true,
        res_x = 0,
        res_y = 0,
        z = 0
    })

    result['w'] = result.x1 - result.x0
    result['h'] = result.y1 - result.y0

    for n,v in pairs(result) do
        result[n] =math.floor(v)     
    end
    --msg.warn(utils.format_table(result))

    return result
end

function MpvIptvUtils.GetTextWH(text) -- WxH
    local result = get_osd_overlay_box(text, dummy_overlay.id)
    return result.x1 - result.x0, result.y1 - result.y0
end

function MpvIptvUtils.GetTextWidth(text)
    local result = get_osd_overlay_box(text, dummy_overlay.id)
    return result.x1 - result.x0
end

function MpvIptvUtils.GetTextBox(text) -- x,y,w,h
    return get_osd_overlay_box(text, dummy_overlay.id)
end

function MpvIptvUtils.GetTextBoxParts(text) -- x,y,w,h
    local result = get_osd_overlay_box(text, dummy_overlay.id)
    return result.x0, result.y0, result.x1 - result.x0, result.y1 - result.y0
end

--MpvIptvUtils.GetTextBox("dummy")

function MpvIptvUtils.fixNameWithPoints(input_string)
    -- Ищем: начало строки, затем любые символы (title_part), затем возможно точки, затем (год), затем возможно точки, затем конец строки
    -- (.+) означает ж, но мы ограничиваем его местом перед скобкой
    local pattern = "^(.-)%s*[%.]*%((%d+)%)%.*$"
    local title_part, year_part = string.match(input_string, pattern)

    if not title_part or not year_part then return input_string end

    -- Убираем возможные лишние точки и пробелы в конце названия
    -- Убираем пробелы в конце
    title_part = string.gsub(title_part, "%s+$", "")
    -- Убираем точки в конце названия (если остались после пробелов)
    title_part = string.gsub(title_part, "[%.]+$", "")
    -- Убираем пробелы в конце снова на всякий случай
    title_part = string.gsub(title_part, "%s+$", "")

    return title_part .. " (" .. year_part .. ")"
end

return MpvIptvUtils