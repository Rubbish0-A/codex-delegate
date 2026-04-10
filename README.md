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
| **交叉审查** | Claude 写完代码后，Codex 做独立 review，报告问题和建议 |
| **测试修复循环** | Codex 跑测试 → 修 bug → 再跑，最多 3 轮，超过交回 Claude |
| **Bug 诊断** | Codex 只读分析代码，定位 bug 根因，给出修复方案供 Claude 决策 |
| **双触发方式** | 自然语言（"交给 codex"）和斜杠命令（`/codex`）均可触发 |

### 使用场景

```
✅ 适合交给 Codex 的任务
├── 交叉审查：Claude 写完代码 → Codex review 检查 bug 和安全问题
├── 测试修复：跑测试 → 修失败 → 再跑（最多 3 轮自动循环）
├── Bug 诊断：只读分析代码，定位根因，给出修复方案
├── 精确的代码微调（Claude 给方向，Codex 精准落刀）
├── 批量/重复性修改（20 个文件同一模式替换）
├── 设计阶段的快速原型验证
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

### 安装步骤

Claude Code 插件需要注册为 marketplace 才能被正确发现和加载。

> 完整的 6 步安装指南（含 API Key 配置、代理配置、排障）请参考  
> **[`skills/delegate-to-codex/references/setup-guide.md`](skills/delegate-to-codex/references/setup-guide.md)**

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

### 方式二：开发流程中的协作（v1.2 新增）

Claude 会在开发流程的关键节点主动建议 Codex 介入：

```
场景一：交叉审查（Claude 写完代码后）
────────────────────────────────────
你：帮我实现用户注册接口
Claude：[写完代码]
Claude："代码写完了，要不要让 Codex 做个交叉审查？"
你："好"
→ Codex review，报告 2 个 HIGH + 3 个 MEDIUM 问题
→ Claude 逐条分析，和你讨论哪些要改

场景二：测试修复循环
────────────────────────────────────
你："测试跑不过，让 codex 修一下"
→ Codex 跑测试 → 发现 4 个失败 → 修复 → 再跑
→ 第 2 轮：还剩 1 个失败 → 修复 → 再跑
→ 第 3 轮：全部通过 ✓
→ Claude review Codex 的修复，确认质量后告诉你

场景三：Bug 诊断（只读分析）
────────────────────────────────────
你："这个接口返回 500，让 codex 查一下"
→ Codex 只读分析代码，不改任何文件
→ 报告：根因在 db.query() 未处理 null，建议 3 种修复方案
→ Claude 评估方案，和你讨论用哪个
```

### 方式三：斜杠命令

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

## 冲突防护

Claude 和 Codex 操作**同一个文件系统**，脚本内置三层自动防护：

| 阶段 | 防护措施 |
|------|---------|
| **委派前** | 检测 git 状态 → 自动 stash 未提交改动 → 记录 HEAD 用于回滚 |
| **执行中** | Codex 在 workspace-write 沙箱运行；Claude 做范围隔离避免文件冲突 |
| **委派后** | 自动输出 `git diff --stat` + 回滚命令 + stash 恢复提醒 |

回滚：`git checkout -- . && git clean -fd`，恢复 stash：`git stash pop`

---

## 插件结构

```
codex-delegate/
├── .claude-plugin/
│   ├── plugin.json                     # 插件清单
│   └── marketplace.json                # marketplace 发现入口
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
│   ├── run-codex-review.sh             # 执行代码审查的封装脚本
│   └── run-codex-testfix.sh            # 测试修复循环脚本（最多 3 轮）
└── README.md
```

### 各组件职责

| 组件 | 类型 | 职责 |
|------|------|------|
| `SKILL.md` | Skill | 教 Claude 判断标准、执行流程、冲突防护规则 |
| `codex.md` | Command | 提供 `/codex` 斜杠命令入口 |
| `run-codex-task.sh` | Script | 封装 `codex exec`，含 pre/post-flight 安全检查 |
| `run-codex-review.sh` | Script | 封装 `codex review`，针对代码审查场景 |
| `run-codex-testfix.sh` | Script | 测试修复循环：跑测试→修bug→再跑，最多 3 轮 |
| `workflow-patterns.md` | Reference | 4 种开发流程模式的详细 prompt 模板和决策树 |
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
| 404 / API 代理不兼容 | 参考 [setup-guide.md](skills/delegate-to-codex/references/setup-guide.md) 的代理配置章节 |
| `Not inside a trusted directory` | 确保在 git 仓库内运行，或脚本会自动添加 `--skip-git-repo-check` |
| 插件未加载 | 需要完成 marketplace 注册，参考 setup-guide.md 的 6 步安装 |
| `/codex` 命令未识别 | 确认 `commands/codex.md` 存在，重启 Claude Code |
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
