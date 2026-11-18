# 项目操作约定

> 模拟器相关（基准镜像、端口、实测要求）统一看工作区根规则 `../AGENTS.md` §1；
> UNI 的任何修改都必须在领克 AAOS 820A（API 28）模拟器里实测通过才算完成。

- UNI 桌面的 OTA 更新检查 API 使用 `https://ota.i4o.xyz`。
- `share-ota.circleai.tech` 是 APK 下载域名，不是更新检查 API。当前服务签发该域名的 HTTP 下载链接；构建时必须保留对应的下载域名及 HTTP 白名单，下载内容仍需校验大小和 SHA-256。
- 用户未明确允许时不要推送 Git 远程。
