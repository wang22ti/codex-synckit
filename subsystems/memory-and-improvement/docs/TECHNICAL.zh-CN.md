# memory-and-improvement 技术参考

[概览](../README.zh-CN.md) · [English](TECHNICAL.md)

这是一个仅供 Codex 使用的记忆技能，用于记录项目内记忆、跨项目的全局记忆，以及那些应当升级为独立 Codex 技能的可复用流程。

这份参考面向维护者，说明当前实现的架构、预期工作流、主要脚本、自动化模型和运行边界。

如果需要看紧凑、可作为维护基准的规则参考，请看
[references/maintainer-reference.md](../references/maintainer-reference.md)。

## 这个技能的用途

这个技能为 Codex 提供了一种结构化的记忆方式，用来保存：

- 仓库特定的事实、约定、失败案例和经验教训
- 跨项目的事实、偏好、历史记录和持久化工作流经验
- 重要到足以成为真正 Codex 技能的可复用流程

它围绕三层记忆设计：

- 项目记忆：默认位于检测到的仓库根目录下的 `./.learnings/`
- 全局记忆：默认位于 `$HOME/global-memory/namespaces/<namespace>/.learnings/`
- 技能：默认位于 `$HOME/.codex/skills/`

核心思路是：

- 事实和经验保留在记忆中
- 可复用流程沉淀为技能
- 全局记忆保存跨项目的持久知识
- 项目记忆保存仓库特定知识
- 仓库本地的 agent 指令应留在 `AGENTS.md`，而不是项目记忆中

记录优先召回，提升优先精度。
用了这个 skill 之后，每次回复前都先做一次显式的 recall decision。纯闲聊可以按判断跳过，但主会话里仍要保留清晰的 safe-skip 判断，不必为了这件事专门对用户输出一句“这轮不需要 recall”。

## 闭环运行模型

期望中的运行模型是：

1. Recall
   每次回复前先做显式的 recall decision。
   要么从最小相关 memory 层开始回忆，要么在内部做出 safe-skip 判断，说明为什么这次 turn 足够简单或自包含，可以安全跳过 recall。
2. Reason
   判断当前召回层是否已经足够，还是需要继续深入读取。
   可以用这份 checklist：
   当前 recall 到了什么相关 memory？
   如果这次跳过了 recall，为什么这个跳过是安全的？
   这一层够不够安全地答复或执行？
   如果不够，下一步应该去 `review-memory.sh`、`search-memory.sh`、结构化 factual file，还是 raw `.learnings/*.md`？
   repo 约定、之前的失败模式，或者这次 safe-skip 判断，会不会在动手前改变计划？
   推荐升级规则：
   summary 命中且已足够 -> 直接继续
   summary 命中但细节不够 -> 打开 `review-memory.sh` 或相关 structured factual file
   summary 没命中但任务明显依赖历史/偏好/失败/纠正 -> 用 `search-memory.sh`
   需要 chronology / evidence / debugging context / 精确 correction history -> 打开 raw `.learnings/*.md`
3. Respond/Act
   在遵守召回到的约束和 repo 约定的前提下答复或执行。
4. Reflect
   在有意义的工作产出之后，先做显式的 reflect decision。
   如果本轮产生了有意义的工作产出，应在最终回答前运行结构化 reflect check。`UserPromptSubmit` hook 只负责提醒主会话，不会自动运行反思。

严格版运行标准：

- 在主会话内部，recall 不能静默跳过
- 有意义的工作产出之后不能静默省略 reflect
- 不要为了满足流程而硬塞用户可见的“这轮不需要 recall/reflect”提示；只有当这个判断会影响答复、计划、audit 状态或 logging 结果时才说出来
- hook 和 helper script 只能触发或辅助，不能替主会话做判断

对这个仓库来说，`memory-and-improvement` 的 workflow、docs、specs、roadmap-driven implementation 和 diagram 编辑都属于 audit-sensitive work。在运行时规则和用户许可允许的情况下，repo 里的约定是要在任务完成或进入下一阶段前运行一次 audit-focused subagent；如果做不到，也要显式说明这个缺口，而不是默认把规则弱化掉。
这条 audit 约定应该在开始编辑前就进入计划，而不是等收尾时才想起来。

这个仓库里的执行边界可以这样看：

- normal execution：普通答复、memory review/logging/search，以及不会改变 `memory-and-improvement` workflow/docs/specs/roadmap/diagrams 行为的仓库修改
- audit-aware execution：会改变 `memory-and-improvement` workflow/docs/specs/roadmap/diagram 行为、skill contract 或 maintainer guidance 的 substantial work

一旦属于 audit-aware execution，就应该在动手前的 plan 或 commentary 里明确说出来，把 audit step 保持在作用域里；如果因为运行时规则或用户许可没法跑 subagent，也要把这个 unmet audit requirement 说清楚。

当前需要如实说明的一点：

- 专门的 recall helper 现在已经有了，也就是 `scripts/recall/recall-memory.sh`
- 专门的 reflect helper 现在已经有了，也就是 `scripts/recall/reflect-memory.sh`
- Windows CodexKit 适配器会在 `SessionStart` 注入运行时 guidance；其 `UserPromptSubmit` 适配器只给出 recall 提醒，并在明确的身份提示下按需注入 `user-profile/SUMMARY.md`；独立 Bash 适配器才额外包含 reflect 提醒
- `suggest-promotions.sh` 和 `reflect-memory.sh` 都是 advisory helper，而 nightly organize/writeback 仍然只是 supportive distillation，不是 authoritative promotion
- `scripts/maintenance/update-skill-policy.sh` 是唯一允许自动改写 `SKILL.md` 的路径，而且只允许改受管的 routing-strategy 区块，不会改整份 skill 本体

## 快速上手

如果你是第一次使用这套系统，不需要先理解所有分层。

先记住这个最小路由规则：

- 仓库特定的事实、约定、失败或请求 -> 项目记忆
- 跨项目的事实、偏好、历史或持久经验 -> 全局记忆
- 可复用流程 -> 技能
- 不确定要不要升级 -> 先留在原始 `.learnings/*.md`
- 不确定该记到哪一层 -> 默认先记到项目记忆，除非你已经明确知道它下周在别的仓库里也会有用
- 不确定这件事到底值不值得记 -> 通常也可以先放进 `.learnings/*.md`

正常使用时，由 Hook guidance 提醒当前 Codex 会话选择合适的辅助脚本。
快捷脚本和核心脚本都是内部集成入口；只有维护、诊断、恢复，或没有托管 Hook
适配器的独立安装，才需要直接运行。

## 不确定时怎么办

这套系统里，最安全的默认策略不是“多升级”，而是：

- 先把内容记到原始 `.learnings/*.md`
- 如果连该记到项目还是全局都不确定，默认先记到项目侧的 raw history
- 描述尽量保持简单、事实化
- 如果之后反复出现，再用 `suggest-promotions.sh` 看建议
- 记录尽量宽松，升级尽量保守

在这套系统里，不升级是正常结果。很多内容最终停留在 raw history 里，本来就是对的。

## 常见例子

- “This repo stores fixtures in `tests/fixtures/`” -> 项目记忆
- “The user prefers concise rebuttal drafts” -> 全局记忆
- “这次排错暴露了一个本地集成失败” -> 原始项目 `.learnings/*.md`
- “这套流程会在多个仓库里重复使用” -> 考虑做成技能
- “这个 PDF 或图文件之后还需要被重新发现” -> 记到对应层的 asset index

## 为什么要做成这样

这套系统优化的重点是 knowledge governance，而不只是“用起来顺手”。

和更轻量的 memory 系统相比，它的主要区别是：

- 它会在 `project`、`global`、`skill` 三层之间显式路由，而不是把所有东西都扔进一个平面记忆仓库
- 它把短加载提示、规范化 factual files、按时间积累的 learnings、以及 durable artifacts 分开治理
- 它坚持由主会话做最终决策，从而避免低价值、带噪音的 session 残留把 memory 仓库灌满
- 它偏向 markdown、shell 和显式索引，因此整体更可检查、可 grep，也更容易人工修复

