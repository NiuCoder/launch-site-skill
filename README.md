# launch-site — 网站快速上线技能

一个 agent 技能（[Agent Skills](https://agentskills.io) 开放格式），带着 Claude Code、Codex、Cursor 等 agent 把一个项目从本地跑通推进到正式上线：域名、Cloudflare Workers、D1/R2、密钥、Google 登录、支付（Waffo / PayPal / Stripe）、SEO、AI 演示素材，以及有证据的上线验收。

流程和踩坑清单来自两次真实上线，记录在 [`skills/launch-site/references/pitfalls.md`](skills/launch-site/references/pitfalls.md)，每条按"症状 → 原因 → 做法"写。

An agent skill that walks a coding agent through launching a website on Cloudflare Workers — domain, D1/R2, secrets, Google sign-in, payments, SEO, AI demo assets and verified go-live — with a pitfall list from real launches. The skill text is in Chinese; agents follow it regardless of the user's language.

## 安装

**任意 agent（推荐）**，用 [skills CLI](https://github.com/vercel-labs/skills)：

```bash
npx skills add NiuCoder/launch-site-skill
```

**Claude Code 插件**：

```
/plugin marketplace add NiuCoder/launch-site-skill
/plugin install launch-site@launch-site-skill
```

**手动**：把 `skills/launch-site` 目录复制到 agent 的技能目录：

| Agent | 项目级 | 用户级 |
|---|---|---|
| Claude Code | `.claude/skills/launch-site` | `~/.claude/skills/launch-site` |
| Codex | `.codex/skills/launch-site` | `~/.codex/skills/launch-site` |
| Cursor | `.cursor/skills/launch-site` | — |
| 其他 | `.agents/skills/launch-site` | `~/.agents/skills/launch-site` |

不支持技能目录的 agent：在 `AGENTS.md` 里加一行"上线新站时，阅读并遵循 `<路径>/launch-site/SKILL.md`"。

## 使用

对 agent 说"上线新站"、"launch a new site"，或者输入 `/launch-site`。

两个脚本可以单独用，只需要 bash、curl、node 和 perl（macOS 自带）：

```bash
bash skills/launch-site/scripts/preflight.sh --domain example.com   # 上线前只读预检
```

```bash
bash skills/launch-site/scripts/smoke.sh https://example.com --private /api/user/info --retired /old-page
```

`preflight.sh` 检查工具、wrangler 登录、密钥文件是否被 git 忽略、`site.yaml` 里有没有直接写的密钥、wrangler 配置和 `.env.production` 的站点地址是否一致，以及 NS 和 zone 状态。`smoke.sh` 只发 GET 请求，检查 sitemap 里每个页面的 SEO 标签、跳转、安全响应头、私有接口是否拒绝未登录访问、下线路径的大小写和编码变体。有 FAIL 时两个脚本都以状态 1 退出。

## 目录

```
skills/launch-site/
├── SKILL.md                      # 10 个阶段的流程和硬性规则
├── references/
│   ├── pitfalls.md               # 踩坑清单
│   ├── automation-matrix.md      # 每一步谁做、能否自动化
│   ├── verification.md           # 上线验收清单
│   ├── content-assets.md         # AI 演示素材的标准和预算
│   ├── site-manifest.md          # site.yaml 字段说明
│   └── shipany-template.md       # ShipAny 模板项目的专用命令
├── assets/site.example.yaml      # 站点清单模板
└── scripts/
    ├── preflight.sh
    └── smoke.sh
```

## 贡献新坑

上线时遇到清单里没有的问题，按"症状 → 原因 → 做法"的格式追加到 `pitfalls.md` 对应小节，欢迎提 PR。

## 许可

MIT
