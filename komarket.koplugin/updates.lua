--[[--
Detect updates for user-installed plugins (data/plugins only, not KOReader built-ins).
]]

local DataStorage = require("datastorage")
local JSON = require("json")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Catalog = require("catalog")
local Installer = require("installer")

local Updates = {}

local CACHE_DIR = DataStorage:getDataDir() .. "/cache/komarket"
local REGISTRY_FILE = CACHE_DIR .. "/installed.json"
local SELF_DIRNAME = "komarket.koplugin"

local function pathMode(path)
    local attr = lfs.attributes(path)
    return attr and attr.mode or nil
end

local function ensureCacheDir()
    if pathMode(CACHE_DIR) == "directory" then
        return true
    end
    local parent = DataStorage:getDataDir() .. "/cache"
    if pathMode(parent) ~= "directory" then
        lfs.mkdir(parent)
    end
    return lfs.mkdir(CACHE_DIR)
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local data = f:read("*a")
    f:close()
    return data
end

local function writeFile(path, data)
    ensureCacheDir()
    local f, err = io.open(path, "wb")
    if not f then
        return nil, err
    end
    f:write(data)
    f:close()
    return true
end

local function normalizeVersion(v)
    if v == nil then
        return nil
    end
    v = tostring(v):lower():gsub("^v", ""):gsub("%s+", "")
    if v == "" then
        return nil
    end
    return v
end

local function versionParts(v)
    local parts = {}
    local norm = normalizeVersion(v)
    if not norm then
        return parts
    end
    for num in norm:gmatch("%d+") do
        parts[#parts + 1] = tonumber(num)
    end
    if #parts == 0 then
        parts[1] = norm
    end
    return parts
end

function Updates.compareVersion(a, b)
    local pa, pb = versionParts(a), versionParts(b)
    if #pa == 0 and #pb == 0 then
        return 0
    end
    if #pa == 0 then
        return -1
    end
    if #pb == 0 then
        return 1
    end
    local n = math.max(#pa, #pb)
    for i = 1, n do
        local va, vb = pa[i] or 0, pb[i] or 0
        if type(va) == "string" or type(vb) == "string" then
            local sa, sb = tostring(pa[i] or ""), tostring(pb[i] or "")
            if sa < sb then return -1 end
            if sa > sb then return 1 end
        else
            if va < vb then return -1 end
            if va > vb then return 1 end
        end
    end
    return 0
end

function Updates.readLocalVersion(install_dirname)
    local base = Installer.pluginsDir() .. "/" .. install_dirname
    local version_file = base .. "/_version.lua"
    if pathMode(version_file) ~= "file" then
        return nil
    end
    local chunk, err = loadfile(version_file)
    if not chunk then
        logger.warn("KOMarket updates: load _version.lua failed", install_dirname, err)
        return nil
    end
    local ok, ver = pcall(chunk)
    if not ok then
        return nil
    end
    if type(ver) == "string" then
        return ver
    end
    if type(ver) == "table" and ver.version then
        return tostring(ver.version)
    end
    return nil
end

function Updates.loadRegistry()
    local raw = readFile(REGISTRY_FILE)
    if not raw or raw == "" then
        return {}
    end
    local ok, data = pcall(JSON.decode, raw)
    if ok and type(data) == "table" then
        return data
    end
    return {}
end

function Updates.saveRegistry(reg)
    writeFile(REGISTRY_FILE, JSON.encode(reg or {}) .. "\n")
end

function Updates.recordInstall(plugin)
    if type(plugin) ~= "table" or type(plugin.install_dirname) ~= "string" then
        return
    end
    local reg = Updates.loadRegistry()
    reg[plugin.install_dirname] = {
        id = plugin.id,
        name = plugin.name,
        download_url = plugin.download_url,
        latest_tag = plugin.latest_tag,
        updated_at = plugin.updated_at,
        local_version = Updates.readLocalVersion(plugin.install_dirname),
        installed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    Updates.saveRegistry(reg)
end

function Updates.forgetInstall(install_dirname)
    local reg = Updates.loadRegistry()
    reg[install_dirname] = nil
    Updates.saveRegistry(reg)
end

function Updates.indexCatalog(catalog)
    local map = {}
    for _, plugin in ipairs((catalog and catalog.plugins) or {}) do
        if type(plugin.install_dirname) == "string" and plugin.install_dirname ~= "" then
            map[plugin.install_dirname] = plugin
        end
    end
    return map
end

function Updates.listUserInstalled()
    local dir = Installer.pluginsDir()
    if pathMode(dir) ~= "directory" then
        return {}
    end
    local names = {}
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." and name:match("%.koplugin$") then
            if name ~= SELF_DIRNAME then
                local plugin_dir = dir .. "/" .. name
                if pathMode(plugin_dir) == "directory"
                    and pathMode(plugin_dir .. "/_meta.lua") == "file" then
                    names[#names + 1] = name
                end
            end
        end
    end
    table.sort(names)
    return names
end

local function remoteLabel(plugin)
    if plugin.latest_tag and plugin.latest_tag ~= "" then
        return tostring(plugin.latest_tag)
    end
    if plugin.updated_at and plugin.updated_at ~= "" then
        return tostring(plugin.updated_at):sub(1, 10)
    end
    return "?"
end

local function localLabel(local_version, registry)
    if local_version and local_version ~= "" then
        return tostring(local_version)
    end
    if registry and registry.local_version and registry.local_version ~= "" then
        return tostring(registry.local_version)
    end
    if registry and registry.latest_tag and registry.latest_tag ~= "" then
        return tostring(registry.latest_tag)
    end
    return _("未知")
end

function Updates.isUpdateAvailable(install_dirname, catalog_plugin, registry_entry)
    if not catalog_plugin or not Catalog.isDownloadUrlAllowed(catalog_plugin.download_url) then
        return false
    end

    local local_version = Updates.readLocalVersion(install_dirname)
    local remote_version = catalog_plugin.latest_tag

    if local_version and remote_version then
        if Updates.compareVersion(local_version, remote_version) < 0 then
            return true
        end
    end

    if registry_entry then
        if registry_entry.download_url
            and catalog_plugin.download_url
            and registry_entry.download_url ~= catalog_plugin.download_url then
            return true
        end
        if registry_entry.latest_tag
            and remote_version
            and registry_entry.latest_tag ~= remote_version then
            if not local_version or Updates.compareVersion(local_version, remote_version) <= 0 then
                return true
            end
        end
    end

    return false
end

function Updates.scan(catalog)
    local by_dir = Updates.indexCatalog(catalog)
    local registry = Updates.loadRegistry()
    local updates = {}

    for _, dirname in ipairs(Updates.listUserInstalled()) do
        local catalog_plugin = by_dir[dirname]
        local registry_entry = registry[dirname]
        if catalog_plugin and Updates.isUpdateAvailable(dirname, catalog_plugin, registry_entry) then
            local local_version = Updates.readLocalVersion(dirname)
            updates[#updates + 1] = {
                plugin = catalog_plugin,
                install_dirname = dirname,
                local_version = local_version,
                local_label = localLabel(local_version, registry_entry),
                remote_label = remoteLabel(catalog_plugin),
            }
        end
    end

    table.sort(updates, function(a, b)
        return tostring(a.plugin.name or a.install_dirname)
            < tostring(b.plugin.name or b.install_dirname)
    end)

    return updates
end

return Updates
