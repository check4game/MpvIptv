local MpvIptvGroups = {}

local ChannelsMin = 3

local generator = function(channel_groups, snames, tname, filters)
    
    if not channel_groups[tname] then
        for _, gname in ipairs(snames) do 

            if channel_groups[gname] then

                local channels = channel_groups[tname] or {}

                for _, channel in ipairs(channel_groups[gname]) do
                    
                    for _, filter in ipairs(filters) do 

                        if channel.name:find(filter) then

                            channel = copy_table(channel)
                            channel.group_name = tname

                            table.insert(channels, channel);

                            break
                        end
                    end
                end

                if #channels >= ChannelsMin then
                    channel_groups[tname] = channels
                end
            end
        end
    end
end

local hd = {
    "Общие", "Россия", "Федеральные", "Общероссийские",
    "Украина", "Беларусь",
    "Музыкальные", "Мультфильмы",
    "Новости", "Новостные",
    "Кино", "Фильмы и сериалы", "Кинозалы",
    "Детские", "Природа", "Спорт", "Спортивные",
    "Познавательные", "Образовательные", "Развлекательные", "Образование" 
}

function MpvIptvGroups.GroupGenerator(channel_groups)
    
    for _, name in ipairs(hd) do
        generator(channel_groups, { name }, name.." HD", {" HD ", " HD$", " 4K$", " UHD$"})
    end

    local mGroups = {"Музыкальные", "Музыка"}
    generator(channel_groups, mGroups, "Музыкальные Liberty", {"^Liberty "})
    generator(channel_groups, mGroups, "Музыкальные Bridge", {"^Bridge "})
    generator(channel_groups, mGroups, "Музыкальные VB", {"^VB "})
    generator(channel_groups, mGroups, "Музыкальные RTL", {"^RTL "})
    generator(channel_groups, mGroups, "Музыкальные MTV", {"^MTV "})
    generator(channel_groups, mGroups, "Музыкальные Fresh", {"^Fresh "})
    generator(channel_groups, mGroups, "Музыкальные Velilla", {"^Velilla "})
    generator(channel_groups, mGroups, "Музыкальные Stingray", {"^Stingray "})
    
    local kGroups = {"UHD", "HDR", "KinoINT", "Кинозалы", "Кино", "Фильмы и сериалы"}

    generator(channel_groups, kGroups, "Кинозал Viju", {"^viju", "^Viju"})
    generator(channel_groups, kGroups, "Кинозал Karlson", {"^Karlson "})
    generator(channel_groups, kGroups, "Кинозал TEAM", {"^TEAM "})
    generator(channel_groups, kGroups, "Кинозал BCU", {"^BCU "})
    generator(channel_groups, kGroups, "Кинозал MM", {"^MM "})
    generator(channel_groups, kGroups, "Кинозал CineMan", {"^CineMan "})
    generator(channel_groups, kGroups, "Кинозал Yosso", {"^Yosso TV "})
    generator(channel_groups, kGroups, "Кинозал Magic", {"^Magic "})
    generator(channel_groups, kGroups, "Кинозал Fresh", {"^Fresh "})
    generator(channel_groups, kGroups, "Кинозал Liberty", {"^Liberty "})
    generator(channel_groups, kGroups, "Кинозал Sky High", {"^Sky High "})
    generator(channel_groups, kGroups, "Кинозал BOX", {"^BOX "})
    generator(channel_groups, kGroups, "Кинозал VeleS", {"^VeleS "})
    generator(channel_groups, kGroups, "Кинозал Oasis", {"^Oasis "})
    generator(channel_groups, kGroups, "Кинозал KBC", {"^KBC-"})
    generator(channel_groups, kGroups, "Кинозал Gold Line", {"^Gold Line ", "^GL "})
    generator(channel_groups, kGroups, "Кинозал Velilla TV", {"^Velilla TV "})
    generator(channel_groups, kGroups, "Кинозал Kernel TV", {"^Kernel TV "})
    generator(channel_groups, kGroups, "Кинозал SkyCam", {"^SkyCam "})
    generator(channel_groups, kGroups, "Кинозал TVPlay", {"^TVPlay "})
    generator(channel_groups, kGroups, "Кинозал Clarity4K", {"^Clarity4K Cinema "})

end

return MpvIptvGroups