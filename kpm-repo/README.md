# KOMarket KPM Repository

自建 [KPM](https://kindlemodding.org/kindle-dev/kpm/index.html) 软件源，分发 **KOMarket** 插件包。

本目录由 `kpm/repo-sync.sh` 自动生成/更新，包含：

- `manifest.v2.json` — 仓库索引
- `packages/komarket/artifacts/*.kpkg` — 各平台安装包

## 维护者：发布新版本

```sh
cd kpm
./repo-sync.sh
git add ../kpm-repo/
git commit -m "Publish komarket kpm vX.Y.Z"
git push
```

首次使用若目录不存在，`repo-sync.sh` 会自动执行 `repo-init.sh`。

## 设备端：添加此软件源

将下方 URL 换成你实际托管的 `manifest.v2.json` 地址（GitHub raw、GitHub Pages、任意 HTTPS 静态托管均可）：

```text
;kpm add-repo https://raw.githubusercontent.com/Exhen/komarket-public/main/kpm-repo/manifest.v2.json
;kpm update
;kpm search komarket
;kpm install komarket
```

前提：设备已安装 KPM 与 KOReader（`komarket` 包依赖 `koreader`）。

## 托管说明

KPM 会通过 `add-repo` 的 URL 拉取 JSON manifest；artifact 的 `url` 字段为**相对路径**，会相对于 manifest 所在目录解析。

例如 manifest 位于：

`https://example.com/kpm-repo/manifest.v2.json`

则 artifact：

`packages/komarket/artifacts/komarket_0.4.3_kindlehf.kpkg`

会解析为：

`https://example.com/kpm-repo/packages/komarket/artifacts/komarket_0.4.3_kindlehf.kpkg`

## 查看已添加的软件源

```text
;kpm list-repo
;kpm remove-repo komarket
```
