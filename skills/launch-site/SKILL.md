---
name: launch-site
description: "Launch a new SaaS / tool website end to end on Cloudflare Workers — domain, D1/R2, secrets, Google sign-in, payments (Waffo / PayPal / Stripe), SEO, AI demo assets and production verification — following a phase plan built from real launches and their pitfalls. Use when the user wants to ship a new site, put a template project online, bind a new domain, or audit what is still missing before launch. Triggers: 'launch a new site', 'ship this site', 'go live', 'put it on a domain', '上线新站', '快速上站', '用模板开新站', '配置新域名上线', '上线前还差什么', '/launch-site'."
argument-hint: "[--from=site.yaml] [--phase=0..9] [--url=https://example.com]"
user-invocable: true
---

# 上线新站 — $ARGUMENTS

把一个能在本地跑的项目变成线上可收费、可被搜索到、有证据证明能用的网站。流程来自两次真实上线，那两次的坑都记在 [references/pitfalls.md](references/pitfalls.md)。**开始前先读 pitfalls.md 里和当前阶段对应的小节**，每个阶段结束前对照它自检。

## 先判断项目类型

```bash
bash <skill-dir>/scripts/preflight.sh --domain <domain>     # 只读，不改任何东西
```

`<skill-dir>` 是本 SKILL.md 所在目录。脚本会报告：

- **ShipAny 模板**（存在 `scripts/site-config.ts` 和 `scripts/init-rbac.ts`）：D1 角色、管理员、后台配置都有现成脚本，按 [references/shipany-template.md](references/shipany-template.md) 执行。
- **其他 Cloudflare Workers 项目**：Cloudflare 部分照常，数据和配置步骤按该项目自己的方式做，本技能只提供检查清单。
- **非 Workers 项目**：第 3 阶段换成对应平台的部署方式，其余阶段（登录、支付、SEO、验收）照用。

每一步由谁做、能不能自动化，以 [references/automation-matrix.md](references/automation-matrix.md) 为准：✅ 由你执行；🟡 带着用户手动做；🔴 停下来请用户在浏览器里操作。

## 硬性规则

1. **远程写操作每次先确认。** 部署、`wrangler secret put`、远程 D1 写入、删除 DNS 记录、注册 webhook、同步支付商品，执行前说清楚要做什么，等用户说"是"。只读命令不用问。
2. **不显示密钥的值。** 不 `cat` 密钥文件或 `.env.*`，只看文件名、变量名、长度。密钥经文件或 stdin 传给命令，不放进命令参数。
3. **密钥不进仓库，也不进清单。** `site.yaml` 只写 `{ file: ... }` 或 `{ env: ... }` 引用，引用的文件必须被 git 忽略。
4. **加密 key 一旦上线就不能换。** Worker secret 设置以后读不回来，`CONFIG_ENCRYPTION_KEY` 这类 key 本地必须留一份原值。不要用轮换 key 来"修复"问题。
5. **不替用户做身份和法律动作。** 同意条款、KYC/KYB、提交商户审核、填写法定姓名和税务信息，都由用户本人完成。
6. **完成要分三级汇报，不能混。** 见下面"完成的定义"。

## 完成的定义

每一项都要标明达到哪一级：

| 级别 | 含义 | 例子 |
|---|---|---|
| 代码通过 | 测试、类型检查、构建通过 | `pnpm build` exit 0 |
| 已部署 | 新版本在线，HTTP 冒烟通过 | `smoke.sh` 全部 PASS，版本号已回读 |
| 业务验收 | 真实用户路径走通，有证据 | 真人 Google 登录成功；真实付款后积分到账 |

模拟测试通过不等于已部署；已部署不等于业务验收。没做的写"未验收"，不要写"应该没问题"。

## 密钥交接：什么时候、怎么交给 agent

agent 弹不出安全的输入框，聊天记录也不是安全通道：**永远不要请用户把密钥贴进聊天**。没有密钥，后面的自动化就停在那里，所以每到需要密钥的阶段，必须先停下来，按下表引导用户完成交接，确认到位后再继续。

**交接方式**（让用户二选一，每把密钥都要明确用哪种）：

