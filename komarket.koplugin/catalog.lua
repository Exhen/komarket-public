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

local _ = require("komarket_gettext")

local Catalog = {}

local GetText = require("gettext")

--- Resolve editorial note for display (default: English).
function Catalog.currentLang()
    return GetText.current_lang or "en"
end

function Catalog.resolveEditorialNote(note, lang)
    lang = lang or Catalog.currentLang()
    if type(note) == "string" then
        local s = note:match("^%s*(.-)%s*$") or ""
        if s == "" then
            return ""
        end
        if lang:match("^zh") then
            return s
        end
        return ""
    end
    if type(note) == "table" then
        local en = tostring(note.en or ""):match("^%s*(.-)%s*$") or ""
        local zh = tostring(note.zh or note.zh_CN or ""):match("^%s*(.-)%s*$") or ""
        if lang:match("^zh") then
            return zh ~= "" and zh or en
        end
        return en ~= "" and en or zh
    end
    return ""
end

local CACHE_DIR = DataStorage:getDataDir() .. "/cache/komarket"
local CACHE_FILE = CACHE_DIR .. "/index.json"
local CATEGORIES_CACHE_FILE = CACHE_DIR .. "/categories.json"

local DEFAULT_CATEGORIES = {
    { id = "beautify", name = _("Beautify") },
    { id = "sync", name = _("Sync") },
    { id = "download", name = _("Download") },
    { id = "bookstore", name = _("Bookstore") },
    { id = "llm", name = "LLM" },
    { id = "rss", name = "RSS" },
    { id = "ime", name = _("Input method") },
    { id = "remote", name = _("Remote control") },
    { id = "comic", name = _("Comics") },
    { id = "other", name = _("Other") },
}
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

local TRANSIENT_HTTP_ERRORS = {
    "cannot assign requested address",
    "timeout",
    "connection refused",
    "network is unreachable",
}

local function isTransientError(err)
    if type(err) ~= "string" then
        return false
    end
    local lower = string.lower(err)
    for _, pat in ipairs(TRANSIENT_HTTP_ERRORS) do
        if lower:find(pat, 1, true) then
            return true
        end
    end
    return false
end

local function preferIPv4Url(url)
    local parsed = socketurl.parse(url)
    if not parsed or not parsed.host or parsed.host == "" then
        return url, nil
    end
    local host = parsed.host
    if host:match("^[%d%.]+$") or host:match("^%[.+%]$") then
        return url, nil
    end
    local scheme = (parsed.scheme or "http"):lower()
    -- HTTPS: keep the hostname so LuaSec can send SNI. Rewriting to an IP
    -- makes Cloudflare/etc. fail with "sslv3 alert handshake failure".
    if scheme == "https" then
        return url, nil
    end
    local ok, ip = pcall(socket.dns.toip, host, { family = "inet" })
    if not ok or not ip or ip == "" then
        return url, nil
    end
    local path = parsed.path or "/"
    if parsed.params and parsed.params ~= "" then
        path = path .. ";" .. parsed.params
    end
    if parsed.query and parsed.query ~= "" then
        path = path .. "?" .. parsed.query
    end
    if parsed.fragment and parsed.fragment ~= "" then
        path = path .. "#" .. parsed.fragment
    end
    local port = parsed.port
    local ip_url
    if port then
        ip_url = string.format("%s://%s:%s%s", scheme, ip, port, path)
    else
        ip_url = string.format("%s://%s%s", scheme, ip, path)
    end
    return ip_url, { Host = host }
end

