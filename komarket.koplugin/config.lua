--[[--
KOMarket plugin defaults.

catalog_url points at the KOMarket server mirror (ko.6ili6ili.com); GitHub raw is fallback.
Version string lives in _version.lua (keep in sync with GitHub release tag).
]]

local VERSION = require("_version")

local GITHUB_RAW = "https://raw.githubusercontent.com/Exhen/komarket-public/main"

local Config = {
    -- Primary catalog (KOMarket server mirror; better reachability in China).
    catalog_url = "https://ko.6ili6ili.com/catalog/index.json",
    categories_url = "https://ko.6ili6ili.com/catalog/categories.json",
    -- Fallback mirror (GitHub raw).
    mirror_catalog_url = GITHUB_RAW .. "/catalog/index.json",
    mirror_categories_url = GITHUB_RAW .. "/catalog/categories.json",
    -- Allowlist host suffixes for download_url.
    allowed_download_hosts = {
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