| 方式 | 用户做什么 | agent 之后怎么用 |
|---|---|---|
| A. 放进本地文件 | 把密钥存成仓库里被 git 忽略的文件（如根目录的 `*.pem`、`.secrets/<name>`），或写进 `.env.production` 的一个变量 | `site.yaml` 写 `{ file: ... }` / `{ env: ... }`；推 Worker secret 时用 `< 文件` 走 stdin |
| B. 用户自己在终端输入 | 在终端运行 agent 给出的命令，例如 `npx wrangler secret put WAFFO_PRIVATE_KEY --config <cfg>`，按提示粘贴（不回显） | agent 只用 `wrangler secret list` 确认名字存在 |

**交接节点**（第 1 阶段先列出完整的"密钥清单"表：名称、用途、放在哪里（Worker secret / D1 配置）、谁去哪里拿、交接方式、状态；之后到对应阶段逐个收）：

| 阶段 | 需要的密钥 | 说明 |
|---|---|---|
| 第 3 阶段之前 | `AUTH_SECRET`、`CONFIG_ENCRYPTION_KEY` | agent 用 `openssl rand -base64 32` 生成到 `.secrets/` 下的文件，**并请用户立刻备份到密码管理器**：`CONFIG_ENCRYPTION_KEY` 推上去以后读不回来，丢了就再也写不了加密配置（pitfalls P12） |
| 第 5 阶段之前 | Google OAuth client secret | 用户在 GCP 创建 Web Client 后交接 |
| 第 6 阶段之前（测试） | 支付测试密钥（Waffo 测试私钥、PayPal sandbox secret） | |
| 商户审核通过后（生产） | 支付生产密钥（Waffo 生产私钥、PayPal live secret） | 和测试密钥是两把不同的 key（pitfalls P3）；交接后先核对形状（单行 Base64 / PEM、长度），确认没有填错变量名（pitfalls P13） |

交接后只核对名字、长度和格式，不读内容。

## 第 0 阶段：先启动耗时最长的事（第一天就做）

这些要等外部审核，和开发并行推进，不要等网站做完再开始：

| 事项 | 为什么要早 |
|---|---|
| 支付商户审核（Waffo KYB、PayPal 商家账号） | 审核通过前生产环境不能收款，这是上一次上线最大的阻塞 |
| 买域名、改 NS 到 Cloudflare | zone 生效要几分钟到几小时 |
| Google OAuth 同意屏幕 | 需要隐私政策和条款的线上地址 |
| 发信域名（Cloudflare Email Service / Resend） | DNS 验证要时间 |
| AI 供应商的商用条款和费用 | 决定定价和法务页写法 |

输出一张表：每项的负责人（用户 / agent）、状态、下一步。

## 第 1 阶段：站点清单和预检

1. 没有 `site.yaml` 就从 [assets/site.example.yaml](assets/site.example.yaml) 复制，和用户逐段填写。字段说明见 [references/site-manifest.md](references/site-manifest.md)。
1. 输出"密钥清单"表（见上面"密钥交接"），和用户确认每把密钥的交接方式和时间点。
2. 跑 `preflight.sh`，修掉所有 FAIL。WARN 逐条和用户确认。
3. 新克隆的项目先 `build` 再跑测试：生成文件（路由树、i18n 编译产物）不存在时测试会失败。

## 第 2 阶段：测试环境（要接支付时必做）

用独立的 Worker（workers.dev 子域名）、独立的 D1 和 R2、独立的 secrets 先跑通支付和登录。测试环境：

- 不绑生产域名、生产 R2、邮件和定时任务；
- 响应头带 `X-Robots-Tag: noindex`；
- 只复制角色权限，不复制生产用户和财务数据。

测试构建会覆盖 wrangler 配置。**部署前看一眼目标 Worker 名字**，只用项目封装好的部署命令，不要直接 `wrangler deploy`。

## 第 3 阶段：Cloudflare 资源与部署

按顺序做，对照 pitfalls.md 的"Cloudflare"小节：

1. **zone**：确认域名在 Cloudflare 上是 active。根域名或 www 上有旧的 A/CNAME 记录时，绑定 Worker 自定义域名会报 409。删除前先记下记录 ID 和值，方便回滚，并且先问用户。
2. **R2**：分清公开桶（样片、海报）和私有桶（用户上传和生成物）。用 `wrangler r2 bucket list` 和 `r2 bucket dev-url get` 确认后再上传，永远不要打开私有桶的公开访问。
3. **wrangler 配置**：`name`、`routes`（根域名和 www，`custom_domain: true`）、`vars`（`VITE_APP_URL` 等）、D1/R2 绑定。`VITE_APP_URL` 会在构建时写进产物，构建前确认 shell 里用的是生产值，不是 `.env.local` 里的 localhost。
4. **secrets**：从文件经 stdin 传入。上传加密 key 之前，确认本地已经保存了原值。
5. **数据库迁移**，然后部署。部署后回读版本号和流量比例。
6. www 跳转到根域名要保留路径和 query。

