--[[--
KOMarket — browse / search / install community koplugins.
]]

local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local ProgressbarDialog = require("ui/widget/progressbardialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local socket = require("socket")
local Config = require("config")
local _ = require("komarket_gettext")
local T = require("ffi/util").template

local Catalog = require("catalog")
local Installer = require("installer")
local Updates = require("updates")
local SharePack = require("share_pack")
local ShareClient = require("share_client")
local ShareImport = require("share_import")

local Screen = Device.screen
local MENU_ICON_SIZE = Screen:scaleBySize(24)
local MENU_STATE_W = MENU_ICON_SIZE + Screen:scaleBySize(8)

local function menuIcon(name)
    return IconWidget:new{
        icon = name,
        width = MENU_ICON_SIZE,
        height = MENU_ICON_SIZE,
    }
end

local KOMarket = WidgetContainer:extend{
    name = "komarket",
    is_doc_only = false,
}

function KOMarket:init()
    self.ui.menu:registerToMainMenu(self)
    self._catalog = Catalog.loadCached()
    self._categories = Catalog.loadCachedCategories()
    self._filter_category = "all"
    self._filter_query = nil
end

function KOMarket:addToMainMenu(menu_items)
    menu_items.komarket = {
        text = _("KOMarket"),
        sorting_hint = "setting",
        callback = function()
            self:openMarket()
        end,
    }
end

function KOMarket:notify(text)
    UIManager:show(InfoMessage:new{ text = text, timeout = 3 })
end

--- Installed version from disk (_version.lua), not require() cache.
function KOMarket:selfVersion()
    return Updates.localSelfVersion() or "?"
end

function KOMarket:withNetwork(callback)
    NetworkMgr:runWhenOnline(function()
        callback()
    end)
end

function KOMarket:openMarket()
    self:withNetwork(function()
        self:showBrowser()
        self:refreshCatalog({
            loading_dialog = true,
            refresh_browser = true,
        })
    end)
end

function KOMarket:refreshCatalog(opts, callback)
    if type(opts) == "function" then
        callback = opts
        opts = {}
    end
    opts = opts or {}

    local busy
    local function closeBusy()
        if busy then
            UIManager:close(busy)
            busy = nil
        end
    end

    if opts.loading_dialog then
        busy = InfoMessage:new{
            text = opts.loading_text or _("Refreshing plugin catalog…"),
            force_show = true,
        }
        UIManager:show(busy)
        UIManager:forceRePaint()
    elseif opts.toast then
        UIManager:show(InfoMessage:new{
            text = _("Refreshing plugin catalog…"),
            timeout = 2,
        })
    end

    local data, src_or_err = Catalog.fetchIndex()
    closeBusy()

    if not data then
        self:notify(T(_("Failed to refresh: %1"), tostring(src_or_err)))
        if callback then
            callback(false)
        end
        return
    end
    self._catalog = data
    -- Brief pause between catalog and categories fetch to reduce ephemeral port pressure.
    socket.sleep(Config.http_retry_delay_s or 1)
    local cats, cat_src = Catalog.fetchCategories()
    self._categories = cats or Catalog.loadCachedCategories()
    logger.info("KOMarket: catalog ready from", src_or_err, "count", #(data.plugins or {}))
    logger.info("KOMarket: categories from", cat_src, "count", #(self._categories or {}))
    if opts.refresh_browser then
        self:showBrowser()
    end
    if callback then
        callback(true)
    end
end

function KOMarket:categoryLabel(id)
    if not id or id == "all" then
        return _("All")
    end
    return Catalog.categoryName(self._categories, id)
end

function KOMarket:formatCategoryTags(plugin)
    local cats = plugin.categories or {}
    if #cats == 0 then
        return ""
    end
    local names = {}
    for i, cid in ipairs(cats) do
        names[#names + 1] = self:categoryLabel(cid)
    end
    return table.concat(names, "/")
end

function KOMarket:closeBrowser()
    if self._browser_menu then
        UIManager:close(self._browser_menu)
        self._browser_menu = nil
    end
end

function KOMarket:showBrowser(filter_query, category_id)
    if filter_query ~= nil then
        self._filter_query = filter_query
        if filter_query == "" then
            self._filter_query = nil
        end
    end
    if category_id ~= nil then
        self._filter_category = category_id
    end

    local catalog = self._catalog or Catalog.loadCached()
    if not catalog or type(catalog.plugins) ~= "table" then
        catalog = { plugins = {} }
    end

    local q = self._filter_query
    local cat = self._filter_category or "all"
    local plugins = Catalog.filterPlugins(catalog.plugins, q, cat)
    table.sort(plugins, function(a, b)
        local ia = Installer.isInstalled(a.install_dirname) and 1 or 0
        local ib = Installer.isInstalled(b.install_dirname) and 1 or 0
        if ia ~= ib then
            return ia > ib
        end
        local sa, sb = tonumber(a.stars) or 0, tonumber(b.stars) or 0
        if sa ~= sb then
            return sa > sb
        end
        return tostring(a.name or "") < tostring(b.name or "")
    end)

    local item_table = {
        {
            text = _("Filter by category…"),
            state = menuIcon("appbar.search"),
            callback = function()
                self:showCategoryPicker()
            end,
        },
        {
            text = _("Search…"),
            state = menuIcon("appbar.search"),
            callback = function()
                self:showSearch(q)
            end,
        },
        {
            text = _("Refresh catalog"),
            state = menuIcon("cre.render.reload"),
            callback = function()
                self:withNetwork(function()
                    self:refreshCatalog({
                        loading_dialog = true,
                        refresh_browser = true,
                    })
                end)
            end,
        },
        {
            text = _("Check installed updates…"),
            state = menuIcon("move.up"),
            callback = function()
                self:checkInstalledUpdates()
            end,
        },
        {
            text = T(_("Check KOMarket update (v%1)"), self:selfVersion()),
            state = menuIcon("move.up"),
            callback = function()
                self:checkSelfUpdate()
            end,
        },
        {
            text = _("Share my plugin list…"),
            state = menuIcon("plus"),
            callback = function()
                self:shareMyPlugins()
            end,
        },
        {
            text = _("Import with share code…"),
            state = menuIcon("bookmark"),
            callback = function()
                self:importSharedPlugins()
            end,
        },
    }

    if cat and cat ~= "all" then
        item_table[#item_table + 1] = {
            text = T(_("Clear category: %1"), self:categoryLabel(cat)),
            state = menuIcon("cancel"),
            callback = function()
                self:showBrowser(q, "all")
            end,
        }
    end

    if q and q ~= "" then
        item_table[#item_table + 1] = {
            text = T(_("Clear search: %1"), q),
            state = menuIcon("cancel"),
            callback = function()
                self:showBrowser("", cat)
            end,
        }
    end

    item_table[#item_table + 1] = {
        text = T(_("—— %1 plugins ——"), tostring(#plugins)),
        enabled = false,
    }

    if #plugins == 0 then
        item_table[#item_table + 1] = {
            text = _("(no matching plugins)"),
            enabled = false,
        }
    end

    for i, plugin in ipairs(plugins) do
        local installed = Installer.isInstalled(plugin.install_dirname)
        local stars = tonumber(plugin.stars) or 0
        local tags = self:formatCategoryTags(plugin)
        local text
        if tags ~= "" then
            text = T("%1  [%2] ★%3", plugin.name or plugin.slug or plugin.id, tags, stars)
        else
            text = T("%1  ★%2", plugin.name or plugin.slug or plugin.id, stars)
        end
        item_table[#item_table + 1] = {
            text = text,
            state = installed and menuIcon("check") or nil,
            callback = function()
                self:showPluginActions(plugin)
            end,
        }
    end

    local title = _("KOMarket")
    local parts = {}
    if cat and cat ~= "all" then
        parts[#parts + 1] = self:categoryLabel(cat)
    end
    if q and q ~= "" then
        parts[#parts + 1] = q
    end
    if #parts > 0 then
        title = T(_("KOMarket · %1"), table.concat(parts, " · "))
    end
    title = title .. "  v" .. self:selfVersion()

    self:closeBrowser()
    local menu = Menu:new{
        title = title,
        item_table = item_table,
        state_w = MENU_STATE_W,
        is_borderless = true,
        is_popout = false,
        title_bar_left_icon = "appbar.menu",
        onMenuHold = function() end,
        close_callback = function() end,
    }
    UIManager:show(menu)
    self._browser_menu = menu
end

function KOMarket:showCategoryPicker()
    local catalog = self._catalog or Catalog.loadCached()
    local all_plugins = (catalog and catalog.plugins) or {}
    local categories = self._categories or Catalog.loadCachedCategories()
    local current = self._filter_category or "all"

    local function countFor(cid)
        if cid == "all" then
            return #all_plugins
        end
        return #Catalog.filterByCategory(all_plugins, cid)
    end

    local item_table = {
        {
            text = T(_("All (%1)"), tostring(countFor("all"))),
            state = current == "all" and menuIcon("check") or nil,
            callback = function()
                self:showBrowser(self._filter_query, "all")
            end,
        },
    }

    for i, c in ipairs(categories) do
        local cid = c.id
        local label = Catalog.resolveCategoryName(c)
        item_table[#item_table + 1] = {
            text = T("%1（%2）", label, tostring(countFor(cid))),
            state = current == cid and menuIcon("check") or nil,
            callback = function()
                self:showBrowser(self._filter_query, cid)
            end,
        }
    end

    UIManager:show(Menu:new{
        title = _("Select category"),
        item_table = item_table,
        state_w = MENU_STATE_W,
        is_borderless = true,
        is_popout = false,
    })
end

function KOMarket:showSearch(prefill)
    local dialog
    dialog = InputDialog:new{
        title = _("Search plugins"),
        input = prefill or "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local q = dialog:getInputText()
                        UIManager:close(dialog)
                        self:showBrowser(q, self._filter_category)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function KOMarket:showPluginActions(plugin)
    local installed = Installer.isInstalled(plugin.install_dirname)
    local tags = self:formatCategoryTags(plugin)
    local lines = {
        plugin.name or plugin.id,
        "",
        plugin.summary or "",
        "",
    }
    local note = Catalog.resolveEditorialNote(plugin.editorial_note)
    if note ~= "" then
        lines[#lines + 1] = T(_("Editor's note: %1"), note)
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = T(_("Author: %1"), plugin.owner or "?")
    lines[#lines + 1] = T(_("Repository: %1/%2"), plugin.owner or "?", plugin.repo or "?")
    lines[#lines + 1] = T(_("Install dir: %1"), plugin.install_dirname or "?")
    if tags ~= "" then
        lines[#lines + 1] = T(_("Categories: %1"), tags)
    end
    lines[#lines + 1] = T(_("Updated: %1"), plugin.updated_at or "?")
    lines[#lines + 1] = T(_("Stars: %1"), tostring(plugin.stars or 0))
    lines[#lines + 1] = installed and _("Status: installed") or _("Status: not installed")
    local detail = table.concat(lines, "\n")

    local ok_text = _("Install")
    local ok_callback = function()
        self:confirmInstall(plugin, false)
    end
    if installed then
        ok_text = _("Update / reinstall")
        ok_callback = function()
            self:confirmInstall(plugin, true)
        end
    end

    UIManager:show(ConfirmBox:new{
        text = detail,
        ok_text = ok_text,
        ok_callback = ok_callback,
        cancel_text = _("Close"),
    })
end

function KOMarket:confirmInstall(plugin, is_update)
    local tip = is_update
        and T(_("Update/reinstall \"%1\"?\nThird-party plugin code will be downloaded."), plugin.name or plugin.id)
        or T(_("Install \"%1\"?\nThird-party plugin code will be downloaded."), plugin.name or plugin.id)

    UIManager:show(ConfirmBox:new{
        text = tip,
        ok_text = _("Continue"),
        ok_callback = function()
            self:withNetwork(function()
                self:doInstall(plugin, { updating = is_update })
            end)
        end,
    })
end

function KOMarket:doInstall(plugin, opts)
    opts = opts or {}
    local busy

    local function closeBusy()
        if busy then
            UIManager:close(busy)
            busy = nil
        end
    end

    local function showBusy(text)
        closeBusy()
        busy = InfoMessage:new{
            text = text,
            force_show = true,
        }
        UIManager:show(busy)
        UIManager:forceRePaint()
    end

    local busy_text = opts.updating
        and T(_("Updating %1 …"), plugin.name or plugin.id)
        or T(_("Installing %1 …"), plugin.name or plugin.id)
    showBusy(busy_text)

    local progress_fmt = opts.updating and _("Updating: %1") or _("Installing: %1")
    local ok, err = Installer.install(plugin, function(msg)
        showBusy(T(progress_fmt, msg))
    end, opts)

    closeBusy()

    if not ok then
        local fail_fmt = opts.updating and _("Update failed: %1") or _("Install failed: %1")
        self:notify(T(fail_fmt, tostring(err)))
        return false, err
    end

    if not opts.quiet then
        UIManager:show(ConfirmBox:new{
            text = opts.updating
                and _("Update complete. Restart KOReader to load the new version.")
                or _("Install complete. Restart KOReader to load the new plugin."),
            ok_text = _("OK"),
            cancel_text = _("Back to market"),
            cancel_callback = function()
                self:showBrowser()
            end,
        })
    end
    return true
end

function KOMarket:checkSelfUpdate()
    self:withNetwork(function()
        local busy

        local function closeBusy()
            if busy then
                UIManager:close(busy)
                busy = nil
            end
        end

        busy = InfoMessage:new{
            text = _("Checking for KOMarket update…"),
            force_show = true,
        }
        UIManager:show(busy)
        UIManager:forceRePaint()

        local update, err = Updates.checkSelfUpdate()
        closeBusy()

        if err then
            self:notify(T(_("Check failed: %1"), tostring(err)))
            return
        end
        if not update then
            self:notify(T(_("KOMarket is up to date (v%1)."), self:selfVersion()))
            return
        end

        UIManager:show(ConfirmBox:new{
            text = T(
                _("New KOMarket version available:\n\n%1 → %2\n\nRestart KOReader after updating."),
                update.local_label,
                update.remote_label
            ),
            ok_text = _("Update"),
            ok_callback = function()
                self:withNetwork(function()
                    self:doSelfUpdate(update.plugin)
                end)
            end,
            cancel_text = _("Cancel"),
        })
    end)
end

function KOMarket:doSelfUpdate(plugin)
    local busy

    local function closeBusy()
        if busy then
            UIManager:close(busy)
            busy = nil
        end
    end

    local function showBusy(text)
        closeBusy()
        busy = InfoMessage:new{
            text = text,
            force_show = true,
        }
        UIManager:show(busy)
        UIManager:forceRePaint()
    end

    showBusy(T(_("Updating KOMarket %1 …"), plugin.latest_tag or ""))

    local ok, err = Installer.install(plugin, function(msg)
        showBusy(T(_("Updating: %1"), msg))
    end, { self_update = true })

    closeBusy()

    if not ok then
        self:notify(T(_("Update failed: %1"), tostring(err)))
        return
    end

    UIManager:show(ConfirmBox:new{
        text = _("KOMarket updated.\n\nFully quit and restart KOReader for the new version to take effect."),
        ok_text = _("OK"),
        cancel_text = _("Back to market"),
        cancel_callback = function()
            self:showBrowser()
        end,
    })
end

function KOMarket:checkInstalledUpdates()
    self:withNetwork(function()
        local busy

        local function closeBusy()
            if busy then
                UIManager:close(busy)
                busy = nil
            end
        end

        busy = InfoMessage:new{
            text = _("Checking installed plugin updates…"),
            force_show = true,
        }
        UIManager:show(busy)
        UIManager:forceRePaint()

        self:refreshCatalog({ loading_dialog = false }, function(ok)
            closeBusy()
            if not ok then
                return
            end

            local installed = Updates.listUserInstalled()
            if #installed == 0 then
                self:notify(_("No user-installed plugins found."))
                return
            end

            local pending = Updates.scan(self._catalog)
            if #pending == 0 then
                self:notify(T(_("Checked %1 installed plugins; all are up to date."), #installed))
                return
            end

            self:confirmBatchUpdate(pending, #installed)
        end)
    end)
end

function KOMarket:confirmBatchUpdate(pending, checked_count)
    local lines = {
        T(_("Checked %1 user-installed plugins; %2 updates available:"), checked_count, #pending),
        "",
    }
    for i, item in ipairs(pending) do
        lines[#lines + 1] = T(
            "• %1  %2 → %3",
            item.plugin.name or item.install_dirname,
            item.local_label,
            item.remote_label
        )
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = _("Download and update all now?")

    UIManager:show(ConfirmBox:new{
        text = table.concat(lines, "\n"),
        ok_text = _("Update all"),
        ok_callback = function()
            self:withNetwork(function()
                self:runBatchUpdate(pending)
            end)
        end,
        cancel_text = _("Cancel"),
    })
end

function KOMarket:runBatchUpdate(pending)
    local total = #pending
    local ok_count = 0
    local fail_lines = {}

    for i, item in ipairs(pending) do
        local busy
        local function closeBusy()
            if busy then
                UIManager:close(busy)
                busy = nil
            end
        end
        local function showBusy(text)
            closeBusy()
            busy = InfoMessage:new{
                text = text,
                force_show = true,
            }
            UIManager:show(busy)
            UIManager:forceRePaint()
        end

        showBusy(T(_("Updating %1 (%2/%3)…"), item.plugin.name or item.install_dirname, i, total))

        local ok, err = self:doInstall(item.plugin, { updating = true, quiet = true })
        closeBusy()

        if ok then
            ok_count = ok_count + 1
        else
            fail_lines[#fail_lines + 1] = T(
                "%1：%2",
                item.plugin.name or item.install_dirname,
                tostring(err)
            )
        end
    end

    local lines = {
        T(_("Updates complete: %1/%2 succeeded."), ok_count, total),
    }
    if #fail_lines > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("Failed:")
        for i, line in ipairs(fail_lines) do
            lines[#lines + 1] = line
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = _("Restart KOReader for new versions to take effect.")

    UIManager:show(ConfirmBox:new{
        text = table.concat(lines, "\n"),
        ok_text = _("OK"),
        cancel_text = _("Back to market"),
        cancel_callback = function()
            self:showBrowser()
        end,
    })
end

function KOMarket:shareMyPlugins()
    UIManager:show(ConfirmBox:new{
        text = _(
            "Upload your installed plugin list (excluding KOMarket) and get a 9-digit share code.\n\n" ..
            "The recipient will download and install plugins in list order."
        ),
        ok_text = _("Continue"),
        ok_callback = function()
            self:withNetwork(function()
                self:doSharePlugins()
            end)
        end,
    })
end

function KOMarket:doSharePlugins()
    local busy
    local function closeBusy()
        if busy then
            UIManager:close(busy)
            busy = nil
        end
    end
    local function showBusy(text)
        closeBusy()
        busy = InfoMessage:new{ text = text, force_show = true }
        UIManager:show(busy)
        UIManager:forceRePaint()
    end

    showBusy(_("Refreshing plugin catalog…"))
    self:refreshCatalog({ loading_dialog = false }, function(ok)
        if not ok then
            closeBusy()
            return
        end

        showBusy(_("Generating plugin list…"))
        local payload, err = SharePack.build(self._catalog)
        if not payload then
            closeBusy()
            self:notify(T(_("Cannot share: %1"), tostring(err)))
            return
        end

        showBusy(_("Uploading…"))
        local resp, upload_err = ShareClient.uploadPluginList(payload, "")
        closeBusy()

        if not resp then
            self:notify(T(_("Upload failed: %1"), tostring(upload_err)))
            return
        end

        local code = ShareClient.formatCode(resp.code)
        UIManager:show(ConfirmBox:new{
            text = T(
                _("Share code created:\n\n%1\n\n%2 plugins\nValid until %3\n\nSave it; others can import via \"Import with share code\"."),
                code,
                tostring(resp.plugin_count or #payload.plugins),
                resp.expires_at or "?"
            ),
            ok_text = _("OK"),
        })
    end)
end

function KOMarket:importSharedPlugins()
    local dialog
    dialog = InputDialog:new{
        title = _("Enter 9-digit share code"),
        input = "",
        input_type = "number",
        description = _("Digits only, e.g. 123456789"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Look up"),
                    is_enter_default = true,
                    callback = function()
                        local code = ShareClient.normalizeCode(dialog:getInputText())
                        UIManager:close(dialog)
                        if not code then
                            self:notify(_("Share code must be 9 digits"))
                            return
                        end
                        self:withNetwork(function()
                            self:previewSharedPlugins(code)
                        end)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function KOMarket:previewSharedPlugins(code)
    local busy = InfoMessage:new{
        text = _("Looking up share code…"),
        force_show = true,
    }
    UIManager:show(busy)

    local meta, err = ShareClient.fetchMeta(code)
    UIManager:close(busy)

    if not meta then
        self:notify(T(_("Check failed: %1"), tostring(err)))
        return
    end
    if type(meta.plugins) ~= "table" or #meta.plugins == 0 then
        self:notify(_("Share code has no plugin list"))
        return
    end

    local lines = {
        T(_("Share code: %1"), ShareClient.formatCode(meta.code)),
        "",
    }
    if meta.label and meta.label ~= "" then
        lines[#lines + 1] = T(_("Name: %1"), meta.label)
    end
    lines[#lines + 1] = T(_("Plugin count: %1"), tostring(meta.plugin_count or #(meta.plugins or {})))
    lines[#lines + 1] = T(_("Valid until: %1"), meta.expires_at or "?")
    lines[#lines + 1] = ""
    lines[#lines + 1] = _("Plugin list (install in this order):")
    for i, item in ipairs(meta.plugins or {}) do
        lines[#lines + 1] = T("%1. %2", tostring(i), item.name or item.install_dirname or "?")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = _("Plugins will be downloaded and installed in order; already installed ones are skipped.")

    UIManager:show(ConfirmBox:new{
        text = table.concat(lines, "\n"),
        ok_text = _("Import"),
        ok_callback = function()
            self:withNetwork(function()
                self:doImportSharedPlugins(code, meta)
            end)
        end,
        cancel_text = _("Cancel"),
    })
end

function KOMarket:doImportSharedPlugins(code, meta)
    if not meta then
        local fetch_err
        meta, fetch_err = ShareClient.fetchMeta(code)
        if not meta then
            self:notify(T(_("Check failed: %1"), tostring(fetch_err or "unknown")))
            return
        end
    end

    local busy = InfoMessage:new{
        text = _("Refreshing plugin catalog…"),
        force_show = true,
    }
    UIManager:show(busy)
    UIManager:forceRePaint()

    self:refreshCatalog({ loading_dialog = false }, function(ok)
        UIManager:close(busy)
        if not ok then
            return
        end

        local resolved, missing, resolve_err = ShareImport.resolvePlugins(meta.plugins, self._catalog)
        if resolve_err then
            self:notify(T(_("Import failed: %1"), tostring(resolve_err)))
            return
        end
        if not resolved or #resolved == 0 then
            if missing and #missing > 0 then
                self:notify(T(_("Plugins not found in catalog:\n%1"), table.concat(missing, "\n")))
            else
                self:notify(_("No plugins to install"))
            end
            return
        end

        if missing and #missing > 0 then
            UIManager:show(ConfirmBox:new{
                text = T(
                    _("The following plugins were not found and will be skipped:\n%1\n\nContinue with the remaining %2 plugins?"),
                    table.concat(missing, "\n"),
                    tostring(#resolved)
                ),
                ok_text = _("Continue"),
                ok_callback = function()
                    self:runSharedPluginInstall(resolved, missing)
                end,
                cancel_text = _("Cancel"),
            })
        else
            self:runSharedPluginInstall(resolved, missing)
        end
    end)
end

function KOMarket:runSharedPluginInstall(plugins, missing)
    local total = #plugins
    local progress = ProgressbarDialog:new{
        title = _("Import plugin list"),
        subtitle = _("Preparing…"),
        progress_max = total,
    }
    progress:show()

    local function setSubtitle(text)
        progress.subtitle = text
        progress:redrawProgressbarIfNeeded()
    end

    local result = ShareImport.installSequential(plugins, {
        on_item = function(i, max, plugin, phase, err)
            local name = plugin.name or plugin.install_dirname or "?"
            if phase == "start" then
                setSubtitle(T(_("Processing %1 (%2/%3)…"), name, i, max))
            elseif phase == "skip" then
                setSubtitle(T(_("Already installed, skipping %1 (%2/%3)"), name, i, max))
            elseif phase == "fail" then
                setSubtitle(T(_("Failed %1: %2"), name, tostring(err)))
            end
        end,
        on_progress = function(i, max, plugin, msg)
            local name = plugin.name or plugin.install_dirname or "?"
            setSubtitle(T(_("%1 (%2/%3): %4"), name, i, max, msg))
        end,
        on_step_done = function(i, max)
            progress:reportProgress(i)
        end,
    })

    progress:close()

    local lines = {
        T(_("Install complete: %1/%2 succeeded (%3 skipped)."),
            tostring(result.ok_count - result.skipped),
            tostring(result.total),
            tostring(result.skipped)),
    }
    if missing and #missing > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("Not found:")
        for i, name in ipairs(missing) do
            lines[#lines + 1] = "• " .. name
        end
    end
    if #result.failures > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("Failed:")
        for i, item in ipairs(result.failures) do
            lines[#lines + 1] = T(
                "• %1：%2",
                item.plugin.name or item.plugin.install_dirname,
                tostring(item.err)
            )
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = _("Restart KOReader for new plugins to load.")

    UIManager:show(ConfirmBox:new{
        text = table.concat(lines, "\n"),
        ok_text = _("OK"),
        cancel_text = _("Back to market"),
        cancel_callback = function()
            self:showBrowser()
        end,
    })
end

function KOMarket:confirmUninstall(plugin)
    UIManager:show(ConfirmBox:new{
        text = T(_("Uninstall \"%1\"?"), plugin.name or plugin.id),
        ok_text = _("Uninstall"),
        ok_callback = function()
            local ok, err = Installer.uninstall(plugin.install_dirname)
            if not ok then
                self:notify(T(_("Uninstall failed: %1"), tostring(err)))
            else
                self:notify(_("Uninstalled. Restart to apply."))
                self:showBrowser()
            end
        end,
    })
end

return KOMarket
