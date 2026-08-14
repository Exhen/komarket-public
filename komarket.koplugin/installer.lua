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
        -- ffi/util.copyFile returns nil on success, error string on failure.
        local copy_err = ffiutil.copyFile(src, dst)
        if copy_err then
            return nil, copy_err
        end
        return true
    end
    if mode == "link" then
        -- Skip symlinks; plugin packages should ship real files.
        logger.warn("KOMarket install: skip symlink", src)
        return true
    end
    if mode ~= "directory" then
        return nil, "invalid source: " .. tostring(src)
    end
    local ok, err = ensureDirectory(dst)
    if not ok then
        return nil, err
    end
    for name in lfs.dir(src) do
        if name ~= "." and name ~= ".." then
            ok, err = copyTree(src .. "/" .. name, dst .. "/" .. name)
            if not ok then
                return nil, err or ("copy failed: " .. name)
            end
        end
    end
    return true
end

local function safeRelPath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    -- Reject absolute / drive / zip-slip paths.
    if path:sub(1, 1) == "/" or path:match("^%a:[/\\]") then
        return nil
    end
    path = path:gsub("\\", "/")
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == "" or part == "." then
            -- skip
        elseif part == ".." then
            return nil
        else
            parts[#parts + 1] = part
        end
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "/")
end

local function writeFile(path, data)
    local parent = parentPath(path)
    if parent then
        local ok, err = ensureDirectory(parent)
        if not ok then
            return nil, err
        end
    end
    local f, err = io.open(path, "wb")
    if not f then
        return nil, err
    end
    local ok, werr = f:write(data)
    f:close()
    if not ok then
        return nil, werr
    end
    return true
end

--- Extract whole archive into dest_dir (index entries first, then extractToMemory).
local function extractArchive(archive_path, dest_dir)
    local ok, err = removeTree(dest_dir)
    if not ok then
        return nil, err or "cannot clear extract dir"
    end
    ok, err = ensureDirectory(dest_dir)
    if not ok then
        return nil, err or "cannot create extract dir"
    end

    local archive = Archiver.Reader:new()
    if not archive:open(archive_path) then
        return nil, archive.err or "cannot open zip"
    end

    -- Index all entries before extracting (KOReader archiver cannot read twice).
    for _ in archive:iterate() do
    end
    archive:close(true)
    if not archive:open(archive_path) then
        return nil, archive.err or "cannot reopen zip"
    end

    for entry in archive:iterate() do
        local rel = safeRelPath(entry.path)
        if not rel then
            archive:close()
            removeTree(dest_dir)
            return nil, "unsafe path in archive: " .. tostring(entry.path)
        end
        local dest = dest_dir .. "/" .. rel
        if entry.mode == "directory" then
            ok, err = ensureDirectory(dest)
            if not ok then
                archive:close()
                removeTree(dest_dir)
                return nil, err or "mkdir failed"
            end
        elseif entry.mode == "link" then
            logger.warn("KOMarket install: skip symlink in archive", entry.path)
        elseif entry.mode == "file" then
            local content = archive:extractToMemory(entry.path)
            if content == nil then
                local aerr = archive.err
                archive:close()
                removeTree(dest_dir)
                return nil, aerr or "extract failed"
            end
            ok, err = writeFile(dest, content)
            if not ok then
                archive:close()
                removeTree(dest_dir)
                return nil, err or "write failed"
            end
        end
    end

    if archive.err then
        local aerr = archive.err
        archive:close()
        removeTree(dest_dir)
        return nil, aerr
    end
    archive:close()
    return true
end

local function hasPluginMarkers(dir)
    return pathMode(dir .. "/_meta.lua") == "file"
        and pathMode(dir .. "/main.lua") == "file"
end

local function findPluginRoot(extract_dir, expected_dirname)
    if hasPluginMarkers(extract_dir) then
        return extract_dir
    end

    local direct = extract_dir .. "/" .. expected_dirname
    if hasPluginMarkers(direct) then
        return direct
    end

    local function scan(dir, depth)
        if depth > 5 or pathMode(dir) ~= "directory" then
            return nil
        end
        if hasPluginMarkers(dir) then
            return dir
        end
        local preferred = dir .. "/" .. expected_dirname
        if hasPluginMarkers(preferred) then
            return preferred
        end
        for name in lfs.dir(dir) do
            if name ~= "." and name ~= ".." then
                local child = dir .. "/" .. name
                if pathMode(child) == "directory" and name:match("%.koplugin$") then
                    if hasPluginMarkers(child) then
                        return child
                    end
                end
            end
        end
        for name in lfs.dir(dir) do
            if name ~= "." and name ~= ".." then
                local child = dir .. "/" .. name
                if pathMode(child) == "directory" then
                    local found = scan(child, depth + 1)
                    if found then
                        return found
                    end
                end
            end
        end
        return nil
    end

    return scan(extract_dir, 0)
end

function Installer.pluginsDir()
    return DataStorage:getDataDir() .. "/plugins"
end

function Installer.isInstalled(install_dirname)
    return pathMode(Installer.pluginsDir() .. "/" .. install_dirname) == "directory"
end

function Installer.install(plugin, on_status, opts)
    opts = opts or {}
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
    if dirname == "komarket.koplugin" and not opts.self_update then
        return nil, "refusing to modify KOMarket without self-update flag"
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
    ok, err = extractArchive(zip_path, extract_dir)
    if not ok then
        return nil, err or "extract failed"
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
    local Updates = require("updates")
    Updates.recordInstall(plugin)
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
    local ok, err = removeTree(dest)
    if ok then
        pcall(function()
            require("updates").forgetInstall(install_dirname)
        end)
    end
    return ok, err
end

return Installer
