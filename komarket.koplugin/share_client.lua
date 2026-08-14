--[[--
HTTP client for KOMarket plugin-list share API.
]]

local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketurl = require("socket.url")
local socketutil = require("socketutil")
local JSON = require("json")
local logger = require("logger")
local Config = require("config")

pcall(require, "ssl.https")

local ShareClient = {}

local MAX_REDIRECTS = 5

local function apiBase()
    return (Config.share_api_base or "https://ko.6ili6ili.com/api/share"):gsub("/$", "")
end

local function isRedirect(code)
    code = tonumber(code)
    return code == 301 or code == 302 or code == 303 or code == 307 or code == 308
end

local function normalizeCode(code)
    if type(code) ~= "string" then
        return nil
    end
    code = code:gsub("%s+", "")
    local len = Config.share_code_length or 9
    if not code:match("^%d+$") or #code ~= len then
        return nil
    end
    return code
end

function ShareClient.normalizeCode(code)
    return normalizeCode(code)
end

local function parseApiError(body)
    if type(body) ~= "string" or body == "" then
        return nil
    end
    local ok, data = pcall(JSON.decode, body)
    if ok and type(data) == "table" and type(data.error) == "string" and data.error ~= "" then
        return data.error
    end
    return nil
end

local function friendlyError(err)
    if type(err) ~= "string" then
        return tostring(err or "unknown error")
    end
    local lower = string.lower(err)
    if lower:find("zip", 1, true) then
        return "share API outdated (server expects zip; update KOMarket server for plugin-list shares)"
    end
    return err
end

local function request(method, url, opts)
    opts = opts or {}
    local current = url
    for _ = 0, MAX_REDIRECTS do
        local resp_body = {}

        socketutil:set_timeout(Config.connect_timeout_s, Config.request_timeout_s)
        local request_opts = {
            url = current,
            method = method,
            headers = {
                ["User-Agent"] = Config.user_agent or socketutil.USER_AGENT,
                ["Accept"] = opts.accept or "application/json,*/*",
                ["Connection"] = "close",
            },
            sink = ltn12.sink.table(resp_body),
            redirect = false,
        }

        for k, v in pairs(opts.headers or {}) do
            request_opts.headers[k] = v
        end

        if opts.body then
            request_opts.headers["Content-Length"] = tostring(#opts.body)
            request_opts.source = ltn12.source.string(opts.body)
        end

        local code, headers, status = socket.skip(1, http.request(request_opts))
        socketutil:reset_timeout()

        if not code then
            return nil, status or "request failed"
        end

        local numeric = tonumber(code) or 0
        local body = table.concat(resp_body)

        if numeric >= 200 and numeric < 300 then
            return numeric, body, headers
        end
        if isRedirect(numeric) then
            local loc = headers and (headers.location or headers.Location)
            if not loc then
                return nil, "redirect without Location"
            end
            current = socketurl.absolute(current, loc)
        else
            return nil, body ~= "" and body or (status or ("HTTP " .. tostring(code)))
        end
    end
    return nil, "too many redirects"
end

function ShareClient.uploadPluginList(payload, label)
    if type(payload) ~= "table" then
        return nil, "invalid payload"
    end
    if payload.kind ~= "plugin_list" then
        return nil, "invalid payload kind"
    end
    local body = JSON.encode(payload)
    if #body == 0 then
        return nil, "empty payload"
    end

    local headers = {
        ["Content-Type"] = "application/json; charset=utf-8",
    }
    if label and label ~= "" then
        headers["X-Share-Label"] = label
    end

    local url = apiBase() .. "/config"
    logger.info("KOMarket share upload", url, #body, "bytes")
    local numeric, resp_body = request("POST", url, {
        body = body,
        headers = headers,
        accept = "application/json",
    })
    if not numeric then
        return nil, friendlyError(parseApiError(resp_body) or resp_body or "upload failed")
    end

    local ok, data = pcall(JSON.decode, resp_body)
    if not ok or type(data) ~= "table" or not data.ok then
        return nil, "invalid upload response"
    end
    return data
end

function ShareClient.fetchMeta(code)
    code = normalizeCode(code)
    if not code then
        return nil, "invalid share code"
    end
    local url = apiBase() .. "/config/" .. code
    local numeric, body = request("GET", url, { accept = "application/json" })
    if not numeric then
        return nil, friendlyError(parseApiError(body) or body or "not found")
    end
    local ok, data = pcall(JSON.decode, body)
    if not ok or type(data) ~= "table" or not data.ok then
        return nil, "invalid meta response"
    end
    if type(data.plugins) ~= "table" then
        return nil, "share code has no plugin list"
    end
    if data.kind and data.kind ~= "plugin_list" then
        return nil, "unsupported share kind (legacy config pack)"
    end
    return data
end

function ShareClient.formatCode(code)
    code = normalizeCode(code)
    if not code then
        return code
    end
    if #code == 9 then
        return code:sub(1, 3) .. " " .. code:sub(4, 6) .. " " .. code:sub(7, 9)
    end
    return code
end

return ShareClient
