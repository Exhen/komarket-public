--[[--
Build plugin-list payload for share (no zip).
]]

local Updates = require("updates")

local SharePack = {}

function SharePack.build(catalog)
    local by_dir = Updates.indexCatalog(catalog)
    local items = {}

    for _, dirname in ipairs(Updates.listUserInstalled()) do
        local plugin = by_dir[dirname]
        local stars = plugin and tonumber(plugin.stars) or 0
        items[#items + 1] = {
            install_dirname = dirname,
            id = plugin and plugin.id or nil,
            name = (plugin and plugin.name) or dirname:gsub("%.koplugin$", ""),
            _stars = stars,
        }
    end

    if #items == 0 then
        return nil, "no plugins to share"
    end

    table.sort(items, function(a, b)
        if a._stars ~= b._stars then
            return a._stars > b._stars
        end
        return tostring(a.name) < tostring(b.name)
    end)

    for i = 1, #items do
        items[i]._stars = nil
    end

    return {
        schema_version = 1,
        kind = "plugin_list",
        plugins = items,
    }
end

return SharePack
