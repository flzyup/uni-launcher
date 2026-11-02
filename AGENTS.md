# 项目操作约定

- UNI 桌面的 OTA 更新检查 API 使用 `https://ota.i4o.xyz`。
- `share-ota.circleai.tech` 是 APK 下载域名，不是更新检查 API。当前服务签发该域名的 HTTP 下载链接；构建时必须保留对应的下载域名及 HTTP 白名单，下载内容仍需校验大小和 SHA-256。
- 用户未明确允许时不要推送 Git 远程。
