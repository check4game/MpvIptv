local msg = require 'mp.msg'

function string.startswith(str, prefix)
    if prefix then
        return str:sub(1, #prefix) == prefix
    else
        return false
    end
end

function string:contains(substr)
    return self:find(substr, 1, true) ~= nil
end

function string.trim(str)
    return str:match("^%s*(.-)%s*$")
end

function string.normalize_display_name(name)
    local result = name

    result = result:gsub("%s+", " ") -- double space

    -- ua:Перший в Перший, ua: Перший в Перший
    result = result:gsub("^[a-zA-Z][a-zA-Z]:%s?", "")

    -- Private (18+) в Private
    result = result:gsub(" %(18%+%)$", ""):gsub("%.$", "")

    -- Если уже в правильном формате "Россия 1 (+2)", оставляем как есть
    if result:match("%(%+%d+%)") then
        return result
    end
    
    -- Преобразуем "Россия 1 +2 HD" в "Россия 1 (+2) HD"
    return result:gsub(" (%+)(%d+)", " (%1%2)")
end

function string.split_last_word(name)
    -- Находим последнее слово (последний пробел до конца строки)
    local last_word = name:match("%s(%S+)$") or name
    -- Разделяем последнее слово
    local fixed_last = last_word:gsub("([а-яa-z])([А-ЯA-Z])", "%1 %2")
    -- Заменяем в исходной строке
    local result = name:gsub("%s(%S+)$", " " .. fixed_last) or name:gsub("^(%S+)$", fixed_last)

    return result
end

local local_tz_offset = os.difftime(os.time(), os.time(os.date("!*t")))

function string.epg_time_to_seconds(datetime)

    local year,month,day,hour,min,sec,sign,hours,minutes = 
        datetime:match("^(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)(%d%d)%s([+-])(%d%d)(%d%d)$")

    if not year then
        msg.error("unknown format: " .. datetime)
        return nil
    end
    
    local seconds = os.time({day=day,month=month,year=year,hour=hour,min=min})
    local tz_offset = (hours * 3600) + (minutes * 60)
    if sign == "-" then tz_offset = tz_offset * -1 end

    if tz_offset ~= local_tz_offset then
        if tz_offset > local_tz_offset then
            seconds = seconds - (tz_offset - local_tz_offset)
        else
            seconds = seconds + (local_tz_offset - tz_offset)
        end
    end
    
    return seconds
end

local hex_to_char = function(x)
  return string.char(tonumber(x, 16))
end

function string.urldecode(url)
    url = url:gsub("+", " ")
    url = url:gsub("%%(%x%x)", hex_to_char)
  return url
end

function string.find_and_extract(word, url)
    -- Просто ищем word и всё что после него до /
    --msg.warn(word)
    return url:match(word .. "[^/]*") or word
end

function string.split(str, delimiter)
    local result = {}

    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        -- Убираем пробелы в начале и конце
        match = match:match("^%s*(.-)%s*$")
        table.insert(result, match)
    end
    return result
end

return string