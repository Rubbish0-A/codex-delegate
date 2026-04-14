<p align="center">
  <img src="docs/banner.png" alt="codex-delegate banner" width="100%">
</p>

# codex-delegate

**轻量级 Claude Code + Codex CLI 协作插件。**

> 零依赖。纯 Bash。Git 安全。Windows 实战验证。

Claude 负责思考。Codex 负责执行。互不干扰，各司其职。

[English](README.md) | **中文**

---

## 为什么选这个插件？

Claude Code **没有内置的 Codex 集成**。你可以通过 Bash 运行 `codex exec`，但那只是一个裸进程 —— 没有 git 保护、没有输出捕获、没有超时、没有结构化交接。

OpenAI 发布了[官方插件](https://github.com/openai/codex-plugin-cc)（`codex-plugin-cc`），但那是一套重量级的 Node.js/TypeScript 技术栈，包含 15+ 个库文件、一个 app-server 中间层，还需要 `npm install`。

**codex-delegate** 走了一条不同的路：**3 个 Bash 脚本，1 个 Skill，1 个命令。就这些。** 不需要构建。不需要运行时依赖。克隆即用。

### 对比

| | 原生 Bash | OpenAI 官方插件 | **codex-delegate** |
|---|---|---|---|
| **安装复杂度** | 无 | `npm install` + app server | 仅需克隆 |
| **运行时依赖** | 无 | Node.js 18+ | 无（纯 Bash） |
| **Git 安全** | 无 | 无 | 自动 stash、HEAD 记录、回滚信息 |
| **超时保护** | 无 | 无 | 可配置 `CODEX_TIMEOUT` |
| **中断安全** | 无 | 无 | `trap` 清理 + stash 警告 |
| **测试修复循环** | 手动 | 无 | 内置（运行 → 修复 → 重跑，最多 N 轮） |
| **协作模式** | 无 | 无 | 谨慎 / 快速 / 诊断 |
| **委派判断** | 无 | 基础 | 教 Claude 何时该委派，而不仅是如何委派 |
| **输出捕获** | 仅 stdout | 结构化 | `-o` 文件 + stdout 双通道 |
| **后台任务** | 手动 | `/codex:status/result/cancel` | 通过 Claude Code 原生支持 |
| **对抗性审查** | 无 | `/codex:adversarial-review` | 通过自定义审查 prompt |
| **审查门禁（Stop hook）** | 无 | 内置 | 未包含 |
| **会话恢复** | 手动 | `--resume` | 未包含 |
| **Windows 测试** | 不稳定 | 未知 | Windows 11 + Git Bash 实测通过 |
| **双语支持** | 否 | 仅英文 | 中文 + 英文触发词 |
| **代码量** | 0 | ~3000 行 (TS/MJS) | ~300 行 (Bash) |

### codex-delegate 的优势

**1. Git 安全 —— 同类唯一**

每次 Codex 调用都被安全网包裹：
- 预检：检测脏工作树 → 自动 stash 并打时间戳标签
- 记录 HEAD 用于回滚参考
- 后检：输出 `git diff --stat`、新增文件、回滚命令
- 中断时：`trap` 确保打印 stash 警告，清理临时文件

**2. 测试修复循环 —— 专属工作流**

`run-codex-testfix.sh` 自动化了最烦人的调试循环：
```
第 1 轮：跑测试 → 4 个失败 → Codex 修复 → 重跑
第 2 轮：还剩 1 个失败 → Codex 修复 → 重跑
第 3 轮：全部通过 ✓
```
没有其他 Codex 插件把这作为一等公民功能。

**3. 协作模式 —— Claude 始终掌控**

| 模式 | 流程 | 适用场景 |
|------|------|---------|
| **谨慎**（默认） | Codex 提方案（只读） → Claude 审查 → Codex 执行 | 多文件变更、不熟悉的代码 |
| **快速** | Codex 直接执行 | 简单重命名、格式化 |
| **诊断** | Codex 只读分析，Claude 决策 | Bug 排查 |

官方插件有 "rescue"（甩手委派）。codex-delegate 有**执行前审查检查点**。

**4. 轻量可移植**

```
codex-delegate/          openai/codex-plugin-cc/
├── scripts/ (3 个文件)  ├── scripts/lib/ (15 个文件)
├── skills/ (1 个 SKILL) ├── agents/ hooks/ prompts/ schemas/
├── commands/ (1 个命令)  ├── commands/ (7 个命令)
└── 共 300 行             └── ~3000 行 + npm 依赖
```

### 官方插件的优势

- **后台任务管理**：`/codex:status`、`/codex:result`、`/codex:cancel` —— 完整的任务生命周期
- **对抗性审查**：魔鬼代言人模式，质疑设计决策
- **审查门禁**：Stop hook 阻止 Claude 完成，直到 Codex 审批通过
- **会话恢复**：`--resume` 继续之前的 Codex 线程

**选 codex-delegate**：要安全、简洁、测试修复自动化。
**选官方插件**：要后台任务控制和审查门禁。

---

## 功能

| 功能 | 说明 |
|------|------|
| **智能委派** | Claude 通过 SKILL.md 学习何时委派 —— 不是每个任务都交给 Codex |
| **Git 安全网** | 自动 stash、HEAD 记录、diff 输出、回滚命令、中断保护 |
| **测试修复循环** | 自动化 运行 → 修复 → 重跑 循环，可配置最大轮数 |
| **交叉审查** | Codex 独立审查 Claude 的代码，检查 bug、安全、性能问题 |
| **Bug 诊断** | 只读分析模式 —— Codex 排查，Claude 决策 |
| **超时保护** | 可配置 `CODEX_TIMEOUT`（默认 300 秒）防止无限挂起 |
| **双触发方式** | 自然语言（"交给 codex"）或斜杠命令（`/codex <任务>`） |
| **双语支持** | 中文 + 英文触发词和文档 |

---

## 安装

### 快速开始

```bash
# 1. 注册 marketplace
/plugin marketplace add Rubbish0-A/codex-delegate

# 2. 安装插件
/plugin install codex-delegate@codex-delegate

# 3. 重载插件
/reload-plugins
```

### 前置条件

- 已安装 [Codex CLI](https://github.com/openai/codex)（`npm install -g @openai/codex`）
- 已在 Codex 中配置 OpenAI API key 或 ChatGPT 订阅
- Git（用于安全功能）

> 完整安装指南（含 API 代理配置）：[`skills/delegate-to-codex/references/setup-guide.md`](skills/delegate-to-codex/references/setup-guide.md)

---

## 使用方法

### 自然语言触发

```
"把这个登录接口的参数校验交给 codex 实现"
"让 codex 修一下 src/auth/ 下面的测试"
"用 codex review 一下当前的改动"
"codex 查一下这个接口为什么返回 500"
```

### 斜杠命令

```bash
/codex implement user registration with input validation
/codex fix the failing tests in src/auth/
/codex review
/codex review check for SQL injection vulnerabilities
```

### 工作流示例

**交叉审查（Claude 写 → Codex 审）**
```
你："帮我实现用户注册接口"
Claude：[写完代码]
Claude："代码写完了，要不要让 Codex 做个交叉审查？"
你："好"
→ Codex 报告 2 个 HIGH + 3 个 MEDIUM 问题
→ Claude 逐条分析，和你讨论哪些要改
```

**测试修复循环**
```
你："测试跑不过，让 codex 修一下"
→ 第 1 轮：4 个失败 → Codex 修复 → 重跑
→ 第 2 轮：还剩 1 个失败 → Codex 修复 → 重跑
→ 第 3 轮：全部通过 ✓
→ Claude 审查修复内容后向你汇报
```

**Bug 诊断（只读）**
```
你："这个接口返回 500，让 codex 查一下"
→ Codex 只读分析代码，不改任何文件
→ 报告：根因在 db.query() 未处理 null，建议 3 种修复方案
→ Claude 评估方案，和你讨论用哪个
```

---

## 架构

```
┌──────────────────────────────────────────────┐
│                  用户                          │
│  "交给 codex"  /  /codex <任务>               │
└─────────────────┬────────────────────────────┘
                  │
                  ▼
┌──────────────────────────────────────────────┐
│            Claude（大脑）                      │
│                                               │
│  SKILL.md 教会 Claude：                        │
│  • 何时委派（判断标准）                          │
│  • 如何委派（协作模式）                          │
│  • 冲突防护规则                                 │
│  • 委派后验证流程                               │
└─────────────────┬────────────────────────────┘
                  │ Bash tool
                  ▼
┌──────────────────────────────────────────────┐
│          安全脚本（Bash）                       │
│                                               │
│  预检：                                        │
│  ✓ codex CLI 可用性检查                        │
│  ✓ git stash 未提交变更                        │
│  ✓ 记录 HEAD 用于回滚                          │
│                                               │
│  执行：                                        │
│  ✓ 超时保护 (CODEX_TIMEOUT)                    │
│  ✓ 关闭 stdin (< /dev/null)                   │
│  ✓ 输出捕获 (-o 文件 + stdout)                 │
│                                               │
│  后检：                                        │
│  ✓ git diff --stat                            │
│  ✓ 回滚命令                                    │
│  ✓ stash 恢复提醒                              │
│                                               │
│  中断时：                                       │
│  ✓ trap 清理（临时文件 + stash 警告）            │
└─────────────────┬────────────────────────────┘
                  │
                  ▼
┌──────────────────────────────────────────────┐
│          Codex CLI（双手）                      │
│                                               │
│  codex exec --full-auto --ephemeral          │
│  沙箱执行 (workspace-write)                    │
│  结果回传给 Claude                              │
└──────────────────────────────────────────────┘
```

---

## 配置

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CODEX_TIMEOUT` | `300`（task/review），`600`（testfix） | Codex 进程最大执行秒数 |

### Codex 模型 / 推理强度

编辑 `~/.codex/config.toml`：

```toml
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
```

---

## 插件结构

```
codex-delegate/
├── .claude-plugin/
│   ├── plugin.json              # 插件清单
│   └── marketplace.json         # Marketplace 发现入口
├── commands/
│   └── codex.md                 # /codex 斜杠命令
├── skills/
│   └── delegate-to-codex/
│       ├── SKILL.md             # 核心：教 Claude 委派逻辑
│       └── references/
│           ├── codex-cli-reference.md
│           ├── setup-guide.md
│           └── workflow-patterns.md
├── scripts/
│   ├── run-codex-task.sh        # 任务执行（full-auto / read-only）
│   ├── run-codex-review.sh      # 代码审查
│   └── run-codex-testfix.sh     # 测试修复循环（最多 N 轮）
└── README.md
```

---

## 常见问题

| 问题 | 解决方案 |
|------|---------|
| `[ERROR] codex CLI not found` | `npm install -g @openai/codex` |
| `401 Unauthorized` | 配置 `OPENAI_API_KEY` 或运行 `codex login` |
| Codex 卡在 stdin | v1.4.1+ 已修复（`< /dev/null`） |
| 大项目超时 | 增大超时：`export CODEX_TIMEOUT=600` |
| 插件未加载 | 完成 marketplace 注册后 `/reload-plugins` |
| Codex 改错了文件 | 回滚：`git checkout -- . && git clean -fd` |
| 中断后 stash 丢失 | 检查：`git stash list` —— 自动 stash 带时间戳标签 |

---

## 更新日志

### v1.4.2 (2026-04-14)
- 新增 codex CLI 预检
- 新增 `trap` 清理（临时文件 + 中断时 stash 安全提醒）
- 新增可配置超时（`CODEX_TIMEOUT` 环境变量）
- FLAGS 从字符串改为 bash 数组，安全展开
- codex review 新增 `-o` 输出捕获
- 新增 `SCRIPT_COMPLETED` 标志避免重复 stash 警告

### v1.4.1 (2026-04-14)
- 所有 codex 调用关闭 stdin（`< /dev/null`）防止挂起

### v1.4.0
- 灵活的协作模式（谨慎 / 快速 / 诊断）

### v1.3.0
- 修复插件发现问题，更新安装指南

### v1.2.1
- 优化为轻量、实用、高质量

---

## 许可证

MIT

---

**3 个脚本。300 行代码。零依赖。完整 Git 安全。**

为那些想让 Claude 和 Codex 协作，又不想搞复杂的开发者而生。