local function httpGetOnce(url, max_bytes)
    local current = url
    for _ = 0, MAX_REDIRECTS do
        local request_url, extra_headers = preferIPv4Url(current)
        local chunks = {}
        local total = 0
        local sink_error

        socketutil:set_timeout(Config.connect_timeout_s, Config.request_timeout_s)
        local headers = {
            ["User-Agent"] = Config.user_agent or socketutil.USER_AGENT,
            ["Accept"] = "application/json,text/plain,*/*",
            ["Connection"] = "close",
        }
        if extra_headers then
            for k, v in pairs(extra_headers) do
                headers[k] = v
            end
        end
        -- socket.skip(1, http.request(...)) => code, headers, status
        local code, resp_headers, status = socket.skip(1, http.request({
            url = request_url,
            method = "GET",
            headers = headers,
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
            return table.concat(chunks), resp_headers
        end
        if isRedirect(numeric) then
            local loc = resp_headers and (resp_headers.location or resp_headers.Location)
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

local function httpGet(url, max_bytes)
    local retries = Config.http_retries or 3
    local delay_s = Config.http_retry_delay_s or 1
    local last_err
    for attempt = 1, retries do
        local body, headers_or_err = httpGetOnce(url, max_bytes)
        if body then
            return body, headers_or_err
        end
        last_err = headers_or_err
        if attempt < retries and isTransientError(last_err) then
            logger.info("KOMarket: transient HTTP error, retry", attempt, last_err)
            socket.sleep(delay_s)
        else
            break
        end
    end
    return nil, last_err
end

function Catalog.catalogUrls()
    local urls = {}
    if Config.catalog_url and Config.catalog_url ~= "" then
        urls[#urls + 1] = Config.catalog_url
    end
    if Config.mirror_catalog_url and Config.mirror_catalog_url ~= "" then
        urls[#urls + 1] = Config.mirror_catalog_url
    end
    return urls
end

function Catalog.fetchIndex(opts)
    opts = opts or {}
    local last_err
    local urls = Catalog.catalogUrls()
    local url_delay_s = Config.http_retry_delay_s or 1
    for i, url in ipairs(urls) do
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
        if i < #urls then
            socket.sleep(url_delay_s)
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

function Catalog.categoriesUrls()
    local seen = {}
    local urls = {}
    local function add(url)
        if url and url ~= "" and not seen[url] then
            seen[url] = true
            urls[#urls + 1] = url
        end
    end
    add(Config.categories_url)
    add(Config.mirror_categories_url)
    -- Derive from catalog URL when explicit categories URLs are not set
    if not Config.categories_url or Config.categories_url == "" then
        for _, catalog_url in ipairs(Catalog.catalogUrls()) do
            add(catalog_url:gsub("index%.json$", "categories.json"))
        end
    end
    return urls
end

function Catalog.loadCachedCategories()
    local raw = readFile(CATEGORIES_CACHE_FILE)
    if raw and raw ~= "" then
        local ok, data = pcall(JSON.decode, raw)
        if ok and type(data) == "table" and type(data.categories) == "table" then
            return data.categories
        end
    end
    return DEFAULT_CATEGORIES
end

function Catalog.fetchCategories()
    local last_err
    local urls = Catalog.categoriesUrls()
    local url_delay_s = Config.http_retry_delay_s or 1
    for i, url in ipairs(urls) do
        local body, err = httpGet(url, 256 * 1024)
        if body then
            local ok, data = pcall(JSON.decode, body)
            if ok and type(data) == "table" and type(data.categories) == "table" then
                writeFile(CATEGORIES_CACHE_FILE, body)
                return data.categories, url
            end
            last_err = "invalid categories JSON"
        else
            last_err = err
        end
        if i < #urls then
            socket.sleep(url_delay_s)
        end
    end
    return Catalog.loadCachedCategories(), last_err and ("fallback:" .. tostring(last_err)) or "builtin"
end

function Catalog.resolveCategoryName(cat, lang)
    lang = lang or Catalog.currentLang()
    if type(cat) ~= "table" then
        return tostring(cat or "")
    end
    local name = cat.name
    if type(name) == "string" then
        local legacy_en = tostring(cat.name_en or "")
        if lang:match("^zh") then
            return name
        end
        if legacy_en ~= "" and legacy_en ~= name then
            return legacy_en
        end
        return name
    end
    if type(name) == "table" then
        local en = tostring(name.en or ""):match("^%s*(.-)%s*$") or ""
        local zh = tostring(name.zh or name.zh_CN or ""):match("^%s*(.-)%s*$") or ""
        if lang:match("^zh") then
            return zh ~= "" and zh or en
        end
        return en ~= "" and en or zh
    end
    return tostring(cat.id or "")
end

function Catalog.categoryName(categories, id)
    for _, c in ipairs(categories or DEFAULT_CATEGORIES) do
        if c.id == id then
            return Catalog.resolveCategoryName(c)
        end
    end
    return id
end

function Catalog.filterByCategory(plugins, category_id)
    if not category_id or category_id == "" or category_id == "all" then
        return plugins
    end
    local out = {}
    for _, p in ipairs(plugins or {}) do
        local cats = p.categories or {}
        for _, cid in ipairs(cats) do
            if cid == category_id then
                out[#out + 1] = p
                break
            end
        end
    end
    return out
end

function Catalog.filterPlugins(plugins, query, category_id)
    local list = Catalog.filterByCategory(plugins, category_id)
    if not query or query == "" then
        return list
    end
    query = string.lower(query)
    local out = {}
    for _, p in ipairs(list or {}) do
        local hay = table.concat({
            tostring(p.name or ""),
            tostring(p.summary or ""),
            tostring(Catalog.resolveEditorialNote(p.editorial_note) or ""),
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
Catalog.httpGetOnce = httpGetOnce
Catalog.preferIPv4Url = preferIPv4Url
Catalog.isTransientHttpError = isTransientError
Catalog.writeFile = writeFile
Catalog.readFile = readFile

return Catalog
