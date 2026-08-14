--[[--
Resolve and sequentially install a shared plugin list.
]]

local Catalog = require("catalog")
local Installer = require("installer")
local Updates = require("updates")

local ShareImport = {}

function ShareImport.resolvePlugins(share_plugins, catalog)
    if type(share_plugins) ~= "table" then
        return nil, nil, "invalid plugin list"
    end
    if #share_plugins == 0 then
        return nil, nil, "empty plugin list"
    end

    local by_dir = Updates.indexCatalog(catalog)
    local by_id = {}
    for _, plugin in ipairs((catalog and catalog.plugins) or {}) do
        if type(plugin.id) == "string" and plugin.id ~= "" then
            by_id[plugin.id] = plugin
        end
    end

    local resolved = {}
    local missing = {}

    for _, item in ipairs(share_plugins) do
        local dirname = item.install_dirname
        local plugin = dirname and by_dir[dirname] or nil
        if not plugin and item.id then
            plugin = by_id[item.id]
        end
        if plugin and Catalog.isDownloadUrlAllowed(plugin.download_url) then
            resolved[#resolved + 1] = plugin
        else
            missing[#missing + 1] = item.name or dirname or "?"
        end
    end

    return resolved, missing
end

function ShareImport.installSequential(plugins, callbacks)
    callbacks = callbacks or {}
    local total = #plugins
    local ok_count = 0
    local skipped = 0
    local failures = {}

    for i, plugin in ipairs(plugins) do
        local name = plugin.name or plugin.install_dirname or "?"

        if callbacks.on_item then
            callbacks.on_item(i, total, plugin, "start")
        end

        if Installer.isInstalled(plugin.install_dirname) then
            skipped = skipped + 1
            ok_count = ok_count + 1
            if callbacks.on_item then
                callbacks.on_item(i, total, plugin, "skip")
            end
        else
            local ok, err = Installer.install(plugin, function(msg)
                if callbacks.on_progress then
                    callbacks.on_progress(i, total, plugin, msg)
                end
            end)
            if ok then
                ok_count = ok_count + 1
                if callbacks.on_item then
                    callbacks.on_item(i, total, plugin, "done")
                end
            else
                failures[#failures + 1] = {
                    plugin = plugin,
                    err = err,
                }
                if callbacks.on_item then
                    callbacks.on_item(i, total, plugin, "fail", err)
                end
            end
        end

        if callbacks.on_step_done then
            callbacks.on_step_done(i, total)
        end
    end

    return {
        total = total,
        ok_count = ok_count,
        skipped = skipped,
        failures = failures,
    }
end

return ShareImport
