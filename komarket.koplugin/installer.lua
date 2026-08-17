--[[--
Download and install a plugin zip into KOReader plugins/, and/or user
patches (numbered N-*.lua) into patches/.
]]

local Archiver = require("ffi/archiver")
local DataStorage = require("datastorage")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local sha2 = require("ffi/sha2")
local Catalog = require("catalog")
local Config = require("config")
local _ = require("komarket_gettext")

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

-- KOReader user patches: numbered Lua files, e.g. 2-foo.lua (see userpatch.lua).
local PATCH_FILENAME = "^%d+%-.+%.lua$"

local function isPatchFilename(name)
    return type(name) == "string" and name:match(PATCH_FILENAME) ~= nil
end

--- Numbered patch Lua files that are not inside a real *.koplugin package.
local function findPatchFiles(extract_dir)
    local files = {}
    local function scan(dir, skip, depth)
        if depth > 6 or pathMode(dir) ~= "directory" then
            return
        end
        for name in lfs.dir(dir) do
            if name ~= "." and name ~= ".." then
                local child = dir .. "/" .. name
                local mode = pathMode(child)
                if mode == "directory" then
                    local skip_children = skip
                        or (name:match("%.koplugin$") and hasPluginMarkers(child))
                    scan(child, skip_children, depth + 1)
                elseif not skip and mode == "file" and isPatchFilename(name) then
                    files[#files + 1] = { src = child, name = name }
                end
            end
        end
    end
    scan(extract_dir, hasPluginMarkers(extract_dir), 0)
    return files
end

local function isSafeDirname(dirname)
    return type(dirname) == "string"
        and dirname ~= ""
        and not dirname:find("[/\\]")
        and not dirname:match("%.%.")
end

function Installer.pluginsDir()
    return DataStorage:getDataDir() .. "/plugins"
end

function Installer.patchesDir()
    return DataStorage:getDataDir() .. "/patches"
end

function Installer.patchFileInstalled(filename)
    if not isPatchFilename(filename) then
        return false
    end
    local dir = Installer.patchesDir()
    return pathMode(dir .. "/" .. filename) == "file"
        or pathMode(dir .. "/" .. filename .. ".disabled") == "file"
end

function Installer.isInstalled(plugin_or_dirname)
    local dirname
    if type(plugin_or_dirname) == "table" then
        dirname = plugin_or_dirname.install_dirname
    else
        dirname = plugin_or_dirname
    end
    if not isSafeDirname(dirname) then
        return false
    end
    if pathMode(Installer.pluginsDir() .. "/" .. dirname) == "directory" then
        return true
    end
    local ok, Updates = pcall(require, "updates")
    if not ok or not Updates.loadRegistry then
        return false
    end
    local rec = Updates.loadRegistry()[dirname]
    if type(rec) ~= "table" or type(rec.patch_files) ~= "table" then
        return false
    end
    for _, name in ipairs(rec.patch_files) do
        if Installer.patchFileInstalled(name) then
            return true
        end
    end
    return false
end

--- Normalize catalog / GitHub digest to lowercase 64-char hex, or nil.
function Installer.normalizeSha256(value)
    if type(value) ~= "string" then
        return nil
    end
    local s = value:match("^%s*(.-)%s*$") or ""
    s = s:lower()
    local hex = s:match("^sha256:(%x+)$") or s:match("^(%x+)$")
    if hex and #hex == 64 then
        return hex
    end
    return nil
end

function Installer.expectedSha256(plugin)
    if type(plugin) ~= "table" then
        return nil
    end
    return Installer.normalizeSha256(plugin.sha256)
end

function Installer.verifySha256(body, expected_hex)
    expected_hex = Installer.normalizeSha256(expected_hex)
    if not expected_hex then
        return nil, _("missing sha256 in catalog")
    end
    if type(body) ~= "string" then
        return nil, _("sha256 verification failed")
    end
    local actual = sha2.sha256(body)
    if actual ~= expected_hex then
        logger.warn("KOMarket install: sha256 mismatch expected", expected_hex, "got", actual)
        return nil, _("sha256 mismatch")
    end
    return true
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
    local urls = Catalog.downloadCandidates(plugin)
    local expected_sha = Installer.expectedSha256(plugin)
    if not isSafeDirname(dirname) then
        return nil, "invalid install_dirname"
    end
    if dirname == "komarket.koplugin" and not opts.self_update then
        return nil, "refusing to modify KOMarket without self-update flag"
    end
    if #urls == 0 then
        return nil, "download host not allowed"
    end
    if not expected_sha then
        return nil, _("missing sha256 in catalog")
    end

    removeTree(WORK_DIR)
    local ok, err = ensureDirectory(WORK_DIR)
    if not ok then
        return nil, err or "cannot create work dir"
    end

    local zip_path = WORK_DIR .. "/plugin.zip"
    local extract_dir = WORK_DIR .. "/extract"
    ensureDirectory(extract_dir)

    local body
    local last_err
    for i, url in ipairs(urls) do
        if i == 1 then
            status("Downloading…")
        else
            status(_("OSS package missing, falling back to GitHub…"))
            logger.info("KOMarket install: fallback download", url, "after", tostring(last_err))
        end
        body, last_err = Catalog.httpGet(url, Config.max_plugin_bytes)
        if body then
            status(_("Verifying SHA-256…"))
            ok, err = Installer.verifySha256(body, expected_sha)
            if ok then
                last_err = nil
                break
            end
            body = nil
            last_err = err
            logger.warn("KOMarket install: sha256 failed for", url, err)
        end
    end
    if not body then
        return nil, last_err or "download failed"
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
    local patch_files = findPatchFiles(extract_dir)
    if not root and #patch_files == 0 then
        return nil, "plugin or patch files not found in archive"
    end
    if root and not dirname:match("%.koplugin$") then
        return nil, "invalid install_dirname"
    end

    local dest, backup
    if root then
        dest = Installer.pluginsDir() .. "/" .. dirname
        backup = WORK_DIR .. "/backup-" .. dirname
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
    end

    local installed_patches = {}
    if #patch_files > 0 then
        status(_("Installing patches…"))
        ok, err = ensureDirectory(Installer.patchesDir())
        if not ok then
            if dest and pathMode(backup) == "directory" then
                removeTree(dest)
                copyTree(backup, dest)
            end
            return nil, err or "cannot create patches dir"
        end
        for _, item in ipairs(patch_files) do
            local patch_dest = Installer.patchesDir() .. "/" .. item.name
            os.remove(patch_dest)
            os.remove(patch_dest .. ".disabled")
            ok, err = copyTree(item.src, patch_dest)
            if not ok then
                return nil, err or ("patch copy failed: " .. item.name)
            end
            installed_patches[#installed_patches + 1] = item.name
        end
    end

    status("Done")
    plugin._patch_files = installed_patches
    local Updates = require("updates")
    Updates.recordInstall(plugin)
    plugin._patch_files = nil
    return true
end

function Installer.uninstall(plugin_or_dirname)
    local dirname
    if type(plugin_or_dirname) == "table" then
        dirname = plugin_or_dirname.install_dirname
    else
        dirname = plugin_or_dirname
    end
    if not isSafeDirname(dirname) then
        return nil, "invalid install_dirname"
    end
    if dirname == "komarket.koplugin" then
        return nil, "refusing to uninstall KOMarket itself"
    end

    local removed = false
    local dest = Installer.pluginsDir() .. "/" .. dirname
    if pathMode(dest) == "directory" then
        local ok, err = removeTree(dest)
        if not ok then
            return nil, err
        end
        removed = true
    end

    local Updates = require("updates")
    local rec = Updates.loadRegistry()[dirname]
    if type(rec) == "table" and type(rec.patch_files) == "table" then
        for _, name in ipairs(rec.patch_files) do
            if isPatchFilename(name) then
                os.remove(Installer.patchesDir() .. "/" .. name)
                os.remove(Installer.patchesDir() .. "/" .. name .. ".disabled")
                removed = true
            end
        end
    end

    if not removed then
        return nil, "not installed"
    end
    pcall(function()
        Updates.forgetInstall(dirname)
    end)
    return true
end

return Installer