落到实际使用上，这意味着：

- 和 Claude 风格的 memory 相比，这套系统仍然更重，但比早期版本更容易维护，因为稳定策略、快捷入口和漂移检查已经更集中
- 和 OpenClaw 风格的 retrieval-first memory 相比，这套系统自动化程度更低，但通常噪音更少、promotion 边界更明确，也更容易作为分层档案来治理
- 和简单笔记或扁平长期记忆文件相比，这套系统维护成本更高，但更擅长把 facts、history、procedures 和 assets 分开

如果和 Claude 风格 memory 进一步对比，当前版本更偏向显式治理：

- Claude 风格系统在轻量项目偏好和日常自动复用上仍然更顺手
- 这套系统更适合维护者希望把路由边界、factual files、原始时间线和 artifact index 明确分开的场景
- 这轮版本也把一部分维护负担收敛了：稳定策略集中到 `references/maintainer-reference.md`，快捷入口集中到 `scripts/shortcuts/`，并增加了 `scripts/tests/docs-consistency-test.sh`

如果和 OpenClaw 风格 memory 对比，当前版本仍然是在做相反取舍：

- OpenClaw 风格系统在模糊召回和 retrieval-first 工作流上依然更强
- 这套系统更适合想要低噪音、可检查的 memory store，并且希望把 `SUMMARY.md`、factual files、原始 `.learnings/*.md` 和 asset index 看成不同层的场景
- 当前版本对 artifact 边界也更明确：project asset 在 `.learnings/assets/INDEX.md`，global namespace asset 在 `assets/INDEX.md`

这套系统最强的地方：

- 长期研究或项目记忆
- 跨项目的事实档案
- 需要把 `SUMMARY.md`、structured factual files、原始历史和 assets 区分对待的场景
- 正确性、可审计性和显式边界比低摩擦记录更重要的工作流

它相对较弱的地方：

- 随意、低风险的日常记忆
- 缺少结构提示时的模糊召回
- 用户希望系统自动记住一切、且几乎不想维护的场景

### 对比表

| 维度 | 这套系统 | Claude 风格 memory | OpenClaw 风格 memory | 简单笔记 / 扁平 memory |
|---|---|---|---|---|
| 核心哲学 | governance-first | convenience-first | retrieval-first | capture-first |
| 写入路径 | 主会话显式决策 | 更轻、更自动 | 偏日志化 / agent 驱动 | 完全手工 |
| 噪音控制 | 高 | 中 | 低到中 | 取决于用户 |
| 结构层次 | 高 | 中 | 中 | 低 |
| 模糊召回 | 中 | 中 | 高 | 低 |
| 可审计性 | 高 | 中 | 中 | 高 |
| 跨项目治理 | 高 | 中到高 | 中 | 低 |
| 工件处理 | 高 | 低到中 | 取决于实现 | 低 |
| 上手成本 | 高 | 低 | 中 | 低 |
| 维护成本 | 中 | 低 | 中 | 低 |
| 最适合场景 | 研究 / 长期知识治理 | 通用工程协作 | 长时 agent 检索 | 个人临时记忆 |

### 和 Agent-Memory 研究脉络的关系

上面的对比主要还是产品风格和工作流风格的对比。
如果放到 agent-memory 文献里看，这个 skill 做的是一件更窄、也更工程化的事情：
它不是通用 autonomous agent architecture，不是 social simulator，也不是 context-window manager。
它更像是一个面向真实 coding / research session 的、由 maintainer 显式治理的记忆层。

它和这些工作的高层相似点大概是：

- 和 `Inner Monologue`、`ReAct`、`Reflexion` 一样，都不是一次性 prompt，而是闭环
- 和 `Generative Agents` 一样，都区分 raw experiences 和更高层的 reflections / summaries
- 和 `MemoryBank`、`MemGPT` 一样，都把 memory 当成持久资源，而不只是当前上下文里的 prompt 文本
- 和 `Voyager` 一样，都认为可复用 procedure 不应该永远停留在平面笔记里，而应该进入 skill-like library

但这套 skill 的主设计目标不一样：

- 上面那些工作大多在优化 autonomous task performance、believable behavior、adaptation，或者 context scaling
- 这套 skill 优化的是 governance、inspectability、promotion discipline，以及 `project` / `global` / `skill` 三层 scope routing

和这些论文/系统相比，这套 skill 主要强在：

- repo-local memory、cross-project memory 和 reusable procedure 之间有显式路由边界
- 默认走 summary-first progressive loading，而不是总是检索或回放所有内容
- 用 markdown 做持久化，便于 grep、检查和人工修复
- promotion 规则明确区分 raw history、summaries、factual files、assets 和 skills
- 整个系统是 human-auditable 的，主会话始终是最终决策者

它的弱点也正好是这些优点的反面：

- 相比通过 trial-and-error 自主学习的 agent architecture，它自动性更弱
- 相比 retrieval-first 或 paging-first 系统，它在 fuzzy recall 和动态 context packing 上更弱
- 它不追求 believable social agent，也不追求 embodied exploration
- 它对 maintainer 的要求更高，因为 capture、promotion 和 policy boundary 都是显式的

### 和具体工作的对比

