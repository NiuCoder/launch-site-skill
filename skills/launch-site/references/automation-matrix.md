# 上线自动化矩阵

每个步骤用哪种方式完成。**这张表可以直接改**：发现某个浏览器步骤其实能用 API 做，就改"方式"和"状态"两列，并在"命令 / 入口"写清楚怎么做。

"ShipAny" 一列的命令只在 ShipAny 模板项目里有（见 shipany-template.md）；其他项目按"通用做法"一列。

## 图例

| 方式 | 含义 |
|---|---|
| `script` | 项目脚本，agent 直接运行 |
| `wrangler` | Cloudflare CLI，agent 直接运行（需要 `wrangler login` 或 `CLOUDFLARE_API_TOKEN`） |
| `cf-api` | Cloudflare REST API，wrangler 没有对应命令时使用 |
| `api` | 第三方 REST API（Google / PayPal / Waffo / Resend） |
| `agent` | agent 改仓库文件，不碰外部系统 |
| `browser` | 必须用户本人在浏览器里操作（登录、KYC、同意条款、审核） |

| 状态 | 含义 |
|---|---|
| ✅ | 有现成命令，agent 执行（远程写操作仍要先确认） |
| 🟡 | 能自动化但还没有脚本，agent 带着用户手动做 |
| 🔴 | 只能用户本人做 |
| ❓ | 能否自动化未验证，先按人工处理 |

## A. 账号与授权（一次性，第 0 阶段）

| # | 步骤 | 方式 | 状态 | 通用做法 | 备注 |
|---|---|---|---|---|---|
| A1 | wrangler 登录 | browser | 🔴 | `npx wrangler login` | 每台机器一次；CI 用 API token |
| A2 | Cloudflare API token | browser | 🔴 | Dashboard → My Profile → API Tokens | Zone:Read、DNS:Edit、Workers、D1、R2。存进被忽略的文件 |
| A3 | Google Cloud 项目 | browser | 🔴 | console.cloud.google.com | 可复用已有项目 |
| A4 | PayPal 商家账号 + KYC | browser | 🔴 | paypal.com/business | 多个站可共用 |
| A5 | Waffo 商户注册 + 业务审核 | browser | 🔴 | Waffo 控制台 | 审核前生产不可用，见 pitfalls P1 |

## B. 域名与 Cloudflare

| # | 步骤 | 方式 | 状态 | 通用做法 | 备注 |
|---|---|---|---|---|---|
| B1 | 买域名 | browser | 🔴 | 注册商 | |
| B2 | 加为 Cloudflare zone | cf-api | 🟡 | `POST /client/v4/zones` 或 Dashboard "Add a domain" | |
| B3 | 注册商改 NS | browser | 🔴 | 注册商后台 | 在 CF Registrar 买的跳过 |
| B4 | 等 zone 生效 | cf-api | ✅ | `preflight.sh --domain` 查 NS；有 token 时查 `status` | |
| B5 | 清理冲突的 DNS 记录 | cf-api | 🟡 | 先记录 ID 和值，再删除 | 见 pitfalls C1，必须确认 |
| B6 | 创建 D1 | wrangler | ✅ | `npx wrangler d1 create <name>` | |
| B7 | 创建 R2（公开桶 / 私有桶） | wrangler | ✅ | `npx wrangler r2 bucket create <name>` | 见 pitfalls C5 |
| B8 | 公开桶访问地址 | wrangler | ✅ | `r2 bucket dev-url enable <name>` 或 `r2 bucket domain add` | 只用于公开桶 |
| B9 | wrangler 生产配置 | agent | 🟡 | 按 `site.yaml` 写 `name`、`routes`、`vars`、绑定 | |
| B10 | 数据库迁移 | wrangler | ✅ | `npx wrangler d1 migrations apply DB --remote` | |
| B11 | Worker secrets | wrangler | ✅ | `npx wrangler secret put NAME < file` | 值从 stdin 传入 |
| B12 | 部署 + 自定义域名 + 证书 | wrangler | ✅ | routes 写 `custom_domain: true`，用项目的部署命令 | zone 必须已生效 |
| B13 | 发信域名 | browser | ❓ | Dashboard → Email Service | |

