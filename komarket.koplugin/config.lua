--[[--
KOMarket plugin defaults.

catalog_url points at the public komarket-public catalog.
mirror_catalog_url: optional KOMarket server mirror (faster / more reliable).
]]

local Config = {
    -- Primary catalog (public repo JSON).
    catalog_url = "https://raw.githubusercontent.com/Exhen/komarket-public/main/catalog/index.json",
    -- Optional mirror served by private KOMarket web server.
    mirror_catalog_url = nil,
    -- Allowlist host suffixes for download_url.
    allowed_download_hosts = {
        "github.com",
        "githubusercontent.com",
        "codeload.github.com",
    },
    user_agent = "KOMarket/0.1.0 (KOReader)",
    connect_timeout_s = 15,
    request_timeout_s = 60,
    max_catalog_bytes = 4 * 1024 * 1024,
    max_plugin_bytes = 32 * 1024 * 1024,
}

return Config
