local icons = require("icons")
local colors = require("colors")
local settings = require("settings")

-- Provided by joncrangle/sketchybar-system-stats.
sbar.exec("killall stats_provider >/dev/null; stats_provider --disk usage used free total --interval 15")

local disk = sbar.add("item", "widgets.disk", {
    position = "right",
    icon = { string = icons.disk },
    label = {
        string = "disk --%",
        font = {
            family = settings.font.numbers,
            style = settings.font.style_map["Bold"],
            size = 9.0,
        },
        align = "right",
        padding_right = 0,
        y_offset = 4
    },
    padding_right = settings.paddings + 6,
    popup = { align = "center", height = 26 }
})

sbar.add("bracket", "widgets.disk.bracket", { disk.name }, {
    background = { color = colors.bg1 }
})

sbar.add("item", "widgets.disk.padding", {
    position = "right",
    width = settings.group_paddings
})

local disk_details = sbar.add("item", {
    position = "popup." .. disk.name,
    label = {
        string = "waiting for disk stats",
        width = 180,
        align = "left",
    },
    drawing = true
})

disk:subscribe("system_stats", function(env)
    if not env.DISK_USAGE then return end

    local usage = tonumber(env.DISK_USAGE:match("%d+")) or 0
    local color = colors.blue
    if usage > 60 then
        color = usage < 80 and colors.yellow or colors.red
    end

    disk:set({
        icon = { color = color },
        label = { string = "disk " .. env.DISK_USAGE }
    })

    disk_details:set({
        label = {
            string = "used " .. (env.DISK_USED or "?") .. " / " .. (env.DISK_TOTAL or "?") .. "  free " .. (env.DISK_FREE or "?")
        }
    })
end)

disk:subscribe("mouse.clicked", function()
    disk:set({ popup = { drawing = "toggle" } })
end)

disk:subscribe("mouse.exited.global", function()
    disk:set({ popup = { drawing = false } })
end)
