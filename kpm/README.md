# KOMarket KPM Package

[KPM](https://kindlemodding.org/kindle-dev/kpm/index.html) 安装包：在已安装 **KOReader** 的 Kindle 上，将 [komarket.koplugin](../komarket.koplugin) 安装到 `koreader/plugins/`。

## 前置条件

- 设备已越狱并安装 KPM
- 已通过 KPM 或手动方式安装 KOReader（插件目录为 `/mnt/us/koreader/plugins/`）

## 支持的平台

插件本身为纯 Lua，各平台包内容相同，仅 `supported_platforms` 不同以便 KPM 匹配设备：

| 平台 | 适用设备 |
|------|----------|
| `kindle` | K2、DX、K3 及更早型号 |
| `kindle5` | K4、K5 及同代 |
| `kindlepw2` | Paperwhite 2 及更新（旧版固件 arm 软浮点） |
| `kindlehf` | 新版 armhf 固件（≥ 5.16.2.1.1 等） |

打包后会在 `dist/` 生成四个 `.kpkg` 文件，例如：

- `komarket_0.4.2_kindle.kpkg`
- `komarket_0.4.2_kindle5.kpkg`
- `komarket_0.4.2_kindlepw2.kpkg`
- `komarket_0.4.2_kindlehf.kpkg`

## 设备上安装

```text
;kpm update
;kpm install komarket
```

KPM 会根据设备平台自动选择对应的 artifact。安装完成后重启 KOReader，在 **工具 → 插件管理** 中启用 **卡欧市场 / KOMarket**。

## 卸载

```text
;kpm uninstall komarket
```

## 本地打包

需要 Python 3 与网络（首次运行会下载 [kpm-helper.py](https://github.com/KindleModding/KPM/blob/main/kpm-helper.py)）：

```sh
cd kpm
./pack.sh
```

产物在 `kpm/dist/*.kpkg`，可加入自建 KPM 仓库或提交到 [KindleModding/repo](https://github.com/KindleModding/repo)。

### 自建软件源（推荐）

一键打包并写入 `../kpm-repo/`（`kpm-helper.py repo add`）：

```sh
cd kpm
./repo-sync.sh
```

首次运行会自动 `repo-init.sh` 创建空仓库，然后把四个平台的 `.kpkg` 复制到 `kpm-repo/packages/` 并更新 `manifest.v2.json`。推送 `kpm-repo/` 到 GitHub 后，设备上：

```text
;kpm add-repo https://raw.githubusercontent.com/Exhen/komarket-public/main/kpm-repo/manifest.v2.json
;kpm update
;kpm install komarket
```

详见 [`../kpm-repo/README.md`](../kpm-repo/README.md)。

### 加入官方仓库 manifest

先克隆官方仓库（建议放在 `komarket-public` 同级目录）：

```sh
git clone https://github.com/KindleModding/repo.git ../kindlemodding-repo
```

打包后，用 `kpm-helper.py repo add` 写入 **`manifest.v2.json`**（官方仓库使用 v2 manifest）：

```sh
cd kpm
./pack.sh
./repo-add.sh ../kindlemodding-repo
```

或手动对每个平台执行：

```sh
HELPER=.tools/kpm-helper.py
MANIFEST=../kindlemodding-repo/manifest.v2.json
for kpkg in dist/*.kpkg; do
  python3 "$HELPER" repo add "$MANIFEST" "$kpkg"
done
```

脚本会复制 `.kpkg` 到 `packages/komarket/artifacts/` 并更新 manifest。随后在 `kindlemodding-repo` 中 commit 并提 PR。

> 注意：若只传仓库目录路径，`kpm-helper` 默认修改的是 `manifest.json`（v1），官方站点读的是 `manifest.v2.json`，必须显式指定后者。

## 目录结构

```text
kpm/
  README.md
  pack.sh                      # 按平台分别打包
  repo-init.sh                 # 初始化空自建仓库
  repo-sync.sh                 # 打包 + repo add 到 ../kpm-repo/
  repo-add.sh                  # 写入官方 KindleModding/repo
  repo-manifest.example.json   # 仓库 manifest 条目示例
  package/
    manifest.json
    install.sh
    uninstall.sh
    payload/                   # 打包时生成，不入库
  dist/                        # .kpkg 输出，不入库
```

## 版本

`package/manifest.json` 中的 `version` 应与 [komarket.koplugin/_version.lua](../komarket.koplugin/_version.lua) 保持一致。发布新版本时同步更新后重新 `./pack.sh`。
