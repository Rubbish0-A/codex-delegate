# codex-delegate

**Claude Code + Codex CLI 智能协作插件** — 让两个 AI 编码代理按需协作，各司其职。

> Claude 负责思考（需求理解、架构设计、代码审查、用户沟通），Codex 负责动手（精确改码、批量重构、测试修复）。  
> 不是替代，不是常驻，而是在明确有价值时按需调用。

---

## 这个插件能做什么

### 核心能力

| 能力 | 说明 |
|------|------|
| **智能判断** | Claude 根据任务特征自动判断是否需要 Codex 介入，不会盲目委派 |
| **精确委派** | 将明确范围的编码任务交给 Codex 非交互执行，结果自动回收 |
| **冲突防护** | 委派前自动 git stash 保护现有改动，委派后自动输出 diff 和回滚信息 |
| **代码审查** | 支持让 Codex 对未提交的改动做独立代码审查 |
| **双触发方式** | 自然语言（"交给 codex"）和斜杠命令（`/codex`）均可触发 |

### 使用场景

```
✅ 适合交给 Codex 的任务
├── 精确的代码微调（Claude 给方向，Codex 精准落刀）
├── 批量/重复性修改（20 个文件同一模式替换）
├── 设计阶段的快速原型验证
├── 迭代式测试修复循环
└── 用户明确指定让 Codex 做的任务

❌ 不适合交给 Codex 的任务
├── 架构设计、方案讨论（Claude 强项）
├── 需要大量上下文理解的复杂任务
├── Claude 自己一步就能搞定的简单改动
└── 涉及密钥、凭证、部署的敏感操作
```

### 协作架构

```
┌─────────────────────────────────────────────────┐
│                   你（用户）                       │
│  "这个批量重构交给 codex"  或  /codex <task>      │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│              Claude（主控大脑）                    │
│                                                   │
│  1. 理解需求，判断是否适合委派                      │
│  2. 准备精确的、有范围的 prompt                     │
│  3. 调用 Codex 执行脚本                            │
│  4. 审查 Codex 的改动                              │
│  5. 向用户汇报结果                                  │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│             Codex CLI（执行双手）                   │
│                                                   │
│  • codex exec --full-auto --ephemeral            │
│  • 在沙箱中执行编码任务                             │
│  • 输出回传给 Claude                               │
└─────────────────────────────────────────────────┘
```

---

## 安装

### 前置条件

