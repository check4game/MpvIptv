local MpvIptvUtf8 = {}

local lower_to_upper = {
    -- Русские буквы
    ["а"] = "А", ["б"] = "Б", ["в"] = "В", ["г"] = "Г", ["д"] = "Д",
    ["е"] = "Е", ["ё"] = "Ё", ["ж"] = "Ж", ["з"] = "З", ["и"] = "И",
    ["й"] = "Й", ["к"] = "К", ["л"] = "Л", ["м"] = "М", ["н"] = "Н",
    ["о"] = "О", ["п"] = "П", ["р"] = "Р", ["с"] = "С", ["т"] = "Т",
    ["у"] = "У", ["ф"] = "Ф", ["х"] = "Х", ["ц"] = "Ц", ["ч"] = "Ч",
    ["ш"] = "Ш", ["щ"] = "Щ", ["ъ"] = "Ъ", ["ы"] = "Ы", ["ь"] = "Ь",
    ["э"] = "Э", ["ю"] = "Ю", ["я"] = "Я",

    -- Латинские буквы
    ["a"] = "A", ["b"] = "B", ["c"] = "C", ["d"] = "D", ["e"] = "E",
    ["f"] = "F", ["g"] = "G", ["h"] = "H", ["i"] = "I", ["j"] = "J",
    ["k"] = "K", ["l"] = "L", ["m"] = "M", ["n"] = "N", ["o"] = "O",
    ["p"] = "P", ["q"] = "Q", ["r"] = "R", ["s"] = "S", ["t"] = "T",
    ["u"] = "U", ["v"] = "V", ["w"] = "W", ["x"] = "X", ["y"] = "Y",
    ["z"] = "Z",

    -- Дополнительные символы
    ["і"] = "І", ["ї"] = "Ї", ["є"] = "Є", ["ґ"] = "Ґ"
}

local upper_to_lower = {
    -- Русские буквы
    ["А"] = "а", ["Б"] = "б", ["В"] = "в", ["Г"] = "г", ["Д"] = "д",
    ["Е"] = "е", ["Ё"] = "ё", ["Ж"] = "ж", ["З"] = "з", ["И"] = "и",
    ["Й"] = "й", ["К"] = "к", ["Л"] = "л", ["М"] = "м", ["Н"] = "н",
    ["О"] = "о", ["П"] = "п", ["Р"] = "р", ["С"] = "с", ["Т"] = "т",
    ["У"] = "у", ["Ф"] = "ф", ["Х"] = "х", ["Ц"] = "ц", ["Ч"] = "ч",
    ["Ш"] = "ш", ["Щ"] = "щ", ["Ъ"] = "ъ", ["Ы"] = "ы", ["Ь"] = "ь",
    ["Э"] = "э", ["Ю"] = "ю", ["Я"] = "я",

    -- Латинские буквы
    ["A"] = "a", ["B"] = "b", ["C"] = "c", ["D"] = "d", ["E"] = "e",
    ["F"] = "f", ["G"] = "g", ["H"] = "h", ["I"] = "i", ["J"] = "j",
    ["K"] = "k", ["L"] = "l", ["M"] = "m", ["N"] = "n", ["O"] = "o",
    ["P"] = "p", ["Q"] = "q", ["R"] = "r", ["S"] = "s", ["T"] = "t",
    ["U"] = "u", ["V"] = "v", ["W"] = "w", ["X"] = "x", ["Y"] = "y",
    ["Z"] = "z",

    -- Дополнительные символы
    ["І"] = "і", ["Ї"] = "ї", ["Є"] = "є", ["Ґ"] = "ґ"
}

local function utf8char_size_in_bytes(byte)
    if byte < 0x80 then return 1 end      -- ASCII

    --if byte < 0xC0 then ERROR end

    if byte < 0xE0 then return 2 end      -- 2 байта
    if byte < 0xF0 then return 3 end      -- 3 байта
    return 4                              -- 4 байта
end

function MpvIptvUtf8.len(str)
    local count = 0
    local i = 1

    while i <= #str do
        count = count + 1
        i = i + utf8char_size_in_bytes(string.byte(str, i))
    end
    
    return count
end

local function charMapper(str, map)

    local i = 1

    local result = {}

    while i <= #str do
        local byte = string.byte(str, i)

        local pos = i

        i = i + utf8char_size_in_bytes(string.byte(str, i))

        local char = string.sub(str, pos, i - 1)

        table.insert(result, upper_to_lower[char] or char)
    end
    
    return table.concat(result)

end

function MpvIptvUtf8.upper(str)
    return charMapper(str, upper_to_lower)
end

function MpvIptvUtf8.lower(str)
    return charMapper(str, lower_to_upper)
end

local function starts_with_utf8(str)
    return string.byte(str, 1) >= 0xC0
end

local function toUpperChar(char)
    return lower_to_upper[char] or char
end

function MpvIptvUtf8.capitalize(str)
    if str == "" then return str end

    local size = utf8char_size_in_bytes(string.byte(str, 1))
    return toUpperChar(string.sub(str, 1, size)) .. string.sub(str, size + 1)
end

function MpvIptvUtf8.sort(t, accessor)

    if not accessor then
        accessor = function(entry)
            return entry
        end
    end

    return table.sort(t, function(a, b)

        local a_is_utf8 = starts_with_utf8(accessor(a))
        local b_is_utf8 = starts_with_utf8(accessor(b))

        if a_is_utf8 and not b_is_utf8 then
            return true
        elseif not a_is_utf8 and b_is_utf8 then
            return false
        else
            return accessor(a) < accessor(b)
        end
    end)
end

function MpvIptvUtf8.IsRtl(str)

    if type(str) ~= "string" then
        return false
    end

    -- Проверка на RLM
    if str:find("\226\128\143") then
        return true
    end

    -- Проверка на 2-байтные символы (например, Hebrew U+0590-U+05CF)
    -- UTF-8 для U+0590 - U+05FF: [11010110] [10xxxxxx] -> D6 [80-BF] или [11010111] [10xxxxxx] -> D7 [80-BF]
    -- Это соответствует паттерну: [\214-\215][\128-\191] (десятичные)
    if str:find("[\214-\215][\128-\191]") then
        return true
    end

    -- Проверка на 3-байтные символы (например, Arabic U+0600-U+06FF)
    -- UTF-8 для U+0600 - U+06FF: [11011000] [10xxxxxx] [10xxxxxx] -> D8 [80-BF] [80-BF], ...
    -- Это соответствует паттерну: [\216-\219][\128-\191][\128-\191], но find ищет по байтам
    -- Нам хватит проверки на первый байт [\216-\219]
    if str:find("[\216-\219]") then
        return true
    end

    return false
end


return MpvIptvUtf8