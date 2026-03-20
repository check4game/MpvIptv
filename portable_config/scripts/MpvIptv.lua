local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local input = require "mp.input"

--[[ 
local assdraw = require 'mp.assdraw'
local ass = assdraw.ass_new()
 ]]

local APP_NAME = "MpvIptv"
local APP_VERSION = "1.2.1"
local TITLE_PREFIX = APP_NAME .. " 📺"

local APP_USER_AGENT = string.format("%s/%s (%s) %s/%s-%s", APP_NAME, APP_VERSION, jit.os, mp.get_property("mpv-version"):gsub(' ', '/'), jit.version, jit.version_num)

package.path = mp.command_native({ "expand-path", "~~/script-opts/?.lua;" }) .. package.path

local htmlEntities = require 'htmlEntities'

local MpvIptvUtf8 = require 'MpvIptvUtf8'
local MpvIptvUtils = require 'MpvIptvUtils'
local MpvIptvGroups = require 'MpvIptvGroups'

local string = require 'MpvIptvString'

local IPTV_JSON_CONFIG_FILE = mp.command_native({ "expand-path", "~~/MpvIptv.json" })

local IPTV_JSON_CONFIG = {}

local DONE_FLAG = "@done_flag"

local DEFAULT_FONT_SIZE = mp.get_property_number("osd-font-size")

local GROUPS_PER_PAGE = 20
local CHANNELS_PER_PAGE = 20

local channel_groups = {}

local menu_state = {}

local current_group = {}

local current_channel = {}

local current_playlist = {}

local epg_channels = {}
local epg_programmes = {}

local GLOBAL_IS_IPTV = true

local GLOBAL_PLAYLIST_INDEX = nil

local osd_overlay = mp.create_osd_overlay("ass-events")

local function show_console()
    mp.commandv("script-binding", "commands/open")
end

local function hide_console()
    mp.command('keypress ESC')
end

local function full_init()

    channel_groups = {}

    menu_state = {
        -- Для групп
        group_page = 1,
        group_pages = 1,

        group_names = {},
        displayed_groups = {},
        
        -- Для каналов
        channel_page = 1,
        channel_pages = 1,

        current_group_channels = {},
        displayed_channels = {},

        type = nil, -- groups, channels, programme

        programme_show = nil,  -- function
    }

    current_group = {
        name = "", page = 0,
        idx = 0, start_idx = 0, end_idx = 0
    }

    current_channel = {
        name = "",
        urls = {},
        idx = 0, start_idx = 0, end_idx = 0,
        group_name = "",

        programme_idx = 0,

        title = nil, start = 0, stop = 0
    }

    current_playlist = {}
    epg_channels = {}
    epg_programmes = {}

    GLOBAL_IS_IPTV = true

    GLOBAL_PLAYLIST_INDEX = nil

    osd_overlay.data = ""
    osd_overlay.hidden = false
    osd_overlay:update()

    clear_temp_bindings()
end

local function osd_overlay_log(msg)

    if not msg then
        osd_overlay.data = string.format("\n\n{\\fs%d}", DEFAULT_FONT_SIZE)
    else
        osd_overlay.data = osd_overlay.data .. msg .. "\n"
        osd_overlay.hidden = false
        osd_overlay:update()
    end
 
end

local function set_window_title(msg)
    if msg then
        mp.set_property("title", TITLE_PREFIX .. " " .. msg)
    else
        mp.set_property("title", TITLE_PREFIX)
    end
end

local function collectgarbage_wrapper()
    collectgarbage()
end

function parse_epg(epg_file_name, epg_file_path)

    if epg_channels[DONE_FLAG] then
        return true
    end

    local file, err = io.open(epg_file_path, "r")
    if not file then
        msg.error("Ошибка чтения EPG файла: " .. (err or "неизвестно"))
        return false
    end

    local content = file:read("*a")
    file:close()

    epg_programmes = {}

    local programme_cnt = 0

    local ctime = os.time()

    local day = 24 * 60 * 60
    local lstart = ctime - day * 3 - 3 * 60 * 60
    local lstop = ctime + day * 1

    for programme in content:gmatch("<programme[^>]->.-</programme>") do
        local id = programme:match("channel=\"([^\"]+)\"")

        if not id then goto continue end
        
        local start = string.epg_time_to_seconds(programme:match("start=\"([^\"]+)\""))
        if start < lstart then goto continue end

        local stop = string.epg_time_to_seconds(programme:match("stop=\"([^\"]+)\""))
        if stop > lstop then goto continue end

        local title = programme:match('<title[^>]*>(.-)</title>') or "N/A"
        
        title = htmlEntities.decode(title):gsub("^⋗ ", "")

        local desc = programme:match('<desc[^>]*>(.-)</desc>') or "N/A"

        desc = htmlEntities.decode(desc)

        if not epg_programmes[id] then epg_programmes[id] = {} end

        if (stop - start) > day then title = "24+/" .. title end

        table.insert(epg_programmes[id], {start=start, stop=stop, title=title, desc=desc})

        programme_cnt = programme_cnt + 1

        if programme_cnt % 100000 == 0 then
            collectgarbage_wrapper()
        end

        ::continue::
    end

    local programmes_msg = string.format("Загружено %d программ передач из '%s' за %d секунд", programme_cnt, epg_file_name, os.time() - ctime)

    msg.info(programmes_msg)

    collectgarbage_wrapper()

    epg_channels = {}

    local channel_cnt = 0
    local display_cnt = 0
    
    for channel in content:gmatch("<channel[^>]->.-</channel>") do

        local id = channel:match("id=\"([^\"]+)\"")

        if id and epg_programmes[id] then

            channel_cnt = channel_cnt + 1

            for name in channel:gmatch('<display%-name[^>]*>(.-)</display%-name>') do

                for part in name:gmatch("[^•]+") do

                    part = part:match("^%s*(.-)%s*$")

                    if part and part ~= "" then

                        part = htmlEntities.decode(part):gsub("4К", "4K") -- русская буква К

                        local lower = string.normalize_display_name(MpvIptvUtf8.lower(part))

                        if not epg_channels[lower] then
                            epg_channels[lower] = id
                        end

                        lower = lower:gsub("[%s-]", "") -- удаляем все пробелы

                        if not epg_channels[lower] then
                            epg_channels[lower] = id
                        end

                        display_cnt = display_cnt + 1
                    end
                end
            end
        end
    end
    
    local channels_msg = string.format("Загружено %d каналов, %d названий из '%s'", channel_cnt, display_cnt, epg_file_name)

    msg.info(channels_msg)

    content = ""
    collectgarbage_wrapper()

    epg_channels[DONE_FLAG] = DONE_FLAG

    return true
end

