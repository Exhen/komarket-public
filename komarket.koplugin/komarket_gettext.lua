--[[--
Plugin-local gettext: English source strings + l10n/*.lua translations.
]]

local GetText = require("gettext")
local logger = require("logger")

local function thisDir()
    local source = debug.getinfo(1, "S").source
    return source:match("^@(.*)[/\\][^/\\]+$")
end

local function loadLangTable(lang)
    if not lang or lang == "" or lang == "C" or lang:match("^en") then
        return nil
    end
    local dir = thisDir()
    if not dir then
        return nil
    end

    local function tryCode(code)
        local path = dir .. "/l10n/" .. code .. ".lua"
        local chunk = loadfile(path)
        if not chunk then
            return nil
        end
        local ok, tbl = pcall(chunk)
        if ok and type(tbl) == "table" then
            return tbl
        end
        logger.warn("komarket_gettext: failed to load", path, tbl)
        return nil
    end

    local tbl = tryCode(lang)
    if not tbl then
        local base = lang:match("^(%a%a)")
        if base and base ~= lang then
            tbl = tryCode(base)
        end
    end
    if not tbl and lang:match("^zh") then
        tbl = tryCode("zh_CN")
    end
    return tbl
end

local translation = loadLangTable(GetText.current_lang) or {}

local KOMarketGetText = setmetatable({}, {
    __call = function(_self, msgid)
        return translation[msgid] or GetText(msgid)
    end,
    __index = GetText,
})

return KOMarketGetText
