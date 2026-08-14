# 卡欧市场 · 公开仓（komarket-public）

KOReader 插件目录 JSON + 设备端插件 `komarket.koplugin`。

产品名：**卡欧市场（KOMarket）**  
配套私有仓：`KOMarket`（Web 浏览站 + 自动同步任务）

## 目录结构

```
catalog/
  index.json        # 插件索引（Web 与设备端共用）
  categories.json
  schema.json
meta/
  last_sync.json    # 同步状态（由私有仓 sync 任务写入）
komarket.koplugin/  # 拷贝到 KOReader plugins/ 即可使用
```

## 安装设备端插件

**方式 A — KPM（Kindle 越狱 + 已装 KOReader）**

```text
;kpm install komarket
```

详见 [`kpm/README.md`](kpm/README.md)。

**方式 B — 手动复制**

1. 将本仓库中的 `komarket.koplugin` 文件夹复制到设备：
   - Kobo / Kindle：`koreader/plugins/`
   - Android：`/sdcard/koreader/plugins/`
2. 重启 KOReader → **工具 / 更多工具 → 卡欧市场**。

## 数据约定

- **唯一数据源**：本仓 `catalog/index.json`
- 由私有仓 `KOMarket` 的同步任务按规则扫描 GitHub 上的 koplugin，再 commit/push 更新本仓
- Web 与 `komarket.koplugin` 都只读这份 JSON（Web 可经服务器镜像加速）

字段说明见 `catalog/schema.json`。

## 许可证

插件与目录数据的许可证待定；各第三方插件版权归原作者。
