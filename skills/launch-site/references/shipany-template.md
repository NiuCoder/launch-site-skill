# ShipAny 模板项目的命令

适用于 ShipAny Next / ShipAny TanStack 模板的项目。`preflight.sh` 发现 `scripts/site-config.ts` 和 `scripts/init-rbac.ts` 同时存在，就会判定为这一类。没有 `site:config` 脚本时，说明项目的模板版本还不支持，先告诉用户，改为在后台设置页手动填写。

`<cfg>` 指生产用的 wrangler 配置文件（通常是 `wrangler.production.jsonc`）。

## 部署

项目里一般还有 `deploy-cloudflare` 技能，负责 D1 创建、迁移、secrets、部署和冒烟测试，可以重复运行。本技能的第 3 阶段交给它，但先做完这三件事：zone 检查、冲突 DNS 记录检查、R2 公开桶和私有桶的确认。

```bash
pnpm cf:deploy          # 先读入 .env.production，再构建、部署
```

不要直接跑 `wrangler deploy`（pitfalls C2）。

## 角色权限和管理员

```bash
pnpm rbac:init --d1=remote --config=<cfg> --dry-run                    # 只打印 SQL
pnpm rbac:init --d1=remote --config=<cfg>                              # 重复运行结果相同
pnpm rbac:init --d1=remote --config=<cfg> --admin-email=<email>        # 用户要先登录过一次
pnpm rbac:assign --d1=remote --email=<email> --role=editor
```

- 输出 `User not found`：用户还没登录过，请用户登录后再跑；
- 只有 `super_admin` 能进 `/admin`；
- 已上线的站不要随便重跑 `rbac:init`：它会把四个默认角色的权限重置成模板默认值。

## 后台配置

```bash
pnpm site:config --from=site.yaml --dry-run                                         # 只显示键名和打码值
pnpm site:config --from=site.yaml --env=production --d1=remote --config=<cfg>       # 写入
```

- 密钥只能写成 `{ file: path }` 或 `{ env: NAME }`。直接写在清单里的密钥，和没被 git 忽略的密钥文件，脚本都会拒绝；
- `--env=production` 会从 `.env.production[.local]` 读取 `CONFIG_ENCRYPTION_KEY`。写入前，脚本会先用它解密一条线上已有的密文，不一致就中止；
- `auth_secret`、`database_*`、`db_*` 这些键不能写，它们属于 Worker secrets；
- D1 配置不走缓存，写入后下一个请求就生效，不用重新部署；
- 只改支付时，`site.yaml` 只写要改的几个键，不列出的键不会被改动。

## 没有加密 key 原值时

本地找不到 `CONFIG_ENCRYPTION_KEY` 原值，`site:config` 就写不了密钥类配置（它拒绝明文写入，也不能换 key）。这时改成用 Worker secret 提供密钥，后台配置只写非密钥项：

1. `npx wrangler secret put <ENV_NAME> --config <cfg> < <密钥文件>`（变量名是配置键的大写，例如 `waffo_private_key` → `WAFFO_PRIVATE_KEY`，由 `src/config/index.ts` 读取）；
2. **删掉 D1 `config` 表里同名的行**：配置合并规则是 D1 优先于环境变量，旧值留着会把 Worker secret 盖掉；
3. 非密钥项照常用 `site:config` 写；
4. 回读确认：`wrangler secret list` 有这个名字，D1 里没有同名行。

## 找密钥（只看名字）

`--dry-run` 报 `cannot read file` 或 `is not set` 时：

```bash
ls *.pem *.key .secrets/ 2>/dev/null
grep -oE '^[A-Z][A-Z0-9_]*=' .env.production | tr -d '='
```

把候选项列给用户，**由用户确认**用哪个：同一个站可能同时有测试和生产两把 key。

## 回调地址

| 用途 | 地址 |
|---|---|
| Google OAuth | `https://<domain>/api/auth/callback/google` |
| PayPal webhook | `https://<domain>/api/payment/notify/paypal` |
| Waffo webhook | `https://<domain>/api/payment/notify/waffo` |
| Stripe webhook | `https://<domain>/api/payment/notify/stripe` |

## IndexNow

```bash
SITE_URL=https://<domain> pnpm indexnow
```

换站时先换 `scripts/indexnow-ping.mjs` 里的 key 和对应的 key 文件路由（pitfalls S4）。