## 第 4 阶段：应用数据

角色权限、第一个超级管理员、后台配置（OAuth、支付、邮件密钥）。ShipAny 模板的命令见 shipany-template.md。要点：

- 授予管理员前，用户要先登录过一次网站（或用脚本建密码账号）。
- 写后台配置前先 dry-run 给用户看打码后的值。
- 已上线的站只改一两个配置时，只写要改的键，不要重跑会重置角色权限的初始化。

## 第 5 阶段：登录

Google OAuth Web Client 的来源填 `https://<domain>`，回调填项目实际的回调路径（ShipAny/better-auth 是 `https://<domain>/api/auth/callback/google`）。然后**逐条验证** pitfalls.md 里的"登录"小节，至少包括：

- 从带 `#` 的页面（如 `/#workspace`）点登录，能回到原页面；
- One Tap 登录后，页头立即显示已登录；
- 用户关掉 One Tap、FedCM 冷却、没有 Google 会话这三种情况分别表现正常；
- 用密码注册过的邮箱再用 Google 登录，有明确提示。

控制台里的 Google FedCM `NetworkError` 先用上一个版本对比，旧版本也有就不是本次回归，不要因此回滚。

## 第 6 阶段：支付

先在测试环境走完一笔真实测试付款，再切生产。切生产前先按"密钥交接"收生产密钥；本地没有 `CONFIG_ENCRYPTION_KEY` 原值时，按 shipany-template.md 的"没有加密 key 原值时"处理。对照 pitfalls.md 的"支付"小节。必须验证：

1. 结账金额和本地价格一致（改了本地价格不会自动更新远端商品）；
2. 付款成功后积分或订阅到账；
3. 重复通知不会重复发放；
4. 错误签名、错误商店、错误环境的通知被拒绝，并且不发放；
5. 处理失败时回调返回 5xx，让支付商重试。

注册 webhook 前先去控制台看有没有已经存在的，重复运行初始化脚本会多注册一个。切换商户、商店或环境时，先关闭支付并清掉旧的商品映射。

## 第 7 阶段：内容、SEO 和演示素材

- 文案里的每条承诺都要和实际功能一致（例如"会去掉车标"必须是模型真的做到了）。
- 每个公开页面都要有：唯一的 title、description、精确的 canonical、一个 H1（并且是第一个标题）、OG/Twitter 图片、语言 alternate。不要只检查首页。
- robots 屏蔽的路径下不要放需要被第三方抓取的资源（例如交给审核服务读取的媒体）。
- IndexNow key 每个站单独生成，不要沿用模板里的。

**AI 生成的演示素材（案例视频、图片）**：开工前和用户定好验收标准和预算上限，按 [references/content-assets.md](references/content-assets.md) 执行。这一步在上一次上线中占了一大半时间。

## 第 8 阶段：上线验收

```bash
bash <skill-dir>/scripts/smoke.sh https://<domain> [--private /api/user/credits] [--retired /old-path]
```

脚本只发 GET 请求，检查首页、robots、sitemap 里所有 URL、www 跳转、安全响应头、每页的 SEO 标签，以及未登录访问私有接口被拒绝。然后按 [references/verification.md](references/verification.md) 做浏览器验收，并把证据（截图、报告 ID、版本号）记录下来。

## 第 9 阶段：上线后

- Search Console：添加站点、验证、提交 sitemap；
- GA4：创建媒体资源，把衡量 ID 写进配置；
- 推送一次 IndexNow；
- 一周后看 Search Console 的收录和查询，再决定下一批页面。

## 结束时

1. 汇报：按阶段列出每一项的完成级别（代码通过 / 已部署 / 业务验收 / 未完成），以及剩下哪些要用户自己做；
2. 本次遇到的新坑，按 pitfalls.md 的格式（症状 → 原因 → 做法）追加进去；
3. 用户说某个 🔴 步骤其实能自动化时，更新 automation-matrix.md 那一行，再按新方式执行。
