--[[--
Download and install a plugin zip into KOReader plugins/.
]]

local Archiver = require("ffi/archiver")
local DataStorage = require("datastorage")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Catalog = require("catalog")
local Config = require("config")

local Installer = {}

local WORK_DIR = DataStorage:getDataDir() .. "/cache/komarket/work"

local function pathMode(path)
    local attr = lfs.attributes(path)
    return attr and attr.mode or nil
end

local function parentPath(path)
    return path:match("^(.*)/[^/]+$")
end

local function ensureDirectory(path)
    if not path or path == "" or pathMode(path) == "directory" then
        return true
    end
    local parent = parentPath(path)
    if parent and parent ~= path then
        local ok, err = ensureDirectory(parent)
        if not ok then
            return nil, err
        end
    end
    local ok, err = lfs.mkdir(path)
    if ok or pathMode(path) == "directory" then
        return true
    end
    return nil, err
end

local function removeTree(path)
    local mode = pathMode(path)
    if not mode then
        return true
    end
    if mode == "file" or mode == "link" then
        return os.remove(path)
    end
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then
            local ok, err = removeTree(path .. "/" .. name)
            if not ok then
                return nil, err
            end
        end
    end
    return lfs.rmdir(path)
end

local function copyTree(src, dst)
    local mode = pathMode(src)
    if mode == "file" then
        local parent = parentPath(dst)
        if parent then
            local ok, err = ensureDirectory(parent)
            if not ok then
                return nil, err
            end
        end
        return ffiutil.copyFile(src, dst)
    end
    if mode ~= "directory" then
        return nil, "invalid source"
    end
    local ok, err = ensureDirectory(dst)
    if not ok then
        return nil, err
    end
    for name in lfs.dir(src) do
        if name ~= "." and name ~= ".." then
            ok, err = copyTree(src .. "/" .. name, dst .. "/" .. name)
            if not ok then
                return nil, err
            end
        end
    end
    return true
end

local function findPluginRoot(extract_dir, expected_dirname)
    local direct = extract_dir .. "/" .. expected_dirname
    if pathMode(direct) == "directory" and pathMode(direct .. "/_meta.lua") == "file" then
        return direct
    end
    -- GitHub zipball: <repo>-<hash>/ or nested *.koplugin
    for name in lfs.dir(extract_dir) do
        if name ~= "." and name ~= ".." then
            local child = extract_dir .. "/" .. name
            if pathMode(child) == "directory" then
                if pathMode(child .. "/_meta.lua") == "file" then
                    return child
                end
                local nested = child .. "/" .. expected_dirname
                if pathMode(nested) == "directory" and pathMode(nested .. "/_meta.lua") == "file" then
                    return nested
                end
                for name2 in lfs.dir(child) do
                    if name2:match("%.koplugin$") then
                        local n2 = child .. "/" .. name2
                        if pathMode(n2) == "directory" and pathMode(n2 .. "/_meta.lua") == "file" then
                            return n2
                        end
                    end
                end
            end
        end
    end
    return nil
end

function Installer.pluginsDir()
    return DataStorage:getDataDir() .. "/plugins"
end

function Installer.isInstalled(install_dirname)
    return pathMode(Installer.pluginsDir() .. "/" .. install_dirname) == "directory"
end

function Installer.install(plugin, on_status)
    local function status(msg)
        if on_status then
            on_status(msg)
        end
        logger.info("KOMarket install:", msg)
    end

    if type(plugin) ~= "table" then
        return nil, "invalid plugin"
    end
    local dirname = plugin.install_dirname
    local url = plugin.download_url
    if type(dirname) ~= "string" or not dirname:match("%.koplugin$") then
        return nil, "invalid install_dirname"
    end
    if dirname == "komarket.koplugin" then
        -- Allow self-update later; for now block accidental wipe via catalog entry mistakes.
        -- Self-update can be added explicitly.
    end
    if not Catalog.isDownloadUrlAllowed(url) then
        return nil, "download host not allowed"
    end

    removeTree(WORK_DIR)
    local ok, err = ensureDirectory(WORK_DIR)
    if not ok then
        return nil, err or "cannot create work dir"
    end

    local zip_path = WORK_DIR .. "/plugin.zip"
    local extract_dir = WORK_DIR .. "/extract"
    ensureDirectory(extract_dir)

    status("Downloading…")
    local body, get_err = Catalog.httpGet(url, Config.max_plugin_bytes)
    if not body then
        return nil, get_err or "download failed"
    end
    ok, err = Catalog.writeFile(zip_path, body)
    if not ok then
        return nil, err or "cannot write zip"
    end

    status("Extracting…")
    local archive = Archiver.Reader:new()
    local opened = archive:open(zip_path)
    if not opened then
        return nil, "cannot open zip"
    end
    local extracted = archive:extractToPath(extract_dir)
    archive:close()
    if not extracted then
        return nil, "extract failed"
    end

    local root = findPluginRoot(extract_dir, dirname)
    if not root then
        return nil, "plugin root (_meta.lua) not found in archive"
    end

    local dest = Installer.pluginsDir() .. "/" .. dirname
    local backup = WORK_DIR .. "/backup-" .. dirname
    if pathMode(dest) == "directory" then
        status("Backing up previous install…")
        removeTree(backup)
        ok, err = copyTree(dest, backup)
        if not ok then
            return nil, err or "backup failed"
        end
        removeTree(dest)
    end

    status("Installing…")
    ok, err = copyTree(root, dest)
    if not ok then
        if pathMode(backup) == "directory" then
            copyTree(backup, dest)
        end
        return nil, err or "install copy failed"
    end

    if pathMode(dest .. "/_meta.lua") ~= "file" or pathMode(dest .. "/main.lua") ~= "file" then
        removeTree(dest)
        if pathMode(backup) == "directory" then
            copyTree(backup, dest)
        end
        return nil, "installed files incomplete"
    end

    status("Done")
    return true
end

function Installer.uninstall(install_dirname)
    if type(install_dirname) ~= "string" or not install_dirname:match("%.koplugin$") then
        return nil, "invalid install_dirname"
    end
    if install_dirname == "komarket.koplugin" then
        return nil, "refusing to uninstall KOMarket itself"
    end
    local dest = Installer.pluginsDir() .. "/" .. install_dirname
    if pathMode(dest) ~= "directory" then
        return nil, "not installed"
    end
    return removeTree(dest)
end

return Installer
