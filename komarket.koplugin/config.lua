--[[--
KOMarket plugin defaults.

catalog_url points at the public komarket-public catalog on GitHub.
Version string lives in _version.lua (keep in sync with GitHub release tag).
]]

local VERSION = require("_version")

local Config = {
    -- Primary catalog (public repo JSON on GitHub).
    catalog_url = "https://raw.githubusercontent.com/Exhen/komarket-public/main/catalog/index.json",
    categories_url = "https://raw.githubusercontent.com/Exhen/komarket-public/main/catalog/categories.json",
    -- Optional mirror (disabled; use GitHub raw URLs).
    mirror_catalog_url = nil,
    mirror_categories_url = nil,
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
    user_agent = "KOMarket/" .. VERSION .. " (KOReader)",
    connect_timeout_s = 15,
    request_timeout_s = 60,
    max_catalog_bytes = 4 * 1024 * 1024,
    max_plugin_bytes = 32 * 1024 * 1024,
}

return Config
