--[[--
卡欧市场 (KOMarket) — browse / search / install community koplugins.
]]

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local Catalog = require("catalog")
local Installer = require("installer")
local VERSION = require("_version")

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
        text = _("卡欧市场"),
        sorting_hint = "setting",
        callback = function()
            self:openMarket()
        end,
    }
end

function KOMarket:notify(text)
    UIManager:show(InfoMessage:new{ text = text, timeout = 3 })
end

function KOMarket:withNetwork(callback)
    NetworkMgr:runWhenOnline(function()
        callback()
    end)
end

function KOMarket:openMarket()
    self:withNetwork(function()
        self:refreshCatalog(function(ok)
            if ok then
                self:showBrowser()
            end
        end)
    end)
end

function KOMarket:refreshCatalog(callback)
    UIManager:show(InfoMessage:new{
        text = _("正在刷新插件目录…"),
        timeout = 2,
    })
    local data, src_or_err = Catalog.fetchIndex()
    if not data then
        self:notify(T(_("刷新失败：%1"), tostring(src_or_err)))
        if callback then
            callback(false)
        end
        return
    end
    self._catalog = data
    local cats, cat_src = Catalog.fetchCategories()
    self._categories = cats or Catalog.loadCachedCategories()
    logger.info("KOMarket: catalog ready from", src_or_err, "count", #(data.plugins or {}))
    logger.info("KOMarket: categories from", cat_src, "count", #(self._categories or {}))
    if callback then
        callback(true)
    end
end

function KOMarket:categoryLabel(id)
    if not id or id == "all" then
        return _("全部")
    end
    return Catalog.categoryName(self._categories, id)
end

function KOMarket:formatCategoryTags(plugin)
    local cats = plugin.categories or {}
    if #cats == 0 then
        return ""
    end
    local names = {}
    for _, cid in ipairs(cats) do
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
        self:notify(_("目录为空，请先刷新。"))
        return
    end

    local q = self._filter_query
    local cat = self._filter_category or "all"
    local plugins = Catalog.filterPlugins(catalog.plugins, q, cat)
    table.sort(plugins, function(a, b)
        local sa, sb = tonumber(a.stars) or 0, tonumber(b.stars) or 0
        if sa == sb then
            return tostring(a.name or "") < tostring(b.name or "")
        end
        return sa > sb
    end)

    local item_table = {
        {
            text = _("📂 分类筛选…"),
            callback = function()
                self:showCategoryPicker()
            end,
        },
        {
            text = _("🔍 搜索…"),
            callback = function()
                self:showSearch(q)
            end,
        },
        {
            text = _("↻ 刷新目录"),
            callback = function()
                self:withNetwork(function()
                    self:refreshCatalog(function(ok)
                        if ok then
                            self:showBrowser()
                        end
                    end)
                end)
            end,
        },
    }

    if cat and cat ~= "all" then
        item_table[#item_table + 1] = {
            text = T(_("清除分类：%1"), self:categoryLabel(cat)),
            callback = function()
                self:showBrowser(q, "all")
            end,
        }
    end

    if q and q ~= "" then
        item_table[#item_table + 1] = {
            text = T(_("清除搜索：%1"), q),
            callback = function()
                self:showBrowser("", cat)
            end,
        }
    end

    item_table[#item_table + 1] = {
        text = T(_("—— %1 个插件 ——"), tostring(#plugins)),
        enabled = false,
    }

    if #plugins == 0 then
        item_table[#item_table + 1] = {
            text = _("（无匹配插件）"),
            enabled = false,
        }
    end

    for _, plugin in ipairs(plugins) do
        local installed = Installer.isInstalled(plugin.install_dirname)
        local stars = tonumber(plugin.stars) or 0
        local mark = installed and "✓ " or ""
        local tags = self:formatCategoryTags(plugin)
        local text
        if tags ~= "" then
            text = T("%1%2  [%3] ★%4", mark, plugin.name or plugin.slug or plugin.id, tags, stars)
        else
            text = T("%1%2  ★%3", mark, plugin.name or plugin.slug or plugin.id, stars)
        end
        item_table[#item_table + 1] = {
            text = text,
            callback = function()
                self:showPluginActions(plugin)
            end,
        }
    end

    local title = _("卡欧市场")
    local parts = {}
    if cat and cat ~= "all" then
        parts[#parts + 1] = self:categoryLabel(cat)
    end
    if q and q ~= "" then
        parts[#parts + 1] = q
    end
    if #parts > 0 then
        title = T(_("卡欧市场 · %1"), table.concat(parts, " · "))
    end
    title = title .. "  v" .. tostring(VERSION)

    self:closeBrowser()
    local menu = Menu:new{
        title = title,
        item_table = item_table,
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
            text = (current == "all" and "✓ " or "") .. T(_("全部（%1）"), tostring(countFor("all"))),
            callback = function()
                self:showBrowser(self._filter_query, "all")
            end,
        },
    }

    for _, c in ipairs(categories) do
        local cid = c.id
        local label = c.name or cid
        local mark = current == cid and "✓ " or ""
        item_table[#item_table + 1] = {
            text = T("%1%2（%3）", mark, label, tostring(countFor(cid))),
            callback = function()
                self:showBrowser(self._filter_query, cid)
            end,
        }
    end

    UIManager:show(Menu:new{
        title = _("选择分类"),
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
    })
end

function KOMarket:showSearch(prefill)
    local dialog
    dialog = InputDialog:new{
        title = _("搜索插件"),
        input = prefill or "",
        buttons = {
            {
                {
                    text = _("取消"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("搜索"),
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
    if plugin.editorial_note and plugin.editorial_note ~= "" then
        lines[#lines + 1] = T(_("编辑注：%1"), plugin.editorial_note)
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = T(_("作者：%1"), plugin.owner or "?")
    lines[#lines + 1] = T(_("仓库：%1/%2"), plugin.owner or "?", plugin.repo or "?")
    lines[#lines + 1] = T(_("目录名：%1"), plugin.install_dirname or "?")
    if tags ~= "" then
        lines[#lines + 1] = T(_("分类：%1"), tags)
    end
    lines[#lines + 1] = T(_("更新：%1"), plugin.updated_at or "?")
    lines[#lines + 1] = T(_("星标：%1"), tostring(plugin.stars or 0))
    lines[#lines + 1] = installed and _("状态：已安装") or _("状态：未安装")
    local detail = table.concat(lines, "\n")

    local ok_text = _("安装")
    local ok_callback = function()
        self:confirmInstall(plugin, false)
    end
    if installed then
        ok_text = _("更新/重装")
        ok_callback = function()
            self:confirmInstall(plugin, true)
        end
    end

    UIManager:show(ConfirmBox:new{
        text = detail,
        ok_text = ok_text,
        ok_callback = ok_callback,
        cancel_text = _("关闭"),
    })
end

function KOMarket:confirmInstall(plugin, is_update)
    local tip = is_update
        and T(_("确认更新/重装「%1」？\n将下载第三方插件代码。"), plugin.name or plugin.id)
        or T(_("确认安装「%1」？\n将下载第三方插件代码。"), plugin.name or plugin.id)

    UIManager:show(ConfirmBox:new{
        text = tip,
        ok_text = _("继续"),
        ok_callback = function()
            self:withNetwork(function()
                self:doInstall(plugin)
            end)
        end,
    })
end

function KOMarket:doInstall(plugin)
    local busy = InfoMessage:new{
        text = T(_("正在安装 %1 …"), plugin.name or plugin.id),
        force_show = true,
    }
    UIManager:show(busy)
    UIManager:forceRePaint()

    local ok, err = Installer.install(plugin, function(msg)
        busy:free()
        busy = InfoMessage:new{
            text = T(_("安装中：%1"), msg),
            force_show = true,
        }
        UIManager:show(busy)
        UIManager:forceRePaint()
    end)

    UIManager:close(busy)

    if not ok then
        self:notify(T(_("安装失败：%1"), tostring(err)))
        return
    end

    UIManager:show(ConfirmBox:new{
        text = _("安装完成。需要重启 KOReader 后新插件才会加载。"),
        ok_text = _("知道了"),
        cancel_text = _("回到市场"),
        cancel_callback = function()
            self:showBrowser()
        end,
    })
end

function KOMarket:confirmUninstall(plugin)
    UIManager:show(ConfirmBox:new{
        text = T(_("确认卸载「%1」？"), plugin.name or plugin.id),
        ok_text = _("卸载"),
        ok_callback = function()
            local ok, err = Installer.uninstall(plugin.install_dirname)
            if not ok then
                self:notify(T(_("卸载失败：%1"), tostring(err)))
            else
                self:notify(_("已卸载。重启后生效。"))
                self:showBrowser()
            end
        end,
    })
end

return KOMarket
