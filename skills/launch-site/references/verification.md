# 上线验收清单

先跑 `scripts/smoke.sh`，全部 PASS 后再做浏览器验收。每一项都记录证据：截图路径、报告 ID、部署版本号、时间（注明时区）。

## 1. HTTP（smoke.sh 覆盖）

- 首页、robots.txt、sitemap.xml 返回 200；
- sitemap 里每个 URL 返回 200，并且都是同一个域名；
- 每个页面：有 title 且各不相同、有 description、canonical 等于页面地址、恰好一个 H1、没有 noindex、有 og:image；
- www 用 301/308 跳转到根域名，路径和 query 保留；http 跳转到 https；
- 首页响应头有 HSTS、`X-Content-Type-Options: nosniff`、`X-Frame-Options` 或 CSP `frame-ancestors`；
- `--private` 指定的接口，未登录时返回 401/403（或 HTTP 200 加错误 envelope，脚本会标 WARN，请人工确认）；
- `--retired` 指定的旧路径返回 404 或 301，并且大小写和编码变体也一样。

## 2. 浏览器

视口：390、768、1440 三档。截图前读取 `window.innerWidth` 确认，截图后核对图片宽度（pitfalls V1）。

| 检查 | 方法 |
|---|---|
| 没有横向溢出 | `document.documentElement.scrollWidth <= clientWidth` |
| 浅色和深色主题都可读 | 切换主题后刷新，确认主题保留 |
| 控制台没有新增错误 | 和上一版本对比，见 pitfalls L5 |
| 首屏能看到核心工具 | 1440 和 390 两档都检查 |
| 视频能播放 | 点击后 `currentTime` 增加，`readyState=4`，没有 media error |
| 图片都加载了 | 懒加载的图片要先滚动到可见位置 |
| 未登录点击购买 | 跳转登录，登录后回到原页面 |

## 3. 登录（用户本人操作）

- Google 按钮登录，从首页、带 `#` 的页面、定价页各试一次；
- One Tap 登录后，页头立即显示已登录；
- 退出后再进 `/admin`，应跳转到登录页；
- 管理员账号能进 `/admin`，设置页里的密钥显示为打码值。

## 4. 支付（用户本人操作，先测试环境）

- 结账页金额和网站价格一致；
- 付款后积分或订阅到账，订单状态变为已支付；
- 在支付商后台重发一次通知，积分不会重复发放；
- 用无签名或错误签名请求回调地址，返回错误，订单和积分都没有变化。

## 5. 性能（可选，上线前做一次）

- PageSpeed Insights 的移动端和桌面端各跑两轮，记录报告 ID；
- 实验室数据不等于真实用户的 Core Web Vitals；CrUX 显示 No Data 时，不要写成"CWV 通过"；
- Best Practices 低于 100 时，先看有没有 hydration 错误（pitfalls L7）。

## 汇报格式

```
| 项目 | 级别 | 证据 |
|---|---|---|
| HTTP 冒烟 | 已部署 | smoke.sh 24/24 PASS，版本 xxxx |
| Google 登录 | 业务验收 | 用户本人确认，截图 ... |
| 真实付款 | 未验收 | 等待商户审核 |
```