## C. 应用数据

| # | 步骤 | 方式 | 状态 | ShipAny | 通用做法 |
|---|---|---|---|---|---|
| C1 | 角色权限 | script | ✅ | `pnpm rbac:init --d1=remote --config=<cfg>` | 项目自己的 seed |
| C2 | 第一个账号 | browser | 🔴 | 用户用 Google 登录一次；或 `--admin-password=` 建密码账号 | |
| C3 | 超级管理员 | script | ✅ | `pnpm rbac:init ... --admin-email=<email>` | |
| C4 | 后台配置（OAuth、支付、邮件） | script | ✅ | `pnpm site:config --from=site.yaml --env=production --d1=remote --config=<cfg>` | 后台设置页手填 |

## D. Google

| # | 步骤 | 方式 | 状态 | 做法 | 备注 |
|---|---|---|---|---|---|
| D1 | OAuth 同意屏幕 | browser | 🔴 | GCP → OAuth consent screen | 需要隐私政策、条款的线上地址 |
| D2 | OAuth Web Client | browser | 🔴 | GCP → Credentials | 来源 `https://<domain>`；回调见 SKILL.md 第 5 阶段 |
| D3 | 写进后台配置 | script | ✅ | C4 | |
| D4 | 同意屏幕发布到生产 | browser | 🔴 | GCP | 只用基础 scope 一般不需要审核 |
| D5 | Search Console 添加并验证 | cf-api + api | 🟡 | TXT 记录用 CF API；站点用 Site Verification API | |
| D6 | 提交 sitemap | api | 🟡 | Search Console API 或 `gsc` MCP 的 `submit_sitemap` | |
| D7 | GA4 媒体资源 | api | 🟡 | Analytics Admin API | 衡量 ID 写进配置 |

## E. PayPal

| # | 步骤 | 方式 | 状态 | 做法 | 备注 |
|---|---|---|---|---|---|
| E1 | REST App，拿 client id/secret | browser | 🔴 | developer.paypal.com | secret 存进被忽略的文件 |
| E2 | 注册 webhook | api | 🟡 | `POST /v1/notifications/webhooks` | ShipAny 回调 `https://<domain>/api/payment/notify/paypal` |
| E3 | 写进后台配置 | script | ✅ | C4 | |

## F. Waffo

| # | 步骤 | 方式 | 状态 | 做法 | 备注 |
|---|---|---|---|---|---|
| F1 | merchant id、store id、API 私钥 | browser | 🔴 | Waffo 控制台 | 测试和生产是两把不同的 key，见 pitfalls P3 |
| F2 | 同步商品 + 注册 webhook | api | 🟡 | 项目的 bootstrap 脚本或后台接口 | 运行前看已有 webhook，见 pitfalls P4 |
| F3 | 写入商品映射 | script | ✅ | `{ json: ... }` 写进 `site.yaml`，再跑 C4 | |

## G. 内容与 SEO

| # | 步骤 | 方式 | 状态 | 做法 | 备注 |
|---|---|---|---|---|---|
| G1 | 品牌名、描述、logo | agent | 🟡 | 写进 wrangler vars 和 `.env.production` | |
| G2 | 首页和落地页文案 | agent | 🟡 | 改文案文件和路由的 head | 用户审稿 |
| G3 | IndexNow key | agent | 🟡 | 每个站生成新的 key 和 key 文件 | 见 pitfalls S4 |
| G4 | 推送 IndexNow | script | ✅ | 项目脚本或 `POST https://api.indexnow.org/indexnow` | |
| G5 | AI 演示素材 | script + agent | 🟡 | 见 content-assets.md | 有预算上限 |

## H. 验收

| # | 步骤 | 方式 | 状态 | 做法 |
|---|---|---|---|---|
| H1 | HTTP 冒烟 | script | ✅ | `scripts/smoke.sh https://<domain>` |
| H2 | 浏览器验收 | agent | 🟡 | verification.md 清单 |
| H3 | 真实登录 | browser | 🔴 | 用户本人 |
| H4 | 真实付款 | browser | 🔴 | 用户本人，先测试环境后生产 |
