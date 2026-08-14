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

```text
;kpm add-repo https://repo.6ili6ili.com
;kpm update
;kpm search komarket
;kpm install komarket
```

前提：设备已安装 KPM 与 KOReader（`komarket` 包依赖 `koreader`）。

## 托管说明

- manifest 内 artifact `url` 使用 **GitHub 绝对地址**，安装包下载直连 GitHub，不经短域名。
- `repo.6ili6ili.com` 仅用于 `add-repo` / `update` 拉 manifest；Cloudflare 规则应**只重定向根路径 `/`**，不要用 `/*` 通配（否则 `.kpkg` 请求也会被重定向到 JSON）。

## 查看已添加的软件源

```text
;kpm list-repo
;kpm remove-repo komarket
```
