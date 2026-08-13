--[[--
HTTP helpers and catalog fetch for KOMarket.
]]

local DataStorage = require("datastorage")
local JSON = require("json")
local http = require("socket.http")
local socket = require("socket")
local socketurl = require("socket.url")
local socketutil = require("socketutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Config = require("config")

-- Ensure LuaSec is loaded so https:// URLs work via LuaSocket scheme handling.
pcall(require, "ssl.https")

local Catalog = {}

local CACHE_DIR = DataStorage:getDataDir() .. "/cache/komarket"
local CACHE_FILE = CACHE_DIR .. "/index.json"
local MAX_REDIRECTS = 5

local function ensureCacheDir()
    local attr = lfs.attributes(CACHE_DIR)
    if attr and attr.mode == "directory" then
        return true
    end
    local parent = DataStorage:getDataDir() .. "/cache"
    if not lfs.attributes(parent) then
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

function Catalog.getCachePath()
    return CACHE_FILE
end

function Catalog.loadCached()
    local raw = readFile(CACHE_FILE)
    if not raw or raw == "" then
        return nil
    end
    local ok, data = pcall(JSON.decode, raw)
    if not ok or type(data) ~= "table" then
        return nil
    end
    return data
end

local function isRedirect(code)
    code = tonumber(code)
    return code == 301 or code == 302 or code == 303 or code == 307 or code == 308
end

local function httpGet(url, max_bytes)
    local current = url
    for _ = 0, MAX_REDIRECTS do
        local chunks = {}
        local total = 0
        local sink_error

        socketutil:set_timeout(Config.connect_timeout_s, Config.request_timeout_s)
        -- socket.skip(1, http.request(...)) => code, headers, status
        local code, headers, status = socket.skip(1, http.request({
            url = current,
            method = "GET",
            headers = {
                ["User-Agent"] = Config.user_agent or socketutil.USER_AGENT,
                ["Accept"] = "application/json,text/plain,*/*",
                ["Connection"] = "close",
            },
            sink = function(chunk, err_msg)
                if err_msg then
                    sink_error = err_msg
                    return nil, err_msg
                end
                if chunk then
                    total = total + #chunk
                    if total > max_bytes then
                        sink_error = "response too large"
                        return nil, sink_error
                    end
                    chunks[#chunks + 1] = chunk
                end
                return 1
            end,
            redirect = false,
        }))
        socketutil:reset_timeout()

        if sink_error then
            return nil, sink_error
        end
        if not code then
            return nil, status or "request failed"
        end

        local numeric = tonumber(code) or 0
        if numeric >= 200 and numeric < 300 then
            return table.concat(chunks), headers
        end
        if isRedirect(numeric) then
            local loc = headers and (headers.location or headers.Location)
            if not loc then
                return nil, "redirect without Location"
            end
            current = socketurl.absolute(current, loc)
            logger.info("KOMarket: redirect", numeric, "->", current)
        else
            return nil, status or ("HTTP " .. tostring(code))
        end
    end
    return nil, "too many redirects"
end

function Catalog.catalogUrls()
    local urls = {}
    if Config.mirror_catalog_url and Config.mirror_catalog_url ~= "" then
        urls[#urls + 1] = Config.mirror_catalog_url
    end
    if Config.catalog_url and Config.catalog_url ~= "" then
        urls[#urls + 1] = Config.catalog_url
    end
    return urls
end

function Catalog.fetchIndex(opts)
    opts = opts or {}
    local last_err
    for _, url in ipairs(Catalog.catalogUrls()) do
        logger.info("KOMarket: fetching catalog", url)
        local body, err = httpGet(url, Config.max_catalog_bytes)
        if body then
            local ok, data = pcall(JSON.decode, body)
            if ok and type(data) == "table" and type(data.plugins) == "table" then
                writeFile(CACHE_FILE, body)
                return data, url
            end
            last_err = "invalid catalog JSON"
        else
            last_err = err
        end
    end

    if not opts.skip_cache then
        local cached = Catalog.loadCached()
        if cached then
            return cached, "cache"
        end
    end
    return nil, last_err or "no catalog url configured"
end

function Catalog.filterPlugins(plugins, query)
    if not query or query == "" then
        return plugins
    end
    query = string.lower(query)
    local out = {}
    for _, p in ipairs(plugins or {}) do
        local hay = table.concat({
            tostring(p.name or ""),
            tostring(p.summary or ""),
            tostring(p.owner or ""),
            tostring(p.repo or ""),
            table.concat(p.topics or {}, " "),
            table.concat(p.categories or {}, " "),
        }, " "):lower()
        if hay:find(query, 1, true) then
            out[#out + 1] = p
        end
    end
    return out
end

function Catalog.isDownloadUrlAllowed(url)
    if type(url) ~= "string" or url == "" then
        return false
    end
    local host = url:match("^https?://([^/]+)")
    if not host then
        return false
    end
    host = host:lower()
    for _, suffix in ipairs(Config.allowed_download_hosts or {}) do
        suffix = suffix:lower()
        if host == suffix or host:sub(-(#suffix + 1)) == "." .. suffix then
            return true
        end
    end
    return false
end

Catalog.httpGet = httpGet
Catalog.writeFile = writeFile
Catalog.readFile = readFile

return Catalog
