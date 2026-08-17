--[[--
Persisted KOMarket user settings (connection mode, custom catalog URL).
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local Config = require("config")
local _ = require("komarket_gettext")

local Settings = {}

local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/komarket.lua"

local MODE_GITHUB = "github"
local MODE_MIRROR = "mirror"
local MODE_CUSTOM = "custom"

Settings.MODE_GITHUB = MODE_GITHUB
Settings.MODE_MIRROR = MODE_MIRROR
Settings.MODE_CUSTOM = MODE_CUSTOM

local _store

local function openStore()
    if not _store then
        _store = LuaSettings:open(SETTINGS_FILE)
    end
    return _store
end

function Settings.getMode()
    local mode = openStore():readSetting("connection_mode")
    if mode == MODE_GITHUB or mode == MODE_MIRROR or mode == MODE_CUSTOM then
        return mode
    end
    return Config.default_connection_mode or MODE_MIRROR
end

function Settings.setMode(mode)
    if mode ~= MODE_GITHUB and mode ~= MODE_MIRROR and mode ~= MODE_CUSTOM then
        return nil, "invalid connection mode"
    end
    local store = openStore()
    store:saveSetting("connection_mode", mode)
    store:flush()
    return true
end

function Settings.getCustomCatalogUrl()
    local url = openStore():readSetting("custom_catalog_url")
    if type(url) == "string" then
        url = url:match("^%s*(.-)%s*$") or ""
        if url ~= "" then
            return url
        end
    end
    return nil
end

function Settings.setCustomCatalogUrl(url)
    if type(url) ~= "string" then
        return nil, _("invalid url")
    end
    url = url:match("^%s*(.-)%s*$") or ""
    if url == "" then
        return nil, _("empty url")
    end
    if not url:match("^https://") then
        return nil, _("url must start with https://")
    end
    local store = openStore()
    store:saveSetting("custom_catalog_url", url)
    store:flush()
    return true
end

--- When true, opening KOMarket refreshes catalog JSON automatically.
--- Default: false (manual "Refresh catalog" only).
function Settings.getAutoRefreshCatalog()
    local v = openStore():readSetting("auto_refresh_catalog")
    if v == true then
        return true
    end
    return false
end

function Settings.setAutoRefreshCatalog(enabled)
    local store = openStore()
    store:saveSetting("auto_refresh_catalog", enabled and true or false)
    store:flush()
    return true
end

--- Catalog index URL for the active connection mode (single primary source).
function Settings.catalogUrl()
    local mode = Settings.getMode()
    if mode == MODE_GITHUB then
        return Config.github_catalog_url
    end
    if mode == MODE_MIRROR then
        return Config.mirror_catalog_url
    end
    return Settings.getCustomCatalogUrl()
end

--- Categories JSON URL derived from the active catalog source.
function Settings.categoriesUrl()
    local mode = Settings.getMode()
    if mode == MODE_GITHUB then
        return Config.github_categories_url
    end
    if mode == MODE_MIRROR then
        return Config.mirror_categories_url
    end
    local catalog_url = Settings.getCustomCatalogUrl()
    if not catalog_url then
        return nil
    end
    if catalog_url:match("index%.json") then
        return catalog_url:gsub("index%.json", "categories.json", 1)
    end
    -- Same directory: replace trailing filename with categories.json
    local base = catalog_url:match("^(.-/)[^/]*$")
    if base then
        return base .. "categories.json"
    end
    return nil
end

function Settings.modeLabel(mode)
    mode = mode or Settings.getMode()
    if mode == MODE_GITHUB then
        return _("GitHub")
    end
    if mode == MODE_MIRROR then
        return _("CN Mirror")
    end
    if mode == MODE_CUSTOM then
        return _("Custom")
    end
    return mode
end

return Settings
