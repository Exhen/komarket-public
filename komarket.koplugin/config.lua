--[[--
KOMarket plugin defaults.

Connection mode (github / mirror / custom) is chosen in Settings and persisted
via settings.lua. Version string lives in _version.lua.
]]

local VERSION = require("_version")

local GITHUB_RAW = "https://raw.githubusercontent.com/Exhen/komarket-public/main"
local OSS_BASE = "https://oss.ko.6ili6ili.com"

local Config = {
    -- Default when the user has never opened Settings.
    default_connection_mode = "mirror",

    -- GitHub: catalog JSON + release zips from GitHub.
    github_catalog_url = GITHUB_RAW .. "/catalog/index.json",
    github_categories_url = GITHUB_RAW .. "/catalog/categories.json",

    -- Mirror: OSS catalog JSON + OSS release zips.
    mirror_catalog_url = OSS_BASE .. "/catalog/index.json",
    mirror_categories_url = OSS_BASE .. "/catalog/categories.json",

    -- Allowlist host suffixes for download_url (plus custom catalog host when in custom mode).
    allowed_download_hosts = {
        "oss.ko.6ili6ili.com",
        "aliyuncs.com",
        "github.com",
        "githubusercontent.com",
        "objects.githubusercontent.com",
        "codeload.github.com",
    },
    -- Self-update via GitHub Releases API only.
    self_release_api = "https://api.github.com/repos/Exhen/komarket-public/releases/latest",
    self_install_dirname = "komarket.koplugin",
    -- Plugin-list share API (9-digit codes on KOMarket server).
    share_api_base = "https://ko.6ili6ili.com/api/share",
    share_code_length = 9,
    share_max_plugins = 64,
    user_agent = "KOMarket/" .. VERSION .. " (KOReader)",
    connect_timeout_s = 15,
    request_timeout_s = 60,
    http_retries = 3,
    http_retry_delay_s = 1,
    max_catalog_bytes = 4 * 1024 * 1024,
    max_plugin_bytes = 32 * 1024 * 1024,
}

return Config
