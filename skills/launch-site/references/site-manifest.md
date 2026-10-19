# site.yaml 字段说明

模板：[../assets/site.example.yaml](../assets/site.example.yaml)。放在项目根目录，可以提交进仓库：它不含密钥，只含引用。

| 段 | 用途 | 谁读 |
|---|---|---|
| `long_lead` | 第 0 阶段的外部审核进度 | 本技能（汇报用） |
| `site` | 域名、`app_url`、品牌名、描述、logo、语言、客服邮箱 | 第 3 阶段写进 wrangler `vars` 和 `.env.production` |
| `seo` | 首页 title、description、关键词、OG 图、是否推送 IndexNow | 第 7 阶段 |
| `cloudflare` | Worker 名、wrangler 配置文件、D1、R2 私有桶和公开桶、secrets 的文件引用、测试环境 | 第 2、3 阶段 |
| `admin` | 超级管理员邮箱 | 第 4 阶段 |
| `pricing` | 积分包或订阅的 ID、积分、价格 | 第 6 阶段同步支付商品 |
| `assets` | AI 演示素材的验收标准和预算 | 第 7 阶段，见 content-assets.md |
| `payments` | 支付商初始化选项 | 第 6 阶段 |
| `config` | 写进后台配置表的键值（OAuth、支付、邮件） | ShipAny 的 `pnpm site:config` |

## 密钥引用

| 写法 | 适合 | 说明 |
|---|---|---|
| `{ file: <路径> }` | PEM 私钥等多行内容 | 相对 `site.yaml` 所在目录；文件必须被 git 忽略 |
| `{ env: <变量名> }` | 短密钥 | 从 `.env.<环境>.local`、`.env.<环境>` 读取，shell 环境变量优先；多行值用双引号包住 |
| `{ json: ... }` | 商品映射等结构化值 | 存成 JSON 字符串 |

直接写在清单里的密钥会被拒绝。可以用 `preflight.sh` 检查引用的文件是否都被 git 忽略。