function copy_table(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end

function n_episodes(n)
    local last = n % 100
    if last > 10 and last < 20 then return n.." эпизодов" end
    last = n % 10
    if last == 1 then return n.." эпизод"
    elseif last < 5 and last > 1 then return n.." эпизода"
    else return n.." эпизодов" end
end

function parse_m3u(m3u_file_name, m3u_file_path, fixes)

    if channel_groups[DONE_FLAG] then
        return true
    end
        
    channel_groups = {}

    lines = MpvIptvUtils.ReadAllStrings(m3u_file_path)

    GLOBAL_IS_IPTV = true
    
    local group_name = nil
    local channel_name = nil
    local channel_logo_id = nil
    local channel_tvg_id = nil

    local channel_catchup_type = 0
    local global_catchup_type = 0

    local film_year = nil
    local film_resolution= nil
    local film_genres = nil

    local channel_urls = {}
    
    local channel_cnt = 0

    local nil_tvg_id_cnt = 0

    local fixNameWithPoints = fixes and fixes == "name_with_points"

    local get_catchup_type = function(line) 

        if global_catchup_type ~= 0 then return global_catchup_type end

        -- timeshift="3" catchup-type="flussonic" catchup="flussonic" catchup="shift"
        local catchup_type = line:match('catchup%-type="([^"]+)"') or line:match('catchup="([^"]+)"') or ""

        -- tvg-rec="0" отключен, tvg-rec="6" 6 дней, tvg-rec="3" 3 дня, catchup-days="3" 3 дня, timeshift="6"
        local cd = line:match('tvg%-rec="([^"]+)"') 
                    or line:match('catchup%-days="([^"]+)"') 
                    or line:match('timeshift="([^"]+)"')
                    or line:match('catchup-time="([^"]+)"')

        if catchup_type ~="" and cd ~= "" and cd ~= "0" then
            if catchup_type == "flussonic" then
                catchup_type = 2 -- index.m3u8 => index-1491395400-900.m3u8
            elseif catchup_type == "shift" then
                catchup_type = 3 -- ?utc=1491395400&lutc=1491808183
            else
                catchup_type = 9
            end
        elseif cd ~= "" and cd ~= "0" then
            catchup_type = 1 -- архив есть
        else
            catchup_type = 0
        end

        return catchup_type
    end

    for _,line in ipairs(lines) do
        
        if line:startswith("#EXTM3U") then
        
        -- думал что на все но фиг фам
        --#EXTM3U generation-date="2026.03.05 18:01:31 MSK" url-tvg="https://rus.epg.team/3.1.xml.gz" playlist-name="rus.tvtm.one.Playlist"
        -- catchup-icon="1" catchup-type="flussonic" catchup-time="604800" playlist-logo="https://rus.tvtm.one/images/rus.tvtm.one.playlist.logo.png"

            --global_catchup_type = get_catchup_type(line)

        elseif line:startswith("#EXTINF:") then
            channel_name = line:match('.*",%s*(.*)') or "N/A"
            channel_name = string.normalize_display_name(htmlEntities.decode(channel_name)):gsub("4К", "4K") -- русская буква К

            channel_name = channel_name:gsub(" BY$", ""):gsub(" (BY)$", "")

            if fixNameWithPoints then channel_name = MpvIptvUtils.fixNameWithPoints(channel_name) end

            group_name = line:match('group%-title="([^"]+)"')

            channel_tvg_id = line:match('tvg%-id="([^"]+)"')
            if channel_tvg_id=="" then channel_tvg_id = nil end

            channel_logo_id = line:match('tvg%-logo="([^"]+)"')
            if channel_logo_id then channel_logo_id = channel_logo_id:match("/([^/]+)%.png$") end

            channel_catchup_type = get_catchup_type(line)

            if not channel_tvg_id then -- скорее всего медиатека
                nil_tvg_id_cnt = nil_tvg_id_cnt + 1

                film_year = line:match('year="([^"]+)"')
                film_resolution = line:match('resolution="([^"]+)"')
                film_genres = line:match('genres="([^"]+)"')

                if film_year == "" then film_year = nil end

                if film_resolution == "" then film_resolution = "???" end
                if film_genres == "" then film_genres = "Без жанра" end
            end

        elseif line:startswith("#EXTIMG:") then -- медиатека, картинка фильма

        elseif line:startswith("#EXTDESC:") then -- медиатека, описание фильма

        elseif line:startswith("#EXTGRP:") then -- название группы
            if channel_name and (not group_name or group_name == "") then
                group_name = line:match("^#EXTGRP:(.*)$"):trim()
            end
        elseif line:startswith("http") then --not line:startswith("#") and line ~= "" then
            if channel_name and not group_name then
                group_name = "Отсутствует"
            end

            if channel_name and group_name then

                group_name = string.match(group_name, "([^/]+)$"):trim()

                table.insert(channel_urls, line)

                if not film_resolution or #channel_urls == #film_resolution:split(',') then

                    channel_cnt = channel_cnt + 1

                    local isIPTV = not (film_year or film_genres or film_resolution or not channel_tvg_id)

                    if channel_logo_id then --fix, real from url
                        channel_logo_id = string.find_and_extract(channel_logo_id, line):gsub("_", "-")
                    end

                    local urls = {}

                    if film_resolution then
                        for idx, url in ipairs(channel_urls) do
                            table.insert(urls, { resolution=film_resolution:split(',')[idx], url=url })
                        end
                    else
                        table.insert(urls, { resolution=nil, url=channel_urls[1] })
                    end

                    -- alltv.club
                    if group_name then group_name = group_name:gsub("^%d+%. ", "") end

                    -- yasso tv
                    if group_name then group_name = group_name:gsub(" %([A-Z][A-Z]%)", "") end

                    entry = {
                        name = channel_name,
                        urls =  urls,
                        group_name = group_name,
                        logo_id = channel_logo_id,
                        tvg_id = channel_tvg_id,

                        year = film_year and tonumber(film_year) or 0,

                        isIPTV = isIPTV,

                        catchup_type = channel_catchup_type
                    } 

                    if not channel_groups[group_name] then
                        channel_groups[group_name] = {}
                    end
            
                    table.insert(channel_groups[group_name], entry)

                    if film_resolution and film_resolution:contains("2160") then
                        local gname = string.format("%s 4K", group_name)

                        if not channel_groups[gname] then
                            channel_groups[gname] = {}
                        end

                        entry = copy_table(entry)
                        --entry.group_name = gname
                        
                        entry.bAdditional = true
                        table.insert(channel_groups[gname], entry)
                    end

                    if film_genres then
                        for _, genre in ipairs(film_genres:split(',')) do
                            local gname = string.format("%s (%s)", group_name, MpvIptvUtf8.capitalize(genre))
                        
                            if not channel_groups[gname] then
                                channel_groups[gname] = {}
                            end

                            entry = copy_table(entry)
                            --entry.group_name = gname

                            entry.bAdditional = true                            
                            table.insert(channel_groups[gname], entry)
                        end
                    end

                    channel_name = nil
                    group_name = nil
                    channel_logo_id = nil
                    channel_tvg_id = nil

                    film_year = nil
                    film_resolution = nil
                    film_genres=nil

                    channel_urls = {}

                    channel_catchup_type = 0
                end
            end
        end
    end

    if channel_cnt > 0 then
        if nil_tvg_id_cnt < channel_cnt then
            msg.info("IPTV потоки, tvg-id-nil: " .. nil_tvg_id_cnt .. " from " .. channel_cnt)
            if nil_tvg_id_cnt > 0 then
                
                for _, channels in pairs(channel_groups) do

                    for _, channel in ipairs(channels) do
                        if not channel.tvg_id then
                            channel.isIPTV = true
                            msg.info('tvg-id-nil: ' .. channel.name)
                        end
                    end
                end
            end

            MpvIptvGroups.GroupGenerator(channel_groups)
        else

            GLOBAL_IS_IPTV = false

            msg.info("Фильмы/Сериалы/ТВ Шоу")

            local allGroup = {}

            local year = os.date("*t", os.time()).year

            local yearGroups = {}

            for i = 0, 6 do yearGroups[year - i] = {} end
            
            for gname, glist in pairs(channel_groups) do
                for _, entry in ipairs(glist) do
                    if not entry.bAdditional then
                        entry = copy_table(entry)
                        table.insert(allGroup, copy_table(entry))

                        for year, group in pairs(yearGroups) do
                            if entry.year == year or entry.name:find(year) then
                                entry = copy_table(entry)
                                table.insert(group, copy_table(entry))
                                break
                            end
                        end
                    end
                end
            end

            channel_groups["«ПОТОКИ ОБЩИЙ СПИСОК»"] = allGroup
            allGroup = nil

            for year, group in pairs(yearGroups) do
                if #group > 0 then
                    channel_groups["«ПОТОКИ "..year.." год»"] = group
                end
                yearGroups[year] = nil
            end

            -- удаляем порожденые группы которые полностью совпадают с парентом
            for gname, glist in pairs(channel_groups) do
                local name = glist[1].bAdditional and gname:gsub("%s*%([^%)]+%)$", "")
                if name and name ~= gname then
                    local gparent = channel_groups[name]
                    --msg.warn(gname.."|"..name.."|"..tostring(gparent ~= nil))
                    if gparent and #gparent == #glist then
                        channel_groups[gname] = nil
                    end
                end
            end

            for gname, _ in pairs(channel_groups) do

                local glist = channel_groups[gname]

                MpvIptvUtf8.sort(glist, function(entry)
                    return entry.name
                end)

                local serials = {}

                for _, info in ipairs(glist) do
                    local season, episode = info.name:match("S(%d+)E(%d+)$")

                    local name = info.name

                    if season and episode then
                        name = name:gsub("E"..episode.."$", "")
                    end

                    if not serials[name] then serials[name] = {} end
                    table.insert(serials[name], info)
                end

                glist = {}

                for name, info in pairs(serials) do

                    local serial = info[1]

                    local season = name:match("( S%d+)$")

                    local add_serial = true

                    if #info > 1 or season then

                        serial = copy_table(info[1])

                        serial.name = name

                        serial.urls = {}
                        
                        if season then

                            local number = serial.name:match(" S(%d+)$")

                            for _, episode in ipairs(info) do
                                table.insert(serial.urls, {episode=episode.name:match("(S%d+E%d+)$"), url=episode.urls[1].url})
                            end

                            if serial.year > 1000 then
                                serial.name = serial.name:gsub(" %(сериал%)", ""):gsub(" %(.-%d%d%d%d.-%)", ""):gsub(" %(%d%d%d%d%)", "")

                                if not serial.name:find(serial.year) then
                                    if number == "01" then
                                        if serials[name:gsub(" S01$", " S02")] then
                                            serial.name = serial.name:gsub(season, string.format(" ( %s) %s", serial.year, season))
                                        else
                                            serial.name = serial.name:gsub(season, string.format(" (%s) %s", serial.year, season))
                                        end
                                    else
                                        serial.name = serial.name:gsub(season, string.format(" (%s+) %s", serial.year, season))
                                    end
                                end
                            else
                                local year = serial.name:match(" %((%d%d%d%d)%) ")
                                if year then
                                    if number == "01" then
                                        if serials[name:gsub(" S01$", " S02")] then
                                            serial.name = serial.name:gsub(serial.name:match("( %(%d%d%d%d%))"), string.format(" ( %s) ", year))
                                        else
                                            serial.name = serial.name:gsub(serial.name:match("( %(%d%d%d%d%))"), string.format(" (%s) ", year))
                                        end
                                    else
                                        serial.name = serial.name:gsub(serial.name:match("( %(%d%d%d%d%))"), string.format(" (%s+) ", year))
                                    end
                                end
                            end
                            
                            --serial.name = string.format("%s Сезон %s/%s", serial.name:gsub(season, ""), number, n_episodes(#serial.urls))
                            --serial.name = string.format("%s Сезон %s / Серий %s", serial.name:gsub(season, ""), number, #serial.urls)
                            serial.name = string.format("%s Сезон %s/%02d", serial.name:gsub(season, ""), number, #serial.urls)
                        else
                            add_serial = false

                            -- тут могут быть одинаковые названия, одинаковые названия но разный год, одинаковые url
                            local unique_urls = {}

                            for _, entry in ipairs(info) do
                                if entry.year > 1000 and not entry.name:find(entry.year) then
                                    entry.name = string.format("%s (%s)", entry.name, entry.year)
                                end

                                if not unique_urls[entry.urls[1].url] then
                                    unique_urls[entry.urls[1].url] = entry
                                else
                                    --msg.warn("dup: "..entry.group_name.."|"..entry.name.."|"..#entry.urls)
                                end
                            end

                            local unique_names = {}

                            for _, entry in pairs(unique_urls) do
                                if not unique_names[entry.name] then
                                    unique_names[entry.name] = { entry }
                                else
                                    table.insert(unique_names[entry.name], entry)
                                end
                            end

                            unique_urls = {}

                            for _, un_entries in pairs(unique_names) do
                                if #un_entries == 1 then
                                     table.insert(glist, un_entries[1])
                                else
                                    local unique_groups = {}
                                    local unique_groups_cnt = 0

                                    for _, entry in ipairs(un_entries) do
                                        if not unique_groups[entry.group_name] then
                                            unique_groups[entry.group_name] = { entry }
                                            unique_groups_cnt = unique_groups_cnt + 1
                                        else
                                            table.insert(unique_groups[entry.group_name], entry)
                                        end
                                    end

                                    for _, ug_entries in pairs(unique_groups) do
                                        if #ug_entries == 1 then
                                            local entry = ug_entries[1]
                                            entry.name = string.format("%s/%s", entry.name, entry.group_name)
                                            table.insert(glist, entry)
                                        else
                                            local index = 1
                                            for _, entry in ipairs(ug_entries) do
                                                if unique_groups_cnt ~= #un_entries then
                                                    --entry.name = string.format("%s (вариант %s)/%s", entry.name, index, entry.group_name)
                                                    entry.name = string.format("%s (вариант %s)", entry.name, index)
                                                    index = index + 1
                                                else
                                                    entry.name = string.format("%s/%s", entry.name, entry.group_name)
                                                end
                                                table.insert(glist, entry)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    else
                        if serial.year > 1000 and not serial.name:find(serial.year) then
                            serial.name = string.format("%s (%s)", serial.name, serial.year)
                        end
                    end

                    if add_serial then
                        serial.name = serial.name:gsub("  ", " ")
                        table.insert(glist, serial)
                    end

                end

                MpvIptvUtf8.sort(glist, function(entry)
                    return entry.name
                end)

                channel_groups[gname] = glist
            end
        end
    end

    lines = nil

    collectgarbage_wrapper()

    prepare_groups_pagination()
    
    channel_groups[DONE_FLAG] = DONE_FLAG

    msg.info(string.format("Обнаружено %d групп и %d ссылок на потоки в '%s'", #menu_state.group_names, channel_cnt, m3u_file_name))

--[[     
    if GLOBAL_IS_IPTV then
        msg.info(string.format("Загружено %d групп и %d каналов из '%s'", #menu_state.group_names, channel_cnt, m3u_file_name))
    else
        msg.info(string.format("Загружено %d групп и %d фильмов/сериалов/тв шоу из '%s'", #menu_state.group_names, channel_cnt, m3u_file_name))
    end
 ]]    
    return true
end

function load_m3u_epg()

    local entry = get_playlist_entries(GLOBAL_PLAYLIST_INDEX)[1]

    --set_window_title(string.format("Обработка playlist '%s' ...", MpvIptvUtils.GetFileName(entry.url)))

    local result = parse_m3u(MpvIptvUtils.GetFileName(entry.url), MpvIptvUtils.GetFilePath(entry.url), get_playlist_fixes(entry.url))

    if result and GLOBAL_IS_IPTV and entry.epgUrl then
        --set_window_title(string.format("Обработка '%s' ...", MpvIptvUtils.GetFileName(entry.epgUrl, true)))
        result = parse_epg(MpvIptvUtils.GetFileName(entry.epgUrl, true), MpvIptvUtils.GetFilePath(entry.epgUrl, true))
    end

    if result then
        if entry.name then
            --set_window_title(string.format("Playlist '%s' / %s загружен", entry.name, MpvIptvUtils.GetFileName(entry.url)))
        else
            --set_window_title(string.format("Playlist '%s' загружен", MpvIptvUtils.GetFileName(entry.url)))
        end
    end

    return result
end    

function prepare_groups_pagination()
    menu_state.group_names = {}

    for group_name, _ in pairs(channel_groups) do
        table.insert(menu_state.group_names, group_name)
    end
    
    MpvIptvUtf8.sort(menu_state.group_names)

    menu_state.group_pages = math.ceil(#menu_state.group_names / GROUPS_PER_PAGE)
    menu_state.group_page = 1
end

function get_current_page_groups(page)
    
    menu_state.group_pages = math.ceil(#menu_state.group_names / GROUPS_PER_PAGE)
    menu_state.group_page = math.max(1, math.min(page, menu_state.group_pages))

    local cache = menu_state.displayed_groups[menu_state.group_page]

    if not cache then

        local start_idx = (menu_state.group_page - 1) * GROUPS_PER_PAGE + 1
        local end_idx = math.min(menu_state.group_page * GROUPS_PER_PAGE, #menu_state.group_names)
        
        local page_groups = {}

        local max_len = 0

        for i = start_idx, end_idx do

            local name = menu_state.group_names[i]

            local name_len = MpvIptvUtf8.len(name)

            max_len = math.max(max_len, name_len)

            table.insert(page_groups, {
                name = name,
                name_len = name_len,
                index = i,
                channel_count = #channel_groups[name] or 0
            })
        end
        
        cache = {page_groups = page_groups, start_idx = start_idx, max_len = max_len}
        menu_state.displayed_groups[menu_state.group_page] = cache
    end

    return cache.page_groups, cache.start_idx, cache.max_len
end

function prepare_channels_pagination(group_name)
    menu_state.group_name = group_name
    menu_state.current_group_channels = channel_groups[group_name]
    menu_state.channel_pages = math.ceil(#menu_state.current_group_channels / CHANNELS_PER_PAGE)
    menu_state.channel_page = 1
end

function map_channel_to_programme(channel_info)

    if not channel_info.id and channel_info.channel.tvg_id then

        channel_info.symbol = " "

        if not channel_info.id and channel_info.channel.tvg_id then
            if epg_programmes[channel_info.channel.tvg_id] then
                channel_info.id = channel_info.channel.tvg_id
                channel_info.symbol = " " -- нашли по tvg_id
            end
        end

        if not channel_info.id and channel_info.channel.logo_id then
            if epg_programmes[channel_info.channel.logo_id] then
                channel_info.id = channel_info.channel.logo_id
                channel_info.symbol = "!" -- нашли по logo_id
            end
        end

        if not channel_info.id then
            local display_lower = string.normalize_display_name(MpvIptvUtf8.lower(channel_info.channel.name))
            channel_info.id = epg_channels[display_lower] or epg_channels[display_lower:gsub("[%s-]", "")]

            if channel_info.id and epg_programmes[channel_info.id] then
                channel_info.symbol = "⋗" -- нашли по имени
            else
                channel_info.id = nil
            end
        end

            --display_lower = display_lower:gsub(" premium%+$", "")             
--[[
            channel_info.id = channel_info.id
                or epg_channels[display_lower]
                or epg_channels[display_lower:gsub(" hd ", " ")]
                or epg_channels[display_lower:gsub(" vip ", " ")]
                or epg_channels[display_lower:gsub("s$", "")]
                or epg_channels[display_lower:gsub(" hdr$", " hd")] -- BCU FilMystic HDR & BCU FilMystic HD

                or epg_channels[display_lower .. " tv"]
                or epg_channels[display_lower .. " 4k"]
                or epg_channels[display_lower .. " hd"]

                or epg_channels[display_lower:gsub("[%s-]", "")] -- пробелы
                or epg_channels[display_lower:gsub("cgtn ", "cgtn-"):gsub(" hd$", "")] -- CGTN-Русский HD

                or epg_channels[display_lower:gsub("%s", ""):gsub("hd$", "")] -- Detective Jam HD

                or epg_channels[display_lower:gsub(" hd ", " "):gsub(" hd$", "")] -- Мосфильм. Золотая коллекция HD (+4) HD

                or epg_channels[display_lower:gsub(" live hd$", ".live")] -- Соловьев.Live
                
                or epg_channels[display_lower:gsub(" hd$", " fhd")] -- SKY HIGH BEYOND S FHD
                or epg_channels[display_lower:gsub("тв$", "tv")] -- ЭхоТВ

                or epg_channels[display_lower:gsub(" hd$", "")]
                or epg_channels[display_lower:gsub(" teens$", "")]
                or epg_channels[display_lower:gsub(" uhd$", "")]
                or epg_channels[display_lower:gsub(" tv$", "")] -- Dorcel TV
]]

        if channel_info.channel.catchup_type < 1 then
            channel_info.symbol = channel_info.symbol .. " \u{2005}" --FOUR-PER-EM SPACE
        elseif channel_info.channel.catchup_type < 4 then
            channel_info.symbol = channel_info.symbol .. "↺"
        else
            channel_info.symbol = channel_info.symbol .. channel_info.channel.catchup_type .. "\u{2005}"
        end
    end

    return channel_info
end

function get_current_page_channels(group_name, page)

    menu_state.channel_pages = math.ceil(#menu_state.current_group_channels / CHANNELS_PER_PAGE)
    menu_state.channel_page = math.max(1, math.min(page, menu_state.channel_pages))
    
    local cache = menu_state.displayed_channels[group_name .. menu_state.channel_page]

    if not cache then
    
        local start_idx = (menu_state.channel_page - 1) * CHANNELS_PER_PAGE + 1
        local end_idx = math.min(menu_state.channel_page * CHANNELS_PER_PAGE, #menu_state.current_group_channels)
        
        local page_channels = {}

        local max_len = 0
        
        for i = start_idx, end_idx do
            local channel = menu_state.current_group_channels[i]

            max_len = math.max(max_len, MpvIptvUtf8.len(channel.name))

            local info = { channel = channel, symbol = "  ", id = nil }
            
            table.insert(page_channels, map_channel_to_programme(info))

        end
        
        cache = { page_channels=page_channels, start_idx=start_idx, end_idx = end_idx, max_len = max_len }
        menu_state.displayed_channels[group_name .. menu_state.channel_page] = cache 
    end
    
    return cache.page_channels, cache.start_idx, cache.end_idx, cache.max_len    
end

-- Привязка клавиш для элементов 0-19
function bind_items_keys(items, start_index, callback)

    for i, item in ipairs(items) do
        local global_index = start_index + i - 1

        if i <= 10 then
            -- Элементы 0-9: цифры 0-9
            mp.add_forced_key_binding(tostring(i-1), "item_" .. global_index, function()
                callback(global_index, item)
            end)
        elseif i <= 20 then
            -- Элементы 10-19: Ctrl+0-9
            local ctrl_key = "Ctrl+" .. tostring(i - 10 - 1)
            mp.add_forced_key_binding(ctrl_key, "item_ctrl_" .. global_index, function()
                callback(global_index, item)
            end)
        end
    end
end

-- Получение метки для отображения
function get_item_label(index_in_page, global_index)
    if index_in_page <= 10 or index_in_page > 20 then
        return string.format("\\h%d", index_in_page - 1)
    elseif index_in_page <= 20 then
        return string.format("^%d", index_in_page - 10 - 1)  -- ^ для Ctrl
    end
end

-- ============================================
-- МЕНЮ ГРУПП С ПАГИНАЦИЕЙ
-- ============================================

local function makeup(fs, str)
    return string.format("{\\fs%d}%s", fs, str)
end

local function IsClickValid(mouse)

    if not mouse then
        return true --not mp.get_property_bool("osc")
    end

    local x,y = mp.get_mouse_pos() --mp.get_property_native("mouse-pos", {x=0, y=0})
    local width, height, aspect = mp.get_osd_size()
    --local width, height = mp.get_property_native("osd-dimensions")

    --mp.osd_message(string.format("X: %d, Y: %d", event.x, event.y), 2)

    --msg.warn(string.format("osd: %d,%d,%s screen: %d,%d, pos: %d,%d", width, height, aspect, screen.w, screen.h, pos.y, pos.x))
    --mp.osd_message(string.format("osd: %d,%d,%s, pos: %d,%d", width, height, aspect, y, x), 10)
    
    --return not mp.get_property_bool("osc") and pos.y < (screen.h * 3 / 4) and pos.x < (screen.w * 2 / 3)
    return y < (height * 3 / 4) and x < (width * 3 / 4)
end            

function make_header(text)
    return makeup(DEFAULT_FONT_SIZE, "\\h\n")..makeup(5, "\\h\n")
                    ..makeup(DEFAULT_FONT_SIZE, text)..makeup(10, "\\h\n")
end

function show_groups_menu(page)

    clear_temp_bindings()
    
    menu_state.type = "groups" 
    
    local page_groups, start_idx, max_len = get_current_page_groups(page)
    local total_groups = #menu_state.group_names
    
    current_group.start_idx = start_idx
    current_group.end_idx = start_idx + #page_groups - 1
    current_group.name = ""

    local header_text = ""
    local menu_text = ""

    header_text = total_groups <= GROUPS_PER_PAGE and "📡 ГРУППЫ ПОТОКОВ" or
        string.format("📡 ГРУППЫ ПОТОКОВ [СТРАНИЦА %d из %d]", page, menu_state.group_pages)

    header_text = make_header(header_text)

    local GROUP_NAME_FMT = "%s {\\c&H00FFFF&}%s{\\c&HFFFFFF&}%s ⋗ %4d потоков\n"
    local C_GROUP_NAME_FMT = "%s {\\c&H00FF00&}%s%s ⋗ %4d потоков\n"

    -- Выводим группы
    for i, info in ipairs(page_groups) do
        local idx = start_idx + i - 1
        local label = get_item_label(i, idx)

        local entry = makeup(DEFAULT_FONT_SIZE, 
            string.format(current_group.idx == idx and C_GROUP_NAME_FMT or GROUP_NAME_FMT,
            label, info.name, string.rep(' ', max_len - info.name_len + 5), info.channel_count))

        menu_text = menu_text..entry
    end

    -- Привязываем клавиши для групп
    bind_items_keys(page_groups, start_idx, function(global_index, info)
        current_group.idx = global_index
        menu_state.channel_page = 1
        select_channel(info.name, 1)
    end)

    local show_channels = function(mouse)
        if IsClickValid(mouse) and current_group.idx ~= 0 then
            menu_state.channel_page = 1
            select_channel(menu_state.group_names[current_group.idx], 1)
        end
    end

    mp.add_forced_key_binding("Enter", "show_channels_menu", function() show_channels(false) end)
    mp.add_key_binding("MBTN_LEFT", "show_channels_menu_mouse", function() show_channels(true) end)
    
    local group_prev = function(mouse)
        if IsClickValid(mouse) then

            if current_group.page ~= page then
                current_group.page = page
                current_group.idx = current_group.end_idx
            else
                current_group.idx = current_group.idx - 1

                if current_group.idx < 1 then
                    page = menu_state.group_pages
                    current_group.idx = total_groups
                    current_group.page = page
                elseif current_group.idx < current_group.start_idx then
                    page = page - 1
                    current_group.page = page
                end
            end

            show_groups_menu(page)
        end
    end

    mp.add_forced_key_binding("Up", "item_prev", function() group_prev(false) end)
    mp.add_forced_key_binding("WHEEL_UP", "item_prev_mouse", function() group_prev(true) end)
    
    local group_next = function(mouse)
        if IsClickValid(mouse) then

            if current_group.page ~= page then
                current_group.page = page
                current_group.idx = current_group.start_idx
            else
                current_group.idx = current_group.idx + 1

                if current_group.idx > total_groups then
                    page, current_group.idx = 1,1
                    current_group.page = page
                elseif current_group.idx > current_group.end_idx then
                    page = page + 1
                    current_group.page = page
                end
            end
            show_groups_menu(page)
        end
    end

    mp.add_forced_key_binding("Down", "item_next", function() group_next(false) end)
    mp.add_forced_key_binding("WHEEL_DOWN", "item_next_mouse", function() group_next(true) end)

    -- Навигация
    setup_pagination_navigation("groups", menu_state.group_page, menu_state.group_pages,
        function(page)
            current_group.idx = (page - 1) * GROUPS_PER_PAGE + 1
            show_groups_menu(page)
        end)

    local nav_text = string.rep(makeup(DEFAULT_FONT_SIZE, "\\h\n"), (GROUPS_PER_PAGE - #page_groups))
     ..makeup(5, "\\h\n")..get_navigation_controls("groups")

    osd_overlay.data = "\n\n" .. header_text .. menu_text .. nav_text
    osd_overlay.hidden = false
    osd_overlay:update()

end

function show_channels_menu(group_name, page)
    
    clear_temp_bindings()

    menu_state.type = "channels" 
    
    prepare_channels_pagination(group_name)

    local page_channels, start_idx, max_idx, max_len = get_current_page_channels(group_name, page)
    local total_channels = #menu_state.current_group_channels
    
    local idx_format
    if max_idx < 10 then idx_format = "%d" elseif max_idx < 100 then idx_format = "%02d" else idx_format = "%03d" end

    -- Формируем меню
    local header_text
    local menu_text = ""

    --local padding = ((math.ceil(total_channels / CHANNELS_PER_PAGE) < 10 or page > 9) and "") or " "

    header_text = total_channels <= CHANNELS_PER_PAGE and string.format("📡 ГРУППА %s", group_name) or
        string.format("📡 ГРУППА %s [СТРАНИЦА %d ИЗ %d]", group_name, page, menu_state.channel_pages)

    header_text = make_header(header_text)

    local ctime = os.time()

    for i, channel_info in ipairs(page_channels) do

        local display_name = channel_info.channel.name
        local global_index = start_idx + i - 1
        local label = get_item_label(i, global_index)

        if channel_info.channel.film_year then
            --display_name = display_name .. "/" .. channel_info.channel.film_year
        end

        local bRtl = MpvIptvUtf8.IsRtl(display_name)
        local display_name_len = MpvIptvUtf8.len(display_name)

        if bRtl then --display_name == "ערוץ הידברות" then
            display_name =  "\u{2067}"..display_name.."\u{2069}"
        end

        local cchannel = makeup(DEFAULT_FONT_SIZE,
            string.format("{\\q2}%s{\\fs12}" .. idx_format .. " {\\fs%d}{\\c&H00FFFF&}%s{\\c&HFFFFFF&}",
            label, global_index, DEFAULT_FONT_SIZE, display_name))
        
        if current_channel.idx == global_index and current_group.name == group_name then
            cchannel = makeup(DEFAULT_FONT_SIZE,
                string.format("{\\q2}%s{\\fs12}" .. idx_format .. " {\\fs%d}{\\c&H00FF00&}%s{\\c&HFFFFFF&}",
                label, global_index, DEFAULT_FONT_SIZE, display_name))
        end

        local programme = nil

        if channel_info.id and epg_programmes[channel_info.id] then
            programme = epg_programmes[channel_info.id]
        elseif channel_info.channel.isIPTV then
            programme = programme_generator('===')
        end

        if programme then
            if programme then
                local cprogramme = nil

                for i, info in ipairs(programme) do
                    if ctime >= info.start and ctime < info.stop then

                        if current_channel.idx  == global_index then
                            current_channel.programme_idx = i
                        end
 
                        local start = os.date("*t", info.start)
                        local stop = os.date("*t", info.stop)
                        
                        local padding = string.rep(' ', max_len - display_name_len + (bRtl and 2 or 1))
                        --padding = bRtl and (padding .. "\u{2006}\u{2006}") or padding

                        cprogramme = makeup(DEFAULT_FONT_SIZE,
                            string.format("%s%s %s %s", padding, channel_info.symbol,
                            string.format("%02d:%02d-%02d:%02d", start.hour, start.min, stop.hour, stop.min),
                            info.title:gsub("^⋗ ", "")))
                        break
                    end
                end

                if not cprogramme then -- last programme
                    local info = programme[#programme]

                    local start = os.date("*t", info.start)
                    local stop = os.date("*t", info.stop)

                    local padding = string.rep(' ', max_len - display_name_len + (bRtl and 2 or 1))
                    --padding = bRtl and (padding .. "\u{2002}") or padding

                    cprogramme = makeup(DEFAULT_FONT_SIZE,
                        string.format("%s%s %s %s",
                        padding, channel_info.symbol,
                        string.format("%02d/%02d/%04d, %02d:%02d-%02d:%02d", start.day, start.month, start.year, start.hour, start.min, stop.hour, stop.min),
                        info.title:gsub("^⋗ ", "")))
                end

                cchannel = cchannel .. cprogramme

                if current_channel.idx == global_index then

                    programme_show = function()

                        clear_temp_bindings()

                        menu_state.type = "programme"

                        local start_idx = current_channel.programme_idx - 1
                        local end_idx = #programme

                        local data = "\n\n"

                        local fmt = '{\\shad1\\4c&H000000&\\q1\\b1\\bord1\\be\\fs%s\\1c&H%s&}%02d/%02d/%04d %02d:%02d-%02d:%02d{\\fs%s} %s'..
                                    '\n{\\1c&H%s&\\fs%s\\q3\\shad1\\4c&H000000&}\\h\\h\\h%s'
                        
                        for idx = start_idx, end_idx do

                            local info = programme[idx]
                            
                            if info then

                                local start = os.date("*t", info.start)
                                local stop = os.date("*t", info.stop)

                                local desc = info.desc or ""

                                if idx == current_channel.programme_idx then
                                    data = data .. fmt:format(DEFAULT_FONT_SIZE, "54E5B2", --"FF00FF",
                                                start.day, start.month, start.year, start.hour, start.min, stop.hour, stop.min,
                                                DEFAULT_FONT_SIZE, info.title,
                                                "54E5B2", DEFAULT_FONT_SIZE, desc:gsub('\n',''))

                                        --if info.desc then data = data .. "\n\n" else data = data .. "\n" end
                                else
                                    if info.desc then desc = "..." end

                                    data = data .. fmt:format(DEFAULT_FONT_SIZE - 3, "00FFFF",
                                                start.day, start.month, start.year, start.hour, start.min, stop.hour, stop.min,
                                                DEFAULT_FONT_SIZE, info.title,
                                                "FFFFFF", DEFAULT_FONT_SIZE - 2, desc:gsub('\n',''))

                                    --data = data .. "\n"
                                end

                                data = data .. "\n"
                            end
                        end

                        local programme_prev = function()
                            if current_channel.programme_idx > 1 then
                                if not osd_overlay.hidden then
                                    current_channel.programme_idx = current_channel.programme_idx - 1
                                end
                                programme_show()
                            end
                        end

                        mp.add_forced_key_binding("Up", "item_prev", programme_prev)
                        mp.add_forced_key_binding("WHEEL_UP", "item_prev_mouse", programme_prev)

                        local programme_next = function()
                            if (#programme - current_channel.programme_idx) > 0 then
                                if not osd_overlay.hidden then
                                    current_channel.programme_idx = current_channel.programme_idx + 1
                                end
                                programme_show()
                            end
                        end

                        mp.add_forced_key_binding("Down", "item_next", programme_next)
                        mp.add_forced_key_binding("WHEEL_DOWN", "item_next_mouse", programme_next)

                        local back_to_group = function(mouse)
                            if IsClickValid(mouse) then
                                show_channels_menu(menu_state.group_name, menu_state.channel_page)
                            end
                        end

                        mp.add_forced_key_binding("BS", "back_to_group", function() back_to_group(false) end)
                        mp.add_key_binding("MBTN_RIGHT", "back_to_group_mouse", function() back_to_group(true) end)

                        local play_channel = function(mouse)
                            if IsClickValid(mouse) then
                                play_channel(group_name, global_index, channel_info.id)
                            end
                        end

                        mp.add_forced_key_binding("Enter", "play_channel", function() play_channel(false) end)
                        mp.add_key_binding("MBTN_LEFT", "play_channel_mouse", function() play_channel(true) end)

                        osd_overlay.hidden = false
                        osd_overlay.data = data
                        osd_overlay:update()
                    end

                    mp.add_key_binding("Ctrl+Enter", "programme_show", programme_show)
                    mp.add_key_binding("Ctrl+MBTN_LEFT", "programme_show_mouse", programme_show)
                end
            end
        end

        menu_text = menu_text .. cchannel .. "\n"
    end

    -- Привязываем клавиши
    bind_items_keys(page_channels, start_idx, function(global_index, channel_info)
        current_channel.programme_idx = 0
        play_channel(group_name, global_index, page_channels[global_index - start_idx + 1].id)
    end)
    
    local play_channel = function(mouse)
        if IsClickValid(mouse) and current_channel.idx >= current_channel.start_idx and current_channel.idx <= current_channel.end_idx then
            current_channel.programme_idx = 0
            play_channel(group_name, current_channel.idx, page_channels[current_channel.idx - start_idx + 1].id)
        end
    end
    
    mp.add_forced_key_binding("Enter", "play_channel", function() play_channel(false) end)
    mp.add_key_binding("MBTN_LEFT", "play_channel_mouse", function() play_channel(true) end)

    current_channel.start_idx = start_idx
    current_channel.end_idx = start_idx + #page_channels - 1

    local channel_prev = function(mouse)
        if IsClickValid(mouse) then
            if current_channel.idx < current_channel.start_idx or current_channel.idx > current_channel.end_idx then
                select_channel(group_name, current_channel.end_idx)
            elseif current_channel.idx > current_channel.start_idx then
                select_channel(group_name, current_channel.idx - 1)
            elseif menu_state.channel_page > 1 then
                menu_state.channel_page = menu_state.channel_page - 1
                select_channel(group_name, current_channel.idx - 1)
            else
                menu_state.channel_page = menu_state.channel_pages
                select_channel(group_name, #channel_groups[group_name])
            end
        end
    end

    mp.add_forced_key_binding("Up", "item_prev", function() channel_prev(false) end)
    mp.add_forced_key_binding("WHEEL_UP", "item_prev_mouse", function() channel_prev(true) end)
    
    local channel_next = function(mouse)
        if IsClickValid(mouse) then
            if current_channel.idx < current_channel.start_idx or current_channel.idx > current_channel.end_idx then
                select_channel(group_name, current_channel.start_idx)
            elseif current_channel.idx < current_channel.end_idx then
                select_channel(group_name, current_channel.idx + 1)
            elseif menu_state.channel_page < menu_state.channel_pages then
                menu_state.channel_page = menu_state.channel_page + 1
                select_channel(group_name, current_channel.idx + 1)
            else
                menu_state.channel_page = 1
                select_channel(group_name, 1)
            end
        end
    end    

    mp.add_forced_key_binding("Down", "item_next", function() channel_next(false) end)
    mp.add_forced_key_binding("WHEEL_DOWN", "item_next_mouse", function() channel_next(true) end)

    -- Навигация
    setup_pagination_navigation("channels", menu_state.channel_page, menu_state.channel_pages,
        function(page)
            current_channel.idx = (page - 1) * CHANNELS_PER_PAGE + 1
            show_channels_menu(group_name, page)
        end)
    
    local nav_text = string.rep(makeup(DEFAULT_FONT_SIZE, "\\h\n"), (CHANNELS_PER_PAGE - #page_channels))
     ..makeup(5, "\\h\n").. get_navigation_controls("channels")

    osd_overlay.data = header_text .. menu_text .. nav_text
    osd_overlay.hidden = false
    osd_overlay:update()
end

-- ============================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================

function get_navigation_controls(type)
    if type == "channels" then
        return makeup(DEFAULT_FONT_SIZE-2, "ВЫБОР ПОТОКА: [Ctrl+]0..9 | СТРАНИЦЫ: \u{25C4}/\u{25BA} | ВОЗВРАТ: Backspace\n")
    else
        return makeup(DEFAULT_FONT_SIZE-2, "ВЫБОР ГРУППЫ: [Ctrl+]0..9 | СТРАНИЦЫ: \u{25C4}/\u{25BA}\n")
    end
end

function setup_pagination_navigation(type, current_page, total_pages, change_page_callback)
    
    mp.add_forced_key_binding("LEFT", "page_prev", function()
        if current_page > 1 then
            change_page_callback(current_page - 1)
        else
            change_page_callback(total_pages)
        end
    end)
    
    mp.add_forced_key_binding("RIGHT", "page_next", function()
        if current_page < total_pages then
            change_page_callback(current_page + 1)
        else
            change_page_callback(1)
        end
    end)

    if type == "channels" then

        local back_to_group = function(mouse)
            if IsClickValid(mouse) then
                show_groups_menu(menu_state.group_page)
                --menu_state.group_name = ""
            end
        end

        mp.add_forced_key_binding("BS", "back_to_group", function() back_to_group(false) end)
        mp.add_key_binding("MBTN_RIGHT", "back_to_group_mouse", function() back_to_group(true) end)

    else
        local hide = function(mouse)
            if IsClickValid(mouse) then
                mp.remove_key_binding("back_to_group")
                mp.remove_key_binding("back_to_group_mouse")
                hide_menu()
            end
        end

        mp.add_forced_key_binding("BS", "back_to_group", function() hide(false) end)
        mp.add_key_binding("MBTN_RIGHT", "back_to_group_mouse", function() hide(true) end)
    end
end

function select_channel(group_name, channel_index, bDontShowMenu)
    local group = channel_groups[group_name]

    if group then
        local channel = group[channel_index]
        if channel then 
            --msg.warn("sc|"..group_name.."|"..channel_index)
            current_channel.idx = channel_index
            current_channel.name = channel.name
            current_group.name = group_name --channel.group_name
            current_channel.group_name = group_name --channel.group_name
            current_channel.urls = channel.urls

            if not bDontShowMenu then
                show_channels_menu(group_name, menu_state.channel_page)
            end

            return true
        end
    end

    return false
end

local playlist_entry_fmt = "%02d.%02d.%04d %02d:%02d-%02d:%02d %s"
local programme_entry_fmt = "%sПЕРЕДАЧА %03d, %s МИНУТ%s"

function programme_generator(padding)
    return programme_generator_base(48, 2, padding)
end

function programme_generator_base(offset, delta, padding)
    local programme = {}

    delta = delta * 3600
    offset = offset * 3600

    if not padding then padding = '' end

    local stop = math.floor(os.time() / delta) * delta
    local idx = 1

    for start = stop - offset, stop, delta do
        local title = programme_entry_fmt:format(padding, idx, (delta / 60), padding)
        table.insert(programme, {start=start, stop = start + delta, title=title})
        idx = idx + 1
    end

    return programme
end

function play_channel(group_name, channel_index, programme_id)

    mp.set_property("loop-file", "no")

    if select_channel(group_name, channel_index, true) then
        mp.commandv("stop")
        mp.commandv("playlist-clear")
        current_playlist = {}

        local ctime = os.time()

        local channel = channel_groups[group_name][current_channel.idx]

        local play_index = 0

        local programme = {}

        if channel.isIPTV then
            set_window_title(string.format("%s/%s", current_channel.group_name, current_channel.name))
        else
            --set_window_title(current_channel.group_name)
            set_window_title(string.format("%s/%s", current_channel.group_name, current_channel.name))
        end

        if programme_id and epg_programmes[programme_id] then

            local temp = epg_programmes[programme_id]

            if temp[#temp].stop <= os.time() then -- программа закончилась

                for _, info in ipairs(temp) do
                    table.insert(programme, info)
                end

                for start = temp[#temp].stop, os.time(), 3600 do
                    table.insert(programme, {start=start, stop=start+3600, title = "Название отсутствует..."})
                end
            else
                programme = temp
            end
        elseif channel.isIPTV then
            programme = programme_generator()
        end

        for i, info in ipairs(programme) do

            if info.start > ctime then
                break
            end

            local start = os.date("*t", info.start)
            local stop = os.date("*t", info.stop)
            
            local url = channel.urls[1].url

            local file = url:match("/([^/]+)%?") -- channel.catchup_type == 2

            if file then

                local delta = string.format("-%d-%d", info.start, info.stop - info.start)
                
                url, cnt = url:gsub("/index%.m3u8%?", "/index"..delta..".m3u8?")

                if cnt == 0 then
                    url, cnt = url:gsub("/mono%.m3u8%?", "/mono"..delta..".m3u8?")
                end

            else
                url = url.."?utc="..info.start.."&lutc="..info.stop
            end

            local fmt = playlist_entry_fmt:format(start.day, start.month, start.year, start.hour, start.min, stop.hour, stop.min, "%s")

            table.insert(current_playlist, {title = info.title, fmt = fmt, start = info.start, stop = info.stop, isIPTV = channel.isIPTV})
            mp.commandv("loadfile", url, "append")

            if i == current_channel.programme_idx then play_index = #current_playlist - 1 end
        end
        
        if channel.isIPTV then
            local title = "Прямой эфир ..."
            table.insert(current_playlist, {title = title, fmt = nil, start = 0, stop = 0, isIPTV = channel.isIPTV })
            mp.commandv("loadfile", channel.urls[1].url, "append")

            if current_channel.programme_idx == 0 then play_index = #current_playlist - 1 end
        else
            for _, entry in ipairs(channel.urls) do
                
                local title = ""

                if entry.resolution then
                    title = entry.resolution .. "p, "
                    play_index = #channel.urls - 1
                elseif entry.episode then
                    title = entry.episode .. ", "
                elseif entry.video_options then
                    title = "Вариант "..entry.video_options .. ", "
                end

                title = title .. current_channel.name

                table.insert(current_playlist, {title = title, fmt = nil, start = 0, stop = 0, isIPTV = channel.isIPTV })

                mp.commandv("loadfile", entry.url, "append")
            end
        end

        PlayPlayListEntry(play_index)

        hide_menu()
    end        
end

function clear_temp_bindings()
        -- Очищаем все привязки
        for i = 0, 9 do
            mp.remove_key_binding("item_" .. i)
            mp.remove_key_binding("item_ctrl_" .. i)
        end
        
        mp.remove_key_binding("back_to_channel")
        mp.remove_key_binding("back_to_group")
        mp.remove_key_binding("back_to_group_mouse")

        -- Навигация
        mp.remove_key_binding("page_prev")
        mp.remove_key_binding("page_next")

        mp.remove_key_binding("item_prev")
        mp.remove_key_binding("item_prev_mouse")
        mp.remove_key_binding("item_next")
        mp.remove_key_binding("item_next_mouse")

        mp.remove_key_binding("show_channels_menu")
        mp.remove_key_binding("show_channels_menu_mouse")

        mp.remove_key_binding("play_channel")
        mp.remove_key_binding("play_channel_mouse")

        mp.remove_key_binding("programme_show")
        mp.remove_key_binding("programme_show_mouse")
end

function hide_menu()
    if menu_state.type and not osd_overlay.hidden then
        show_menu()
        return true
    end

    return false
end

function show_menu()
    mp.remove_key_binding("show-menu")

    if menu_state.type and not osd_overlay.hidden then
        clear_temp_bindings()
        osd_overlay.hidden = true
        osd_overlay:update()

        show_osd_media_info(15)

    elseif not menu_state.type then

        if GLOBAL_PLAYLIST_INDEX then
            clear_temp_bindings()
            if load_m3u_epg() then
                current_group.idx = 1
                current_group.page = 1
                show_groups_menu(1)
                hide_console()
                mp.add_key_binding("Esc", "show-menu", show_menu)
            end
        else
            mp.commandv("script-binding", "select-iptv-self")
            mp.add_key_binding(nil, "show-menu", show_menu)
        end
        return
    elseif menu_state.type == "groups" then
        show_groups_menu(menu_state.group_page)
    elseif menu_state.type == "channels" then
        show_channels_menu(menu_state.group_name, menu_state.channel_page)
    elseif programme_show then
        programme_show()
    end

    mp.add_key_binding("Esc", "show-menu", show_menu)
end

mp.add_key_binding(nil, "show-menu", show_menu)

function PlayPlayListEntry(idx)
    mp.commandv("playlist-play-index", idx)
    mp.add_timeout(2, function()
        mp.commandv("set", "pause", "no")
    end)
end

function eof_reached(name, value)

    if value == true and #current_playlist ~= 0 then
        local idx = mp.get_property("playlist-playing-pos") + 1

        if idx > 0 and idx ~= #current_playlist then

            local time_pos = mp.get_property_number("time-pos")
            local duration = mp.get_property_number("duration")

            local current = current_playlist[idx]

            if time_pos > 0 and duration > 0 and current.start > 0 and current.stop > 0 then

                local programme_duration = current.stop - current.start
                --mp.msg.info("EOF reached, " .. time_pos .. "-" .. duration .. ", pd=" .. programme_duration)
                mp.commandv("set", "pause", "yes")

                if (programme_duration - duration) > 10 or os.time() <  current.stop then
                    mp.commandv("playlist-play-index", idx - 1)
                    mp.add_timeout(2, function()
                        if duration ~= mp.get_property_number("duration") then
                            mp.commandv("seek", duration, "absolute")
                            mp.commandv("set", "pause", "no")
                        else
                            PlayPlayListEntry(idx)
                        end
                    end)
                else
                    PlayPlayListEntry(idx)
                end
            end
        end
    end
end

mp.observe_property("eof-reached", "bool", eof_reached)

local function fix_media_title()
    if #current_playlist ~= 0 then
        local index = mp.get_property("playlist-playing-pos") + 1
        if index > 0 then
            local entry = current_playlist[index]

            if entry.fmt then
                title = entry.fmt:format(entry.title)
            else
                title = entry.title
            end

            if entry.isGroupList then
                current_channel.idx = index
            end

            mp.set_property("file-local-options/force-media-title", title)
        end
    end
end

mp.register_event("file-loaded", function(event)
--    msg.warn("file-loaded")
    fix_media_title()
    show_osd_media_info(15)
end)    

mp.add_hook("on_load", 10, function(event)
    mp.set_property("file-local-options/user-agent", APP_USER_AGENT)
end)    

mp.register_event("start-file", function(event)
--    msg.warn("start-file")
    fix_media_title()
end)    

mp.add_hook("on_load_fail", 10, function(event)
--    msg.warn("on_load_fail" .. utils.format_table(event))
--[[     
    local fn = mp.get_property("stream-open-filename", nil)
    if fn then
        msg.warn("Ошибка потока. " .. fn)
        show_console()
    end
 ]]
end)

mp.register_event("end-file", function(event)
--    msg.warn("end-file" .. utils.format_table(event))
end)    

--[[ 
mp.add_hook("on_after_end_file", 10, function(event)
end)
 ]]

--[[ 
 mp.register_event("end-file", function(event)
end)
 ]]

local osd_message_hide_function = nil

function show_osd_message(time, title, text)

    if (title or text) and time and time > 0 then

        if osd_message_hide_function then osd_message_hide_function() end

        if not title then title = "" end
        if not text then text = "" end

        local hide_done = false

        osd_message_hide_function = function()
            if osd_message_hide_function then
                osd_message_hide_function = nil

                mp.remove_key_binding("hide")
                mp.remove_key_binding("hide_mouse")

                osd_overlay.hidden = true
                osd_overlay:update()
            end
        end

        osd_overlay.data = string.format("{\\fs%d}\n%s\n\n\n%s", DEFAULT_FONT_SIZE + 2, title, text)
        osd_overlay.hidden = false
        osd_overlay:update()

        mp.add_timeout(time, osd_message_hide_function)
        mp.add_key_binding("MBTN_LEFT", "hide_mouse", osd_message_hide_function)
        mp.add_forced_key_binding("Esc", "hide", osd_message_hide_function)
        
    end
end

function show_osd_media_info(time)
    if time and time > 0 then
        local title = mp.get_property("metadata/by-key/Title")
        local desc = mp.get_property("metadata/by-key/Description")

        if desc then
            show_osd_message(time, title, desc)
        end
    end

    mp.commandv("script-message-to", "modernz", "osc-show")
end

mp.add_key_binding("Ctrl+c", "video-center", function()
    mp.set_property("video-zoom", 0)
    mp.set_property("video-pan-x", 0)
    mp.set_property("video-pan-y", 0)    
end)

function get_playlist_fixes(url)
    for _, entry in ipairs(IPTV_JSON_CONFIG.m3uInit) do
        if not entry.isEpg and entry.url==url then            
            return entry.fixes
        end
    end

    return nil
end

function get_playlist_entries(index)

    local entries = {}

    for _, entry in ipairs(IPTV_JSON_CONFIG.links) do
        if not entry.isEpg then
            table.insert(entries, entry)
        end
    end

    if not index then
        return entries
    end

    return { entries[index] }
    
end

function get_playlists_name_url()
    local names = {}
    local urls = {}

    for _, entry in ipairs(get_playlist_entries()) do

        table.insert(urls, entry.url)

        if entry.name then
            table.insert(names, entry.name)
        else
            table.insert(names, entry.url)
        end
    end

    return names, urls
end

mp.add_forced_key_binding(nil, "select-iptv-self", function ()
    
    local names, urls = get_playlists_name_url()

    if #urls > 0 then

        local default_item = GLOBAL_PLAYLIST_INDEX or 1

        table.insert(names, "Обновить старые M3U и EPG")
        table.insert(names, "Обновить старые и имеющие ETag/LM M3U и EPG")
        table.insert(names, "Перезагрузить все M3U и EPG")

        mp.commandv("set", "pause", "yes")

        input.select({
            --prompt = "Выбор playlist для просмотра",
            items = names,
            default_item = default_item,

            submit = function (index)
                
                if index > #urls then
                    MpvIptvUtils.BindKeySelectPlaylist(false)
                    IPTV_JSON_CONFIG = MpvIptvUtils.LoadJsonFile(IPTV_JSON_CONFIG_FILE)
                    MpvIptvUtils.LoadAndUpdatePlaylistAndEpg(IPTV_JSON_CONFIG, IPTV_JSON_CONFIG_FILE, index - #urls)
                    show_console()

                else --if GLOBAL_PLAYLIST_INDEX ~= index then
                    MpvIptvUtils.BindKeySelectPlaylist(false)
                    full_init()
                    GLOBAL_PLAYLIST_INDEX = index
                
                    show_console()
                    show_menu()
                    MpvIptvUtils.BindKeySelectPlaylist(true)
                end
            end,
        })

    end
end)

mp.add_forced_key_binding("g-c", "select-channel-list-self", function ()

    if menu_state.type == "channels" and menu_state.group_names and #menu_state.group_names > 0 then

        menu_state.group_name = menu_state.group_names[current_group.idx ~= 0 and current_group.idx or 1]

        local channels = channel_groups[menu_state.group_name]

        if channels and #channels > 1 then

            local items = {}

            for i, channel in ipairs(channels) do
                --channels[i] = string.format("%d. %s\u{00A0}", i, channel.name)
                items[i] = string.format("%d. %s", i, channel.name)
            end

            local bResult = hide_menu()

            --local prompt = string.format("%s: ", menu_state.group_name)
            local prompt = "Выбор потока из группы: "

            input.select({
                prompt = prompt,
                items = items,
                default_item = current_channel.idx,
                closed = function ()
                    if prompt and bResult then
                        show_menu()
                    end
                end,
                submit = function (index)
                    prompt = nil
                    menu_state.channel_page = math.ceil(index / CHANNELS_PER_PAGE)

                    if #current_playlist ~= #channels or channels[index].urls[1].url ~= mp.get_property("playlist/"..(index-1).."/filename") then
                        mp.commandv("stop")
                        mp.commandv("playlist-clear")
                        current_playlist = {}

                        for i, channel in ipairs(channels) do
                            table.insert(current_playlist, {title = items[i], isGroupList = true})
                            mp.commandv("loadfile", channel.urls[1].url, "append")
                        end
                    
                        set_window_title("ГРУППА "..menu_state.group_name)
                    end

                    current_channel.idx = index
                    PlayPlayListEntry(index - 1)

                    --play_channel(menu_state.group_name, index)
                end,
            })
        end
    end

end)

mp.add_key_binding("ctrl+left", "play-list-prev-self", function ()
    mp.command("playlist-prev")
end)

mp.add_key_binding("ctrl+right", "play-list-next-self", function ()
    mp.command("playlist-next")
end)

mp.add_key_binding("ctrl+up", "show_select-play-list-self", function ()
     mp.commandv("script-binding", "select-play-list-self")
end)

mp.add_key_binding("ctrl+down", "show-select-channel-list-self", function ()
     mp.commandv("script-binding", "select-channel-list-self")
end)


mp.add_forced_key_binding("g-p", "select-play-list-self", function ()

    if #current_playlist < 2 then
        return
    end

    hide_menu()

    local playlist = {}
    local default_item

    for i, entry in ipairs(mp.get_property_native("playlist")) do

        local title_entry = current_playlist[i]

        if title_entry.fmt then
            playlist[i] = title_entry.fmt:format(title_entry.title) 
        else
            playlist[i] = title_entry.title
        end

        --playlist[i] = playlist[i]:gsub(" ", "\u{00A0}")
        
        if entry.playing then
            default_item = i
        end
    end
    
    local prompt = "Выбор программы передач: "

    if current_playlist[1].isGroupList then

        prompt = "Выбор из списка проигрывания: "

    elseif not current_playlist[1].isIPTV then

        if current_playlist[1].title:startswith("S") then
            prompt = "Выбор серии в сезоне: "
        else
            prompt = "Выбор разрешения фильма: "
        end

    end
    
    local title = nil

    input.select({
        prompt = prompt,
        items = playlist,
        default_item = default_item,
        closed = function ()
            if not title then
                show_osd_media_info(15)
            end
        end,
        submit = function (index)
            --title = current_playlist[index].title
            --mp.commandv("playlist-play-index", index - 1)

            if current_playlist[index].isGroupList then
                current_channel.idx = index
            end

            PlayPlayListEntry(index - 1)
        end,
    })

end)


--[[ local overlay_add_args = {
    "overlay-add", 1, 1400, 0,
    IPTV_TEMP_DIR .. "1.bgra",
    0, "bgra", 220, 132, 4 * 220
}

mp.command_native(overlay_add_args)
 ]]

set_window_title()

msg.warn(APP_USER_AGENT)
mp.set_property("loop-file", "no")

--mp.commandv("loadfile", mp.command_native({ "expand-path", "~~/30c4e2cc-8b20-479e-89f8-28677973fb24.mp4" }), "replace", 0, "start=0")
--mp.commandv("script-message-to", "modernz", "osc-show")

IPTV_JSON_CONFIG = MpvIptvUtils.LoadJsonFile(IPTV_JSON_CONFIG_FILE)
MpvIptvUtils.LoadAndUpdatePlaylistAndEpg(IPTV_JSON_CONFIG, IPTV_JSON_CONFIG_FILE)
show_console()
