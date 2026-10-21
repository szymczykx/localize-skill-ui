# Skill 界面汉化 / Localize Skill UI

让 Agent 根据每个 Skill **当前的说明**生成简体中文界面描述。已有且准确的中文保持原样；原始 `SKILL.md` 详细说明不变。

This Agent Skill localizes Codex skill UI descriptions into Simplified Chinese, based on current skill instructions. It preserves accurate Chinese descriptions, detailed instructions, and unrelated metadata.

## 安装与使用

用支持 GitHub Skill 安装的工具安装仓库中的 `skills/localize-skill-ui/`，或将该目录复制到你的 Skill 安装目录。例如，安装到 Codex：

```bash
git clone https://github.com/szymczykx/localize-skill-ui.git
mkdir -p "$HOME/.agents/skills"
cp -R localize-skill-ui/skills/localize-skill-ui "$HOME/.agents/skills/"
```

目标目录已存在时先检查本地改动，再选择合并或替换。刷新技能列表后，对 Agent 说：

> 用 $localize-skill-ui 将 ~/.agents/skills 下的界面描述改为中文，保留已有且准确的中文描述。

默认仅处理 `~/.agents/skills` 的直接子目录。不会扫描整台机器、自动更新 Skill 或修改插件缓存。

## harness 支持范围

安装目录和界面元数据是两个不同层面。脚本通过 `--root` 接受任意本地 Skill 根目录，其中每个直接子目录包含 `SKILL.md`。

| 层面 | 支持范围 |
| --- | --- |
| 运行本 Skill 的 Agent | 能读取文件、执行 Ruby、生成中文描述的 harness |
| 输入目录 | 用户指定的全局或项目 Skill 根目录，无硬编码用户名 |
| 界面写入格式 | Codex 的 `agents/openai.yaml` → `interface.short_description` |
| 其他 harness 的原生界面 | 暂无适配；在其目录生成此文件，不代表客户端会读取 |
| 路径发现 | 显式指定单个根目录，不自动发现全部 harness |
| 符号链接 | 拒绝 Skill 目录及目标元数据的符号链接；需要处理时直接指定真实目录的父目录 |

这使 Agent 可以在不同 harness 中执行同一工作流，同时明确限定界面生效范围。对于不支持独立界面描述的客户端，不通过修改 `SKILL.md.description` 来替代汉化。

## 命令行工作流

需要 Ruby 2.6 或更高版本及其标准库。脚本本身不调用模型、翻译 API 或网络；语义核对与翻译由执行 Skill 的 Agent 完成。

```bash
# 1. 读取当前原始说明和界面描述，仅输出 JSON 预览
ruby skills/localize-skill-ui/scripts/localize.rb --root /path/to/skills

# 2. Agent 根据当前说明生成临时审核结果（JSON：目录名 → 最终中文描述）
#    已有中文准确时填入原文，表示已经核对。

# 3. 预览本次结果
ruby skills/localize-skill-ui/scripts/localize.rb \
  --root /path/to/skills --translations /path/to/review.json

# 4. 写入，再用同一份审核结果预览，确认 unchanged
ruby skills/localize-skill-ui/scripts/localize.rb \
  --root /path/to/skills --translations /path/to/review.json --apply
```

新生成的描述为 25–64 个字符；准确的现有中文可按原长度保留。没有固定译文清单，临时审核文件在完成后删除。

| 退出码 | 含义 |
| --- | --- |
| `0` | 预览已完成审核，或写入成功；空目录也返回 `0` |
| `1` | 输入、配置或写入错误；查看标准错误输出 |
| `2` | 预览中存在 `needs_review` 或 `missing_translation`，需要 Agent 核对或生成译文 |

已有 YAML 中的名称、图标、默认提示、调用策略、依赖和其他字段值保留。序列化可能改变注释、引号及格式。每个文件通过临时文件替换写入；输入校验失败时不写入。跨文件写入不是事务，磁盘或权限错误可能在部分文件完成后发生，应检查结果再重试。

## 验证

```bash
ruby tests/localize_test.rb
```

测试覆盖预览只读、配置创建、原文及扩展字段保留、重复执行、缺少审核结果、错误 YAML、路径带空格、符号链接拒绝等场景。CI 在 Linux 和 macOS 上运行。未验证所有 harness 的界面刷新行为。

## 仓库结构

```text
skills/localize-skill-ui/
  SKILL.md              # Agent 工作流
  agents/openai.yaml    # 本 Skill 的界面名称和中文描述
  scripts/localize.rb   # 收集信息、校验和写入
tests/localize_test.rb  # CLI 行为验证
```