| 工作 | 那个工作主要优化什么 | 这套 skill 有什么不同 | 这套 skill 更强在哪 | 这套 skill 更弱在哪 |
|---|---|---|---|---|
| [Inner Monologue](https://arxiv.org/abs/2207.05608) | 面向 embodied planning / robotics 的闭环语言反馈 | 这套 skill 也有闭环，但目标是 repo memory governance，不是在线机器人控制 | 持久化更清楚，路由更显式，历史更可检查 | 在实时 embodied feedback 和控制上明显更弱 |
| [ReAct](https://arxiv.org/abs/2210.03629) | 把 reasoning 和 acting 交错起来解决任务 | 这套 skill 在 loop 外又加了持久记忆层和 promotion 规则 | 长期记忆治理和可审计性更强 | 对单次任务执行没那么轻，action-centered 程度也更低 |
| [Reflexion](https://arxiv.org/abs/2303.11366) | 用 verbal reinforcement 和 episodic memory 在多轮尝试中改进表现 | 这套 skill 里的 reflect 更像受治理的持久记忆工作，而不主要是 reward-improvement 机制 | 噪音更低，更易人工检查，也更贴合 repo 约束 | 自主自我改进速度和跨 trial 适应能力更弱 |
| [Generative Agents](https://arxiv.org/abs/2304.03442) | 通过 observation / planning / reflection 生成可信的人类样行为 | 这套 skill 借用了 raw memory 与 reflection 的区分，但目标是 coding / research 维护，不是模拟社会 | scope 控制、artifact indexing 和可维护性更强 | 不适合做 believable social simulation，也不做 autonomous daily planning |
| [MemoryBank](https://arxiv.org/abs/2305.10250) | 在 companion-style dialogue 中做长期用户记忆和 personality adaptation | 这套 skill 更少做 user modeling，更强调 project/global memory 的治理 | 边界更清楚，promotion 更克制，也能把 procedure 升为 skill | personalization、empathy adaptation 和 forgetting-style 调节更弱 |
| [Voyager](https://arxiv.org/abs/2305.16291) | 通过自动 curriculum 和 executable skill library 做开放式 lifelong learning | 这套 skill 也会把可复用 procedure 升成 skill，但不会自主探索或自我设 curriculum | human oversight 更强，更贴合 repo 工作，也更适合做档案 | 在开放式学习和自主技能获取上明显更弱 |
| [MemGPT](https://arxiv.org/abs/2310.08560) | 通过 paging 和 interrupts 在固定上下文窗口上做层级记忆管理 | 这套 skill 的层主要是语义层和治理层，而不是给上下文扩容的 virtual-memory tier | 可检查的 archive 设计和 promotion policy 更强 | 自动 context packing、paging 和超长上下文任务能力更弱 |

### 统一研究对比总表

| 系统 | memory unit | update rule | retrieval policy | autonomy style | governance style | best-fit domain |
|---|---|---|---|---|---|---|
| 这套 skill | raw learnings、summaries、factual files、assets、skills | 显式 capture；保守 promotion；可复用 procedure 升为 skill | 默认 summary-first progressive loading，不够时再逐层深入 | human-in-the-loop coding assistant workflow | maintainer-governed、scope-routed、audit-aware | 需要持久 project/global memory 的 coding 和 research session |
| [Inner Monologue](https://arxiv.org/abs/2207.05608) | 与环境交互绑定的连续语言反馈 | 在动作-观察闭环中持续更新 | 主要依赖当前闭环状态和环境反馈 | embodied closed-loop acting | 偏 task-policy | robotics 和 embodied planning |
| [ReAct](https://arxiv.org/abs/2210.03629) | 交错出现的 reasoning traces 和 actions | 在任务执行过程中逐步更新 | 在 acting 过程中按需访问外部信息 | task-solving agent loop | 偏 prompt/procedure | question answering 和 interactive decision making |
| [Reflexion](https://arxiv.org/abs/2303.11366) | 来自过往尝试的 reflective verbal episodes | 根据成功/失败信号在多轮尝试后追加 reflection | 在后续尝试中复用以往 reflection | self-improving trial loop | 偏 performance-improvement | 重复任务求解和 agent 改进 |
| [Generative Agents](https://arxiv.org/abs/2304.03442) | 自然语言 memories、reflections、plans | 累积 observations，综合 reflections，再推导 plans | 按 relevance、recency、importance 检索 | semi-autonomous social simulation | 偏 behavior-simulation | believable social agents 和日常行为模拟 |
| [MemoryBank](https://arxiv.org/abs/2305.10250) | 对话记忆和类似 user profile 的长期痕迹 | 从对话中写入记忆，并带有 forgetting-style 动态 | 检索与当前对话和 persona 相关的记忆 | conversational adaptation | 偏 user-model | 长期个性化对话 |
| [Voyager](https://arxiv.org/abs/2305.16291) | executable skills、curriculum history、environment feedback | 在开放式探索中不断增加 skills 和 curriculum knowledge | 为当前 embodied task 检索相关 skills | autonomous exploration and lifelong learning | 偏 skill-library growth | 开放式 embodied agent |
| [MemGPT](https://arxiv.org/abs/2310.08560) | 分层上下文 tier 和类似 virtual memory 的缓冲区 | 通过受控 paging 在不同 memory tier 之间搬运信息 | 把合适的信息分页调入当前 active context window | context-managed assistant loop | 偏 system/runtime | 长上下文聊天和文档分析 |

这张表可以把差异压缩成一句话：

- 大多数这些系统主要优化 autonomous adaptation、task performance 或 context management
- 这套 skill 主要优化真实仓库和真实维护者场景里的长期记忆治理
- 所以它赢在 inspectability 和 promotion discipline，也输在 autonomy、fuzzy retrieval 和 automatic context packing

一句话概括可以是：

- `ReAct` 和 `Inner Monologue` 把 loop 显式化
- `Reflexion` 把 verbal self-improvement 显式化
- `Generative Agents` 把 memory synthesis 显式化
- `MemoryBank` 和 `MemGPT` 把 persistent memory management 显式化
- `Voyager` 把 reusable skill accumulation 显式化
- 这套 skill 则把这些想法里适合工程维护的部分抽出来，重定向到 governed coding-session memory，而不是 benchmark agent autonomy

## 维护参考入口

这份 README 是给人看的总览，不是完整的 canonical policy 文档。

当你需要查看下面这些稳定规则时，请优先看 [references/maintainer-reference.md](../references/maintainer-reference.md)：

- 路由边界
- progressive loading 顺序
- promotion 规则
- asset 使用规则
- anti-overpromotion 指南

这样分层的目的就是：

- `SKILL.md` 只保留运行时真正需要的行为说明
- README 保持可读
- 稳定策略语言集中到 maintainer reference，降低多处漂移

## 不要过度升级

不是所有内容都应该被提升。

大多数条目停留在原始 `.learnings/*.md` 里，本身就是一种正常且健康的结果，不代表系统还没整理完。

只有在收益明确时才值得提升：

- 内容是持久的
- 以后会反复用到
- 提升到更高层后，未来加载会明显更省力

如果时间线、证据链、暂时性或局部上下文本身就是价值来源，就应该继续保留在 raw history 里。
asset 也只有在“这个文件本身值得被重新发现”时才需要索引。

## 当前状态

在当前版本中，主要的日常工作流已经基本可用：

- 项目/全局记忆初始化可用
- 项目/全局路由可用
- 回顾与召回可用
- 重复出现的条目可以被回顾，并被保守地提升到 `SUMMARY.md`
- 可以通过 cron 安排夜间维护
- 记忆变更的 git 跟踪可用

当前实现仍然建立在原有的 shell + markdown 基础之上，但闭环重构现在已经落地：

- 现在有一份紧凑的 maintainer reference 承担稳定策略语言
- 闭环 contract 已经在文档和 runtime guidance 里被显式写出
- 之前最弱的两环现在也有了专门入口：recall 和 reflect helper 都已存在
- 薄封装统一收拢到 `scripts/shortcuts/`
- `suggest-promotions.sh` 会降低人工扫描成本，但不会变成自动升级器
- writeback 现在会遵守 advisory promotion + threshold，而不是单靠 recurrence 越过 review
- `scripts/tests/docs-consistency-test.sh` 会帮忙抓文档和脚本之间的轻量漂移
- anti-overpromotion 现在是显式规则，所以很多内容继续留在 raw `.learnings/*.md` 里是正常结果
- asset index 现在按 scope 区分：project asset 放在 `.learnings/assets/INDEX.md`，global namespace asset 放在 `assets/INDEX.md`

系统已经针对许多边界情况进行了加固，尤其包括：

- 项目/全局隔离
- 重复条目更新
- 夜间写回一致性
- git 自动提交的回退身份
- 路径规范化
- 提升与摘要生成

它仍然是一个基于 shell 和 markdown 的系统，因此它不是数据库，也不是完美的事务型存储。但在正常使用场景下，主要工作流已经比较稳健。

## 心智模型

可以把这个系统理解为四层：

1. 路由与路径解析
   决定记忆应该存放在哪里，并强制执行项目/全局隔离。

2. 结构化记录
   将规范化条目写入 markdown 文件，并带有稳定 ID 和重复出现元数据。

3. 召回与提炼
   读取已有记忆，展示简洁的 recall/review 快照，并对符合条件的摘要候选做保守提炼。

4. 自动化与持久化
   Hook、夜间维护和 git 集成会让记忆仓库持续更新，同时明确区分 guidance、advisory tool 和真正的 enforced behavior。

## 目录结构

### 项目记忆

默认情况下：

```text
<repo-root>/
└── .learnings/
    ├── LEARNINGS.md
    ├── ERRORS.md
    ├── FEATURE_REQUESTS.md
    ├── REVIEW.md
    ├── SUMMARY.md
    ├── SUMMARY_CANDIDATES.md
    ├── assets/
    │   └── INDEX.md
    └── .gitignore
```

#### 项目记忆数据流

![.learnings 目录数据流](../assets/learnings-directory-data-flow.svg)

这张图展示了单个项目 `.learnings/` 目录内部的分工关系：

- `LEARNINGS.md`、`ERRORS.md`、`FEATURE_REQUESTS.md` 是原始结构化历史层
- `REVIEW.md` 和 `SUMMARY_CANDIDATES.md` 是维护/建议性质的提炼层
- `SUMMARY.md` 是最高层的 recall 层
- `assets/INDEX.md` 和 `assets/files/` 是工件发现的旁路

它的默认读取顺序仍然是渐进加载：先读 `SUMMARY.md`，再读 `REVIEW.md`，只有任务真的需要时才继续进入更深的 raw history 或具体 asset。

### 全局记忆

默认情况下：

```text
$HOME/global-memory/
├── README.md
└── namespaces/
    ├── research-principle/
    │   ├── README.md
    │   ├── INIT.md
    │   ├── SUMMARY.md
    │   ├── assets/
    │   │   └── INDEX.md
    │   └── .learnings/
    ├── research-ops/
    │   ├── README.md
    │   ├── INIT.md
    │   ├── SUMMARY.md
    │   ├── assets/
    │   │   └── INDEX.md
    │   └── .learnings/
    ├── research-history/
    │   ├── README.md
    │   ├── INIT.md
    │   ├── SUMMARY.md
    │   ├── RECORDS.md
    │   ├── assets/
    │   │   └── INDEX.md
    │   └── .learnings/
    ├── project/
    │   ├── README.md
    │   ├── INIT.md
    │   ├── SUMMARY.md
    │   ├── RECORDS.md
    │   ├── assets/
    │   │   └── INDEX.md
    │   └── .learnings/
    └── user-profile/
        ├── README.md
        ├── INIT.md
        ├── SUMMARY.md
        ├── PROFILE.md
        ├── ACADEMIC_PROFILE.md
        ├── PUBLICATIONS.md
        ├── FUNDING_HISTORY.md
        ├── assets/
        │   └── INDEX.md
        └── .learnings/
```

### 技能

```text
$HOME/.codex/skills/
└── <skill-name>/
    └── SKILL.md
```

## 路由规则

按这个顺序判断：

1. 主要价值是否是一个可复用流程？
2. 如果不是，这件事在下周的另一个仓库里是否仍然有帮助？

据此路由：

- 可复用流程：提取或更新为技能
- 跨项目的持久事实或经验：进入全局记忆
- 仓库特定的事实、约定、失败或请求：进入项目记忆

重要边界：

- 项目记忆用于仓库事实和提炼后的经验，不用于保存仓库本地 agent 指令或 prompt/routing policy
- 仓库本地操作策略应放进 `AGENTS.md` 或显式仓库配置
- 全局记忆可以包含应在会话早期召回的跨项目初始化指导

示例：

- “This repo stores fixtures in `tests/fixtures/`” -> 项目记忆
- “The user prefers concise rebuttal drafts” -> 全局 `research-principle`
- “This API often fails behind a proxy” -> 全局 `research-ops`
- “A lab-level proposal was submitted in 2025 and is still under review” -> 全局 `research-history`
- “Regenerate clients after schema changes, then validate X, Y, Z” -> 技能候选

结构化 factual file 是介于 `SUMMARY.md` 和 `.learnings/` 之间的一层。

- 用 `.learnings/*.md` 记录原始捕获、修正、时间线和证据
- 用 `SUMMARY.md` 放非常短的顶层加载提示
- 用 `PROFILE.md`、`PUBLICATIONS.md`、`RECORDS.md` 这类 factual file 保存会被反复加载的规范化持久事实

默认提升流程：

1. 先把事实记进 `.learnings/*.md`
2. 当它已经明显稳定，或被反复需要时，再提升到 structured factual file
3. 让 `SUMMARY.md` 保持简短，并在合适时指向对应 factual file
4. 把 `suggest-promotions.sh` 和 `SUMMARY_CANDIDATES.md` 当成 advisory review layer，而不是“出现了就必须升级”的信号

如果某个 factual file 本身也需要作为 artifact 被重新发现，也可以把它再索引成 asset。像 `FUNDING_HISTORY.md`、`PUBLICATIONS.md` 这类文件，在后续需要按路径重新打开或引用时就很适合这样做。

## 核心不变式

当前实现尽量维护以下不变式：

- 项目记忆和全局记忆必须隔离
- 比较前必须先对等价路径做规范化
- 全局记忆覆盖路径也必须遵守 `.learnings/` 目录形状
- 重复条目应更新重复统计，而不是产生重复记录
- 重复出现且价值高的条目可以被提升到 `SUMMARY.md`
- 夜间写回后的输出应保持内部一致
- 即使缺少外部 git 身份，git 自动化也应能工作

其中最重要的硬性保护是项目/全局隔离。系统现在会拒绝如下这种重叠或别名等价路径：

- `project/.learnings`
- `project/../project/.learnings`

## 数据模型

系统会写入三类条目：

- learnings
- errors
- feature requests

所有条目都是 markdown 块，并带有：

- 稳定 ID
- 记录时间戳
- 优先级
- 状态
- 自由格式正文
- 重复出现元数据

### Learnings

存储在 `LEARNINGS.md` 中。

典型字段：

- category
- summary
- details
- suggested action

### Errors

存储在 `ERRORS.md` 中。

典型字段：

- summary
- error text
- context
- suggested fix
- reproducible

### Feature Requests

存储在 `FEATURE_REQUESTS.md` 中。

典型字段：

- requested capability
- user context
- complexity estimate
- suggested implementation

### 重复出现元数据

条目可以携带：

- `Pattern-Key`
- `Recurrence-Count`
- `First-Seen`
- `Last-Seen`
- `Recurrence Notes`

记录器会使用 pattern key 来识别同一问题是否在一段时间内反复出现。

## 条目生命周期

一个典型条目会经历以下状态：

1. 以 `pending` 状态记录
2. 可能因重复出现而被更新
3. 可选择性地提升到 `SUMMARY.md`
4. 可能被解决，或被提取为技能

系统当前识别的重要状态包括：

- `pending`
- `in_progress`
- `resolved`
- `wont_fix`
- `promoted_to_summary`
- `promoted_to_skill`

如果一个此前已解决的条目再次出现，记录器会把它重新打开为 `pending`。

## 主要脚本

`scripts/` 目录现在按功能分组，而不再保持扁平结构：

- `scripts/bootstrap/`：初始化和目录/bootstrap 建立
- `scripts/capture/`：写入路径与提取入口
- `scripts/recall/`：summary-first recall、search 和 reflect helper
- `scripts/maintenance/`：提炼、writeback、git 与 nightly maintenance
- `scripts/hooks/`：运行时 hook 入口和只供 hook 使用的辅助脚本
- `scripts/shared/`：供多个脚本组复用的路径和解析器辅助层
- `scripts/shortcuts/`：对核心脚本的薄封装快捷入口
- `scripts/tests/`：运行时行为和文档漂移的回归测试

这样拆分的目的是让运行时表面保持渐进加载：先进入你真正需要的那一组，而不是把整个 `scripts/` 当成一个扁平命名空间。

### `scripts/shared/memory-paths.sh`

共享的路径与策略层。

职责：

- 检测项目根目录
- 解析项目/全局记忆目录
- 校验命名空间
- 规范化路径
- 强制执行项目/全局隔离
- 暴露通用正则和派生路径

它最接近系统中的共享“运行时配置层”。

### `scripts/bootstrap/init-memory.sh`

初始化项目记忆、全局记忆，或同时初始化两者。

用它来创建目录和文件结构，同时不覆盖已有内容。
它还会为项目 `SUMMARY.md` 写入一条 `AGENTS.md` 边界提醒，并为每个全局命名空间创建用于初始化召回的 `INIT.md`。

示例：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/bootstrap/init-memory.sh --scope both --project-root "$PWD"
bash ~/.codex/skills/memory-and-improvement/scripts/bootstrap/init-memory.sh --scope project --project-memory-dir /path/to/.learnings
bash ~/.codex/skills/memory-and-improvement/scripts/bootstrap/init-memory.sh --scope global --global-defaults
```

### `scripts/capture/log-memory.sh`

主写入路径。

职责：

- 校验记录参数
- 在需要时初始化记忆
- 选择目标文件
- 创建 ID
- 通过 `Pattern-Key` 去重
- 原地更新重复统计
- 如果已解决条目再次出现，则重新打开
- 可选地通过 git 自动提交

这是系统中最重要的运行脚本。

### `scripts/recall/review-memory.sh`

用于简洁召回的主读取路径。

职责：

- 展示摘要高亮
- 如果有的话，展示 `REVIEW.md` 高亮
- 只有在更高层缺失或显式要求时，才回退到待处理/最近可见的 raw entry 摘要
- 让默认快照比直接打开 raw `.learnings/*.md` 更轻

主会话在决定是否继续打开更深层 memory 文件之前，可以用它先拿一个简洁快照。

### `scripts/recall/recall-memory.sh`

当前 turn 的专用 summary-first recall 入口。

职责：

- 在主会话已经判断“这轮需要 memory”的前提下，把 `auto` 解析成 `project`、`global` 或 `both` 里最可能相关的最小 scope
- 先展示简洁的 review 快照
- 当提供 query 或请求 deeper recall 时，可选地补充 `search-memory.sh` 输出
- 在保持 recall 轻量的同时，保留继续升级的能力

当主会话想先跑一个统一的 recall 命令，再判断是否需要更深读取时，就应该优先用它。

### `scripts/recall/reflect-memory.sh`

用于有意义工作产出之后的 advisory reflect 入口。是否运行由主会话判断，hook 只负责提醒。

职责：

- 接收一段简短 turn summary，以及可选 details
- 给出 `log_learning`、`log_error`、`log_feature_request`、`consider_summary`、`consider_skill` 或 `no_action` 之类的建议
- 保持 advisory only，不替代主会话的最终判断

当主会话想在收尾前快速判断“这轮要不要记、怎么记、要不要后续 promotion/skill 化”时，就应该优先用它。

### `scripts/maintenance/organize-memory.sh`

生成维护报告：

- `REVIEW.md`
- `SUMMARY_CANDIDATES.md`

它不会修改源条目的状态。它的定位是维护/报告层。

### `scripts/maintenance/writeback-memory.sh`

只把通过 advisory `promote_to_summary` 且同时满足 writeback recurrence threshold 的候选提升到受管理的 `SUMMARY.md` 区块中，同时保留已经 `promoted_to_summary` 的条目。

它是系统中的提炼层，但不是自动升级器。

### `scripts/maintenance/update-skill-policy.sh`

只会改写 `SKILL.md` 中受管的 routing-strategy 区块。

它的职责是有意保持狭窄：只吸收和 routing、source priority、promotion policy 相关的高信号修正，不允许自动重写 skill 其余正文。

### `scripts/maintenance/git-memory.sh`

git 集成层。

支持：

- `init`
- `status`
- `commit`

行为：

- 如果项目记忆位于某个已有仓库内，则尽可能复用该仓库
- 项目记忆也可以初始化为自己的独立仓库
- 全局记忆使用全局记忆树仓库
- 如果没有显式身份，提交身份现在会回退到 `Codex Memory <codex-memory@local>`

### `scripts/maintenance/nightly-maintenance.sh`

自动化入口。

职责：

- 可选写回
- 整理报告
- 可选 git 提交
- 当已登记的 project memory 目录已经不存在时，顺手清理陈旧注册记录

当前顺序是有意设计的：

1. writeback
2. organize
3. git commit

这样既能保证夜间输出的内部一致性，也能让 nightly maintenance 保持 supportive 而不是 authoritative。

### `scripts/maintenance/install-nightly-maintenance.sh`

安装或打印一条 cron 任务。

职责：

- 同时支持固定每日时刻和按时间间隔执行两种模式
- 将生效中的全局记忆上下文固化进 cron 命令
- 固化重复阈值
- 固化 writeback 和 git-autocommit 标志
- 将日志写到全局记忆 git 树之外
- 在 cron 命令中渲染成 `$HOME/...` 风格路径

在 interval 模式下，它会安装一个轻量 cron probe，再由 `interval-maintenance.sh` 判断是否真的到了执行窗口，因此可以支持“每 N 分钟 / 每 N 小时”而不受 cron 24 小时字段边界限制。

project 侧的 nightly 维护不再只依赖一个冻结的 project root。
它会处理所有已经初始化过或通过结构化 logger 写入过、并登记到本地 state 目录里的 project memory 目录。
如果其中某个已登记的 project memory 目录后来被手动删除了，nightly maintenance 现在会自动把这条陈旧 registry 记录清掉。
global 侧的 nightly 维护现在默认会处理 `~/global-memory/namespaces/` 下所有已存在的 namespace；只有在不使用标准 namespace 树时，配置里的 namespace 才作为回退目标。

### `scripts/maintenance/interval-maintenance.sh`

只有在达到设定时间间隔时才真正执行维护。

职责：

- 在本地 state 目录记录最近一次成功运行时间
- 对过早触发的 cron probe 直接跳过
- 即使已经到点，如果自上次成功运行以来没有相关 project/global memory 更新，也直接跳过
- 只有到点时才调用 `nightly-maintenance.sh`
- 真正运行时仍然保持原有的 writeback / organize / git 顺序

### `scripts/hooks/activator.sh`

用于会话启动阶段提示记忆位置与加载规则的 hook 辅助脚本。

默认行为：

- 在 `SessionStart` 时只注入记忆位置和加载规则，不直接注入项目或全局记忆内容
- project memory 始终是当前检测到的 project root 下的 `.learnings/`，即使这个 root 恰好是 `~`
- 如果当前检测到的 project `.learnings/` 已经存在，`SessionStart` 会把它登记到 nightly project maintenance
- 会额外注入一段很短的 memory candidate checklist，提醒主会话哪些内容值得考虑记录
- 用了这个 skill 之后，要求主会话在每次回复前先做 recall step，并且先看最小相关层
- 把主会话引导到闭环 contract，并指出专门的 summary-first recall helper
- 把主会话引导到 substantial turn 之后可用的 advisory reflect helper

`SessionStart` 指南现在也会把默认读取顺序写明确：

1. `INIT.md`
2. `SUMMARY.md`
3. structured factual files
4. `REVIEW.md`
5. 详细 `.learnings/*.md`
6. asset index（`project: .learnings/assets/INDEX.md`; `global: assets/INDEX.md`）
7. 具体 asset 文件

同时也会明确告诉主会话：什么时候应跳过 global memory，什么时候不要直接打开原始 `.learnings/*.md`。

最小回归检查：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/activator-sessionstart-test.sh
```

### `scripts/hooks/hook-utils.sh`

只供 hook 入口使用的共享辅助层。

职责：

- 解析 hook payload 并规范化运行时元数据
- 把 hook 专用的 shell helper 从 `activator.sh` 里拆出来
- 避免在 capture 或 recall 脚本里重复实现 hook plumbing

凡是只属于 hook 内部 plumbing 的小工具，都应放在这里，而不是继续膨胀顶层 hook 入口。

### `scripts/recall/search-memory.sh`

按 staged progressive loading 执行结构化 memory 搜索。

支持：

- `--scope project|global|both`
- `--namespace <name>`
- `--type learning|error|feature_request|asset`
- `--status <status>`
- `--pattern-key <key>`
- `--query <text>`
- `--exhaustive true|false`

优先级顺序：

1. `INIT.md`
2. `SUMMARY.md`
3. 结构化事实文件
4. `REVIEW.md`
5. 原始 `.learnings/*.md`
6. asset index（`project: .learnings/assets/INDEX.md`; `global: assets/INDEX.md`）

默认会在第一个命中的层停下，这样高层已经足够时不会自动继续扫描更深层。
只有在你明确想做全层搜索时，才用 `--exhaustive true`。

最小回归检查：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/search-memory-test.sh
```

### `scripts/tests/recall-memory-test.sh`

针对专用 recall 入口的回归检查。

它会验证：

- recall 是否坚持 summary-first
- `auto` scope 是否正确解析
- 当 summary/review 已经足够时，默认 recall 不会把 raw `.learnings` 直接带出来
- 提供 query 时是否会升级到 search
- 输出顺序是否先 review 再 search

运行方式：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/recall-memory-test.sh
```

### `scripts/tests/reflect-memory-test.sh`

针对 advisory reflect 入口的回归检查。

它会验证：

- correction -> `log_learning`
- failure -> `log_error`
- 可复用 workflow -> `consider_skill`
- 没有 durable information -> `no_action`

运行方式：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/reflect-memory-test.sh
```

### `scripts/maintenance/suggest-promotions.sh`

在不改任何 memory 文件的前提下，给出可能的 promotion 建议。

支持：

- `--scope project|global|both`
- `--namespace <name>`
- `--project-root <path>`
- `--limit <n>`

当前的建议类型有：

- `promote_to_summary`
- `promote_to_factual_file`
- `consider_skill`
- `keep_raw`

当前会参考的来源包括：

- `.learnings/*.md` 中的结构化条目文件
- 存在时读取 `SUMMARY_CANDIDATES.md`
- 把 `REVIEW.md` 当成轻量的 recurrence hint

这个脚本会刻意保持保守，它是 suggestion layer，不是 autopilot：

- 它绝不会直接修改 memory 文件
- 它会默认显式输出 `keep_raw`，让“不提升”继续保持为正常结果
- 在这个阶段，它优先使用确定性 heuristics，而不是 semantic retrieval

`writeback-memory.sh` 也应该只消费既保守又满足 writeback threshold 的 `promote_to_summary` 建议，同时保留已有的 `promoted_to_summary` 条目，而不是单靠 recurrence 直接越过 review。

最小回归检查：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/suggest-promotions-test.sh
bash ~/.codex/skills/memory-and-improvement/scripts/tests/writeback-memory-test.sh
```

### `scripts/maintenance/remove-project-memory.sh`

用于安全地退役一个 project memory 目录。

职责：

- 在删除前先检查目标 project memory
- 预览其中哪些条目可能更适合先保留到 global memory 或 skill
- 如果存在这些候选，默认先停下来，而不是静默删除
- 默认把项目 `.learnings/` 归档到本地 state，而不是立刻硬删除
- 在归档或删除后同步注销对应的 project memory registry 项

这个脚本会刻意保持保守。它把“remove”当成治理动作，而不只是文件系统动作。
如果你在审阅候选后仍想继续，可以加 `--allow-unpromoted-candidates true` 重新运行。

最小回归检查：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/remove-project-memory-test.sh
```

### `scripts/tests/update-skill-policy-test.sh`

用于检查受管 `SKILL.md` routing-strategy 回写路径的回归测试。

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/update-skill-policy-test.sh
```

### `scripts/tests/nightly-maintenance-test.sh`

用于检查 config 驱动的 nightly writeback 路径。

你可以用它确认：

- 不加额外 CLI 参数时，config 也能把 nightly writeback 打开
- 显式 `--writeback false` 仍然会覆盖 config 默认值
- 已登记但已不存在的 project-memory 路径会在 nightly maintenance 中自动清理

运行方式：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/nightly-maintenance-test.sh
```

### `scripts/tests/log-memory-test.sh`

用于检查 `log-memory.sh` 的 config 驱动默认值。

你可以用它确认：

- config 能打开 `git_autocommit`
- 显式 `--git-autocommit false` 仍然会覆盖 config

运行方式：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/log-memory-test.sh
```

### `scripts/capture/log-asset.sh`

把 durable artifact 索引进对应 scope 的 asset index：project memory 用 `.learnings/assets/INDEX.md`，global namespace 用 `assets/INDEX.md`。

它既可用于 PDF、截图、数据快照，也可用于 structured factual file；当某个 factual file 本身需要按 canonical path 被重新发现时，就应该把它也记成 asset。

支持的类型包括：

- `paper_pdf`
- `supplementary_pdf`
- `slide_deck`
- `figure_source`
- `screenshot`
- `report_pdf`
- `dataset_snapshot`
- `structured_fact_file`
- `other`

最小回归检查：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/log-asset-test.sh
```

### `scripts/shortcuts/`

所有薄封装脚本都集中放在一个地方，避免脚本树越长越乱。

当前提供的 shortcuts：

- [`scripts/shortcuts/remember-project-fact.sh`](../scripts/shortcuts/remember-project-fact.sh)
  - 用默认 `--scope project --type learning --category insight` 调 `log-memory.sh`
- [`scripts/shortcuts/remember-global-fact.sh`](../scripts/shortcuts/remember-global-fact.sh)
  - 用默认 `--scope global --type learning --category insight` 调 `log-memory.sh`
- [`scripts/shortcuts/remember-error.sh`](../scripts/shortcuts/remember-error.sh)
  - 用默认 `--scope project --type error` 调 `log-memory.sh`
- [`scripts/shortcuts/index-factual-file.sh`](../scripts/shortcuts/index-factual-file.sh)
  - 用默认 `--scope global --type structured_fact_file` 调 `log-asset.sh`
- [`scripts/shortcuts/index-asset.sh`](../scripts/shortcuts/index-asset.sh)
  - 用默认 `--scope project` 调 `log-asset.sh`

每个 shortcut 都会把额外参数原样转发给底层核心脚本，所以如果后面显式传了同名参数，仍然可以覆盖默认值。

最小 smoke check：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/shortcuts-smoke-test.sh
```

### `scripts/tests/docs-consistency-test.sh`

这是一个快速、基于 grep 的文档漂移检查脚本。

它用来抓 `README.md`、`README.zh-CN.md`、`SKILL.md`、`TODO.md`、maintainer reference 和当前核心脚本集合之间的简单不一致。

它只是 drift detector，不是 semantic validator。

运行方式：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/tests/docs-consistency-test.sh
```

### `scripts/capture/extract-skill.sh`

从可复用 learning 中创建技能脚手架。

它现在会从以下位置读取规范模板块：

- [`references/SKILL-TEMPLATE.md`](../references/SKILL-TEMPLATE.md)

因此，模板资源文件才是真正的单一事实来源。

## 按流程划分的架构

![记忆更新与加载流程](../assets/memory-update-and-loading-flow.svg)

这张图展示了当前实现的运行模型：

- 只要主会话判断某件事值得记录，就可以触发记忆更新
- nightly 会提炼所有已登记的项目记忆，以及所有已存在的全局 namespace
- 新线程先拿到加载指南，而在这个 skill 生效后，主会话会在每次回复前先做 recall step

### 1. 记录流程

```text
Main session
  -> 判断是否需要记忆
  -> 判断应该进入 project 还是 global
  -> 按 SKILL.md 中定义的边界路由
  -> log-memory.sh
  -> memory-paths.sh
  -> init-memory.sh (if needed)
  -> LEARNINGS.md / ERRORS.md / FEATURE_REQUESTS.md
  -> optional git-memory.sh commit
```

### 2. 回顾流程

```text
activator.sh
  -> 记忆位置提示
  -> 全局 memory catalog 与加载指南
  -> <memory-session-guide> block
  -> 不做 eager preload
```

### 3. 提炼流程

```text
organize-memory.sh
  -> REVIEW.md
  -> SUMMARY_CANDIDATES.md

writeback-memory.sh
  -> SUMMARY.md
  -> source status -> promoted_to_summary

update-skill-policy.sh
  -> 只更新 SKILL.md 的 managed routing-strategy block
```

### 4. 夜间流程

```text
cron
  -> nightly-maintenance.sh
  -> 所有已登记的项目记忆
  -> 所有已存在的全局 namespace
  -> writeback-memory.sh (optional)
  -> update-skill-policy.sh (optional, 只改 managed block)
  -> organize-memory.sh
  -> git-memory.sh commit (optional)
```

## 解析器层

召回与提炼路径使用：

- [`scripts/shared/memory-entry-parser.awk`](../scripts/shared/memory-entry-parser.awk)

这个解析器会提取：

- ID
- Logged
- Priority
- Status
- Summary 或 Requested Capability
- Recurrence count

最近一项重要加固：

- 它不再把条目正文中的任意 `---` 行视为条目结束符
- 现在改为按条目头边界和 EOF 进行解析

这个改动很重要，因为错误日志和命令输出里经常会包含分隔线。

## Git 模型

这里有两种彼此独立的 git 模式：

### 项目记忆 Git

- 如果项目记忆位于某个仓库内部，则复用外围仓库
- 否则可以把 `.learnings` 初始化成自己的仓库

### 全局记忆 Git

- 使用全局记忆树仓库
- 在标准 global-root 模式下，提交相关命名空间树和根 README
- 在自定义全局记忆覆盖模式下，提交自定义命名空间树

## 夜间维护

Linux 和 macOS 使用 cron。

推荐默认配置：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/maintenance/install-nightly-maintenance.sh \
  --scope both \
  --hour 4 \
  --minute 0 \
  --writeback true
```

可选的 interval 用法：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/maintenance/install-nightly-maintenance.sh \
  --scope both \
  --interval-hours 6 \
  --writeback true
```

这会安装：

- 固定模式：在指定 hour/minute 运行一次每日 cron
- interval 模式：安装一个轻量 cron probe，由 `interval-maintenance.sh` 判断是否真的到了执行窗口
- `scope=both`
- `writeback=true`
- 默认 `git-autocommit=false`
- 日志路径为 `${XDG_STATE_HOME:-$HOME/.local/state}/memory-and-improvement/logs/nightly-maintenance.log`

生成的 cron 命令会有意使用 `$HOME` 风格路径，以便提升可读性和可移植性。
interval 模式还会把最近一次成功运行时间记录在 `${XDG_STATE_HOME:-$HOME/.local/state}/memory-and-improvement/` 下。

Windows 使用任务计划程序和 Git for Windows：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  "$HOME\.codex\skills\memory-and-improvement\scripts\maintenance\install-windows-maintenance.ps1" `
  -Apply
```

Windows installer 会读取同一套配置解析结果，支持 fixed 和 interval 两种调度方式，并通过 Git Bash 调用既有 Bash 维护核心。预览、参数覆盖、日志和验证方法见 `references/windows-maintenance.md`。
安装入口为 `scripts/maintenance/install-windows-maintenance.ps1`。
跨平台写锁由 `scripts/shared/file-lock.sh` 提供；当 `flock` 不可用时，会自动回退到原子目录锁。

## Global Configuration

现在可以把跨项目的全局默认值集中放在一个文件里：

- `~/.codex/skills/memory-and-improvement/config.toml`

这里说的是这个 skill 自己的全局配置文件。
本阶段不支持 project-local config file。
如果这个文件不存在，skill 会继续使用 `memory-and-improvement/config/defaults.toml` 里的内建默认值。
loader 也只支持一个刻意收窄的 TOML 子集：固定 section、带引号的字符串、布尔值、整数、注释和空行。

优先级顺序是：

1. CLI arguments
2. environment variables
3. global config file
4. built-in defaults

内建默认值来自仓库内置文件：

- `memory-and-improvement/config/defaults.toml`

派生路径说明：

- `log_dir` 仍然是受支持的用户配置覆盖项，但内建默认值会继续从 `state_root/logs` 派生；只有你在用户 config 里显式设置时，它才会脱离这个派生规则
- `global_namespaces_root` 默认会跟着 `global_root/namespaces` 派生；只有你在用户 config 或环境变量里显式设置时，它才会脱离这个派生规则

这一阶段支持的配置面包括：

- `[paths]`
  - `global_root`
  - `global_namespaces_root`
  - `state_root`
  - `log_dir`
  - `codex_home`
  - `codex_skills_dir`
- `[defaults]`
  - `global_namespace`
  - `git_autocommit`
  - `nightly_writeback`
  - `skill_policy_writeback`
  - `organize_min_recurrence`
- `[maintenance]`
  - `scope`
- `[maintenance.schedule]`
  - `mode`
  - `hour`
  - `minute`
  - `interval_minutes`

未知 key 或拼错的 key 会直接报错，而不是静默忽略。

兼容性说明：

- `SELF_IMPROVING_GLOBAL_MEMORY_DIR` 仍然保留为 env-only escape hatch，用来直接指向某个全局 `.learnings` 目录
- `global_namespace` 只是 single-namespace 命令下的 fallback-only 默认值；如果你已经知道正确 namespace，优先显式传入，而不是依赖默认桶
- `XDG_STATE_HOME` 仍然是父级状态目录的环境变量覆盖入口，skill 仍会在后面追加 `/memory-and-improvement`
- 内建默认值会把 `log_dir` 继续派生为 `state_root/logs`；只有你明确想换位置时，才需要在用户 config 里设置 `log_dir`

示例：

```toml
[paths]
global_root = "$HOME/global-memory"
global_namespaces_root = "$HOME/global-memory/namespaces"
state_root = "$HOME/.local/state/memory-and-improvement"
codex_home = "$HOME/.codex"
codex_skills_dir = "$HOME/.codex/skills"

[defaults]
global_namespace = "research-principle"
git_autocommit = true
nightly_writeback = true
skill_policy_writeback = false
organize_min_recurrence = 2

[maintenance]
scope = "both"

[maintenance.schedule]
mode = "interval"
hour = 4
minute = 0
interval_minutes = 240
```

调度默认值的行为：

- 当 `mode = "fixed"` 时，如果你没有传调度相关 CLI 参数，`install-nightly-maintenance.sh` 会使用配置里的 `hour` 和 `minute`
- 当 `mode = "interval"` 时，如果你没有传 `--interval-minutes` 或 `--interval-hours`，installer 会使用 `interval_minutes`
- 如果你没有传 `--scope`，`nightly-maintenance.sh` 和 `interval-maintenance.sh` 也会使用配置里的 `maintenance.scope`
- 改了 config 之后不会自动改写已经安装好的 crontab；需要重新运行 installer，新的默认值才会体现在生成的 cron entry 里
- installer 现在也会把当时解析出来的 namespace 和 global-root 默认值固化进生成的 cron line，避免后面再改 built-in/defaults 文件时悄悄把旧任务重定向到别处

## Hooks

这个技能也支持 Codex hook 集成。

典型拆分方式：

- `activator.sh` 绑定到 `SessionStart`

Hook 路径提醒：

- 当前生效的 hook 入口是 `~/.codex/skills/memory-and-improvement/scripts/hooks/activator.sh`
- 如果本地旧版 `hooks.json` 还指向 `~/.codex/skills/memory-and-improvement/scripts/activator.sh`，要迁移到 `scripts/hooks/activator.sh`
- 如果你的 Codex 运行时不会展开 hook 命令里的 `~`，就改用绝对路径

推荐的心智模型：

- 在会话开始时告诉模型项目和全局记忆在哪里
- 先把潜在记忆当成 candidate，而不是自动落盘
- 当你看到持久偏好、跨项目持久事实、仓库约定、重复失败模式或真实缺失能力请求时，考虑是否要记录
- 用一个简短清单判断：是不是可复用流程；否则下周在别的仓库还有没有用；否则是不是值得保留的 repo-specific 事实或模式
- 由主会话自己判断某条信息是否值得先 capture，以及之后要不要提升
- 由主会话自己判断它属于 project memory 还是某个 global namespace
- 一旦决定记忆，直接调用 `log-memory.sh`
- 用了这个 skill 之后，每次回复前先做显式的 recall decision；只有当高层不够时才继续往深层读

重要提示：

hook 层仍然依赖 Codex 运行时行为。shell 脚本本身已经做了较充分的加固，但 hook 是否有效仍取决于运行时实际暴露了什么。

## 端到端示例

### project learning

1. 发现一个 repo-specific 约定或失败模式
2. 用 `log-memory.sh` 记到 project memory
3. 之后优先读 `SUMMARY.md`，再读 `REVIEW.md`，只有在需要更细节时才打开原始 learning

### global user-profile fact

1. 先把原始事实记到 `user-profile/.learnings/`
2. 当它稳定且反复需要时，提升到 `PROFILE.md`、`ACADEMIC_PROFILE.md`、`PUBLICATIONS.md` 或 `FUNDING_HISTORY.md`
3. 之后的新会话先读 `SUMMARY.md`，只有确实需要 profile 细节时才打开对应 factual file

### indexed paper PDF asset

1. 把 artifact 放在稳定路径
2. 用 `log-asset.sh` 把它索引进对应 scope 的 asset index
3. 先搜索或回顾 asset index，只有在确实需要 artifact 本体时才打开 PDF

## 重要环境变量

### 路径与作用域

- `SELF_IMPROVING_PROJECT_ROOT`
- `SELF_IMPROVING_PROJECT_MEMORY_DIR`
- `SELF_IMPROVING_GLOBAL_ROOT`
- `SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT`
- `SELF_IMPROVING_GLOBAL_NAMESPACE`
- `SELF_IMPROVING_GLOBAL_MEMORY_DIR`

### 自动化

- `SELF_IMPROVING_GIT_AUTOCOMMIT`
- `SELF_IMPROVING_NIGHTLY_WRITEBACK`
- `SELF_IMPROVING_ORGANIZE_MIN_RECURRENCE`

### Codex 集成

- `CODEX_HOME`
- `SELF_IMPROVING_CODEX_SKILLS_DIR`

## 典型工作流

### 同时初始化项目和全局记忆

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/bootstrap/init-memory.sh --scope both --project-root "$PWD"
```

### 回顾当前记忆

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/recall/review-memory.sh --scope project
bash ~/.codex/skills/memory-and-improvement/scripts/recall/review-memory.sh --scope both
```

### 记录一条 learning

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/capture/log-memory.sh \
  --scope project \
  --type learning \
  --category correction \
  --summary "This repo uses latexmk, not pdflatex" \
  --details "Builds fail when pdflatex is used directly" \
  --suggested-action "Call latexmk in automation and docs"
```

### 记录一条 error

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/capture/log-memory.sh \
  --scope project \
  --type error \
  --summary "Local dev server fails when port is occupied" \
  --error-text "listen EADDRINUSE: address already in use" \
  --context "Observed during npm run dev" \
  --suggested-fix "Detect and free the port before restart"
```

### 记录一条功能请求

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/capture/log-memory.sh \
  --scope project \
  --type feature \
  --capability "Add batch export command" \
  --user-context "Repeatedly needed during nightly reporting" \
  --suggested-implementation "Expose a CLI wrapper around the existing export pipeline"
```

### 整理并写回重复记忆

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/maintenance/organize-memory.sh --scope both
bash ~/.codex/skills/memory-and-improvement/scripts/maintenance/writeback-memory.sh --scope both --min-recurrence 2
```

### 启用 git 跟踪

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/maintenance/git-memory.sh init --scope both
SELF_IMPROVING_GIT_AUTOCOMMIT=true bash ~/.codex/skills/memory-and-improvement/scripts/capture/log-memory.sh ...
```

### 提取一个可复用技能

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/capture/extract-skill.sh \
  review-memory \
  --source-file ~/.learnings/LEARNINGS.md \
  --learning-id LRN-YYYYMMDD-NNN
```

## 这个系统不是什么

它不是：

- 密钥存储
- 全文数据库
- 事务型事件日志
- 仓库文档或设计文档的替代品
- 仓库本地 `AGENTS.md` 的替代品
- 高质量独立技能的替代品

不要存储：

- secrets
- tokens
- private keys
- 原始环境转储
- 不应以纯 markdown 形式保存的敏感个人数据

## 已知运行边界

这些是正常且预期的边界，而不是当前故障：

- hook 行为仍然依赖 Codex 运行时集成
- markdown 仍然是持久化格式，因此更偏向人类可读，而不是强类型
- 高并发编辑虽然比以前安全，但它仍然不是一个完整数据库
- 维护报告是派生产物，不是权威源记录

## 维护指南

如果你要长期维护这套系统，优先优化“收敛”和“低噪音演进”，而不是单纯追求功能数量。

推荐按这个顺序工作：

1. 当稳定策略发生变化时，先改 [references/maintainer-reference.md](../references/maintainer-reference.md)
2. 把 [SKILL.md](../SKILL.md) 控制在运行时行为和短 guardrails 的范围内
3. 让 `README.md` 和 `README.zh-CN.md` 保持人类可读的总结，而不是完整 policy dump

保持脚本目录纪律：

- 保持分组结构稳定：`bootstrap/`、`capture/`、`recall/`、`maintenance/`、`hooks/`、`shared/`、`shortcuts/`、`tests/`
- bootstrap 逻辑放在 `scripts/bootstrap/`
- 写入路径和提取逻辑放在 `scripts/capture/`
- recall/search/reflect 逻辑放在 `scripts/recall/`
- 提炼、writeback、git 和 nightly 逻辑放在 `scripts/maintenance/`
- hook 入口和 hook 专用辅助脚本放在 `scripts/hooks/`
- 共享的路径/解析器辅助层放在 `scripts/shared/`
- 薄封装统一放在 `scripts/shortcuts/`
- 回归检查统一放在 `scripts/tests/`
- 不要在 wrapper 里重复实现核心行为

资源边界也要保持清楚：

- memory asset 属于 memory store，但路径要按 scope 区分：project memory 用 `.learnings/assets/INDEX.md`，global namespace 用 `assets/INDEX.md`
- 稳定策略文档和模板应放在 `references/` 下
- 导出的图表、图片以及可编辑的图文件可以放在 `assets/` 下

只要行为有变化，就在同一轮里同步这些层：

- 脚本行为
- `SKILL.md`
- `README.md`
- `README.zh-CN.md`
- 当某个计划 phase 落地时同步 `TODO.md`
- 如果变动触及稳定策略，再同步 `references/maintainer-reference.md`

每次比较实质性的维护，都跑这些轻量检查：

- `bash ~/.codex/skills/memory-and-improvement/scripts/tests/docs-consistency-test.sh`
- 与功能对应的 shell 测试，例如 `search-memory-test.sh`、`shortcuts-smoke-test.sh`、`suggest-promotions-test.sh`

把下面这些当成固定维护规则：

- 大多数内容应该继续留在原始 `.learnings/*.md`
- `suggest-promotions.sh` 只能是 advisory tool，不能演化成 automatic promotion
- 图表修改后要做 subagent 审阅，也要看真实渲染结果，不能只看源码
- 按 TODO 推进这个技能时，进入下一阶段前要先做一次 subagent 审计
- 改 `config/defaults.toml` 里的 nightly/interval 默认值时，要同时用 `bash ~/.codex/skills/memory-and-improvement/scripts/maintenance/install-nightly-maintenance.sh --apply` 刷新 live crontab

如果你不确定新规则该放哪一层：

- 稳定策略 -> `references/maintainer-reference.md`
- agent 运行时行为 -> `SKILL.md`
- 面向人的解释 -> 双语 README
- 可执行约束或回归保护 -> scripts/tests

## 维护与诊断入口

日常使用 Codex 不需要执行下面这些命令。独立安装、验证、排错或恢复时，维护者
可以直接调用同一组辅助脚本：

```bash
bash ~/.codex/skills/memory-and-improvement/scripts/bootstrap/init-memory.sh --scope both --project-root "$PWD"
bash ~/.codex/skills/memory-and-improvement/scripts/recall/review-memory.sh --scope project
bash ~/.codex/skills/memory-and-improvement/scripts/capture/log-memory.sh --scope project --type learning --summary "..." --details "..." --suggested-action "..."
bash ~/.codex/skills/memory-and-improvement/scripts/maintenance/install-nightly-maintenance.sh --scope both --hour 4 --minute 0 --writeback true
```

这些示例会验证：

- 已初始化的项目/全局记忆
- 回顾快照
- 结构化记录
- 每天 04:00 的夜间维护

## 相关文件

- [`SKILL.md`](../SKILL.md)
- [`scripts/shared/memory-paths.sh`](../scripts/shared/memory-paths.sh)
- [`scripts/capture/log-memory.sh`](../scripts/capture/log-memory.sh)
- [`scripts/recall/review-memory.sh`](../scripts/recall/review-memory.sh)
- [`scripts/maintenance/organize-memory.sh`](../scripts/maintenance/organize-memory.sh)
- [`scripts/maintenance/writeback-memory.sh`](../scripts/maintenance/writeback-memory.sh)
- [`scripts/maintenance/update-skill-policy.sh`](../scripts/maintenance/update-skill-policy.sh)
- [`scripts/maintenance/git-memory.sh`](../scripts/maintenance/git-memory.sh)
- [`scripts/maintenance/nightly-maintenance.sh`](../scripts/maintenance/nightly-maintenance.sh)
- [`scripts/maintenance/install-nightly-maintenance.sh`](../scripts/maintenance/install-nightly-maintenance.sh)
- [`scripts/capture/extract-skill.sh`](../scripts/capture/extract-skill.sh)
- [`references/SKILL-TEMPLATE.md`](../references/SKILL-TEMPLATE.md)