| 依赖 | 安装方式 | 验证 |
|------|---------|------|
| **Claude Code CLI** | [官方文档](https://docs.anthropic.com/en/docs/claude-code) | `claude --version` |
| **Codex CLI** | `npm install -g @openai/codex` | `codex --version` |
| **OpenAI API Key** | 见下方配置 | `codex exec --full-auto --ephemeral "echo hello"` |

### 配置 OpenAI API Key

```bash
# 方式一：环境变量（推荐）
# 添加到你的 shell 配置文件（~/.bashrc, ~/.zshrc 等）
export OPENAI_API_KEY="sk-your-key-here"

# 方式二：Codex 配置文件
# 编辑 ~/.codex/config.toml
[auth]
api_key = "sk-your-key-here"

# 方式三：交互式登录
codex login
```

### 安装插件

**第一步：复制插件文件**

```bash
# 克隆仓库
git clone https://github.com/YOUR_USERNAME/codex-delegate.git

# 复制到 Claude Code 插件目录
cp -r codex-delegate/ ~/.claude/plugins/codex-delegate/

# 给脚本加执行权限
chmod +x ~/.claude/plugins/codex-delegate/scripts/run-codex-task.sh
chmod +x ~/.claude/plugins/codex-delegate/scripts/run-codex-review.sh
```

**第二步：注册插件**

编辑 `~/.claude/plugins/installed_plugins.json`，在 `"plugins"` 对象内添加：

```json
"codex-delegate@local": [
  {
    "scope": "user",
    "installPath": "YOUR_HOME_DIR/.claude/plugins/codex-delegate",
    "version": "1.1.0",
    "installedAt": "2026-04-08T00:00:00.000Z",
    "lastUpdated": "2026-04-08T00:00:00.000Z"
  }
]
```

> **注意**：`installPath` 必须是绝对路径。  
> Windows 示例：`C:\\Users\\yourname\\.claude\\plugins\\codex-delegate`  
> macOS/Linux 示例：`/home/yourname/.claude/plugins/codex-delegate`

**第三步：启用插件**

编辑 `~/.claude/settings.json`，在 `"enabledPlugins"` 内添加：

```json
"codex-delegate@local": true
```

**第四步：重启 Claude Code**

开一个新的 Claude Code 会话，插件即可生效。

---

## 使用方式

### 方式一：自然语言触发

在 Claude Code 对话中直接说：

```
"把这个登录接口的参数校验交给 codex 实现"
"让 codex 修一下 src/auth/ 下面的测试"
"用 codex 把所有 userId 重命名为 user_id"
"让 codex review 一下当前的改动"
```

Claude 会自动识别意图并调用 Codex。

### 方式二：斜杠命令

```bash
# 实现功能
/codex implement user registration endpoint with input validation

# 修复 bug
/codex fix the failing tests in src/auth/

# 批量重构
/codex rename all instances of userId to user_id in the models directory

# 代码审查
/codex review
/codex review check for security vulnerabilities and SQL injection
```

### 执行模式

| 模式 | 说明 | 何时使用 |
|------|------|---------|
| `full-auto` | Codex 自动执行，可读写项目文件 | 大多数编码任务（默认） |
| `read-only` | Codex 只读，不修改文件 | 分析、审查、审计 |

### 实际执行流程

```
1. [Claude] 判断任务适合交给 Codex
2. [Claude] 准备精确的 prompt（指定文件、改动内容、约束条件）
3. [Script] Pre-flight 检查：检测 git 状态，自动 stash 未提交改动
4. [Codex]  在沙箱中执行任务（codex exec --full-auto --ephemeral）
5. [Script] Post-flight：输出 Codex 回复 + git diff + 回滚信息
6. [Claude] 审查 Codex 改动，向用户汇报结果
```

---

## 冲突防护机制

Claude 和 Codex 操作**同一个文件系统**，插件通过三层防护避免冲突：

### 第一层：委派前（Pre-flight）

```
✓ 检测当前是否在 git 仓库内
✓ 检查是否有未提交的改动
✓ 如有改动 → 自动 git stash 保护
✓ 记录当前 HEAD commit 用于回滚
```

### 第二层：执行时（Isolation）

```
✓ Codex 在 workspace-write 沙箱中执行
✓ Claude 的 SKILL.md 要求范围隔离：
  - 给 Codex 指定明确的文件范围
  - 避免委派 Claude 正在编辑的文件
  - 委派前先写完所有待处理的编辑
```

### 第三层：委派后（Post-flight）

```
✓ 自动输出 git diff --stat 显示改动文件
✓ 列出新增的 untracked 文件
✓ 提供一键回滚命令
✓ 提示 stash 恢复步骤
```

### 回滚操作

如果 Codex 改错了：

```bash
# 撤销所有 Codex 改动
git checkout -- . && git clean -fd

# 如果之前有 stash，恢复 Claude 的改动
git stash pop
```

---

## 插件结构

```
codex-delegate/
├── .claude-plugin/
│   └── plugin.json                     # 插件清单
├── commands/
│   └── codex.md                        # /codex 斜杠命令定义
├── skills/
│   └── delegate-to-codex/
│       ├── SKILL.md                    # 核心：教 Claude 何时/如何委派
│       └── references/
│           ├── codex-cli-reference.md  # Codex CLI 详细参数参考
│           └── setup-guide.md          # 安装配置指南
├── scripts/
│   ├── run-codex-task.sh               # 执行编码任务的封装脚本
│   └── run-codex-review.sh             # 执行代码审查的封装脚本
└── README.md
```

### 各组件职责

| 组件 | 类型 | 职责 |
|------|------|------|
| `SKILL.md` | Skill | 教 Claude 判断标准、执行流程、冲突防护规则 |
| `codex.md` | Command | 提供 `/codex` 斜杠命令入口 |
| `run-codex-task.sh` | Script | 封装 `codex exec`，含 pre/post-flight 安全检查 |
| `run-codex-review.sh` | Script | 封装 `codex review`，针对代码审查场景 |
| `codex-cli-reference.md` | Reference | Codex CLI 参数速查，Claude 按需加载 |
| `setup-guide.md` | Reference | 新用户安装配置指南 |

---

## 升级与迭代

### 如何升级插件

```bash
# 拉取最新版本
cd path/to/codex-delegate
git pull origin main

# 复制到插件目录（覆盖）
cp -r . ~/.claude/plugins/codex-delegate/

# 重新加权限
chmod +x ~/.claude/plugins/codex-delegate/scripts/*.sh

# 重启 Claude Code 生效
```

### 如何自定义迭代

这个插件的核心是 **SKILL.md** — 它定义了 Claude 的判断逻辑。你可以按自己的需求修改：

#### 调整判断标准

编辑 `skills/delegate-to-codex/SKILL.md` 中的 "Judgment Criteria" 部分：

```markdown
# 例：添加一个新的委派条件
7. **代码格式化** — 大规模代码风格统一任务交给 Codex 更高效

# 例：排除某类任务
- 不要委派数据库迁移相关的改动（需要人工审查）
```

#### 修改默认执行模式

编辑 `scripts/run-codex-task.sh` 中的 MODE 处理逻辑：

```bash
# 例：添加一个新模式
dangerous)
  FLAGS="$FLAGS --full-auto -s danger-full-access"
  ;;
```

#### 指定 Codex 模型

编辑脚本，在 `codex exec` 调用中添加 `-m` 参数：

```bash
# 例：强制使用 o3 模型
codex exec $FLAGS -m o3 -C "$WORKDIR" -o "$OUTPUT_FILE" "$PROMPT"
```

或在 Codex 全局配置 `~/.codex/config.toml` 中设置：

```toml
model = "o3"
```

#### 添加新脚本

在 `scripts/` 目录下添加新的封装脚本，然后在 SKILL.md 中引用：

```bash
# 例：添加一个专门跑测试的脚本
scripts/run-codex-test.sh
```

### 迭代建议

| 迭代方向 | 做法 |
|---------|------|
| **调优判断逻辑** | 使用一段时间后，根据实际体验修改 SKILL.md 的判断条件 |
| **添加 Codex 模型选择** | 在脚本中支持 `-m` 参数，不同任务用不同模型 |
| **增加任务类型** | 添加专门的测试、文档生成等脚本 |
| **优化 prompt 模板** | 在 SKILL.md 中积累好用的 prompt 模式 |
| **添加日志** | 在脚本中记录每次委派的任务、结果、耗时 |

---

## 常见问题

| 问题 | 解决方案 |
|------|---------|
| `codex: command not found` | 安装 Codex CLI：`npm install -g @openai/codex` |
| `401 Unauthorized` | 配置 `OPENAI_API_KEY` 环境变量 |
| `Not inside a trusted directory` | 确保在 git 仓库内运行，或脚本会自动添加 `--skip-git-repo-check` |
| 插件未加载 | 检查 `installed_plugins.json` 路径是否正确且为绝对路径 |
| `/codex` 命令未识别 | 确认 `commands/codex.md` 存在，重启 Claude Code |
| 脚本权限错误 | `chmod +x ~/.claude/plugins/codex-delegate/scripts/*.sh` |
| Codex 改错了文件 | 用输出中的回滚命令：`git checkout -- . && git clean -fd` |

---

## 技术细节

- **Codex 执行模式**：使用 `codex exec`（非交互模式），不依赖终端交互
- **沙箱**：默认 `workspace-write`（只能写项目目录），不会影响系统文件
- **会话管理**：`--ephemeral` 标志确保 Codex 不持久化会话，干净无残留
- **输出捕获**：通过 `-o` 标志将 Codex 最终回复写入临时文件，配合 stdout 提供双通道输出

## License

MIT

---

**Made with Claude Code + Codex CLI** — 让两个 AI 代理协作，比单独使用任何一个都更高效。
