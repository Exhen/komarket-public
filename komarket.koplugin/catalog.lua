--[[--
HTTP helpers and catalog fetch for KOMarket.
]]

local DataStorage = require("datastorage")
local JSON = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Config = require("config")

local Catalog = {}

local CACHE_DIR = DataStorage:getDataDir() .. "/cache/komarket"
local CACHE_FILE = CACHE_DIR .. "/index.json"

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

local function httpGet(url, max_bytes)
    local chunks = {}
    local total = 0
    local size_ok = true

    socketutil:set_timeout(Config.connect_timeout_s, Config.request_timeout_s)
    local request = {
        url = url,
        method = "GET",
        headers = {
            ["User-Agent"] = Config.user_agent,
            ["Accept"] = "application/json",
        },
        sink = ltn12.sink.simplify(function(chunk, err_msg)
            if err_msg then
                return nil, err_msg
            end
            if chunk then
                total = total + #chunk
                if total > max_bytes then
                    size_ok = false
                    return nil, "response too large"
                end
                chunks[#chunks + 1] = chunk
            end
            return true
        end),
        redirect = true,
    }

    local ok, code, headers = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    if not size_ok then
        return nil, "response too large"
    end
    if not ok then
        return nil, tostring(code or "request failed")
    end
    local status = tonumber(code) or 0
    if status < 200 or status >= 300 then
        return nil, "HTTP " .. tostring(code)
    end
    return table.concat(chunks), headers
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
