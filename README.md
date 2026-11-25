# dddx-video-production

口播视频全流程技能（WorkBuddy / Claude Skill 格式）。把一篇文案做成带素材、字幕和动效的口播片。

四段流水线，每段产出可检查的文件，下一段只读上一段的产物：

```
0 准备   00-brief.md + 素材清单
1 文案   01-script-final.md          去语病、改口语、数字与多音字预处理
2 剪辑   02-edit-plan.md（镜表）     动效镜头的渲染要 onetake 的 python 环境
3 音频   vo/*.wav + manifest.json    Voicebox 逐句 TTS + ASR 回读校验
4 成片   ChatCut 工程 + mp4          BGM、字幕、结尾引导
```

## 依赖

| 环节 | 需要什么 | 说明 |
|---|---|---|
| 阶段 2 动效 | [onetake](https://github.com/feitangyuan/onetake) 技能 + python/playwright/ffmpeg | 动效段落用它出（音效与画面事件对齐）；缺环境时退回 Remotion |
| 阶段 2 alpha 叠层 | Node 22+ / Remotion | 只做需要透明通道叠在实拍上的小元素 |
| 阶段 3 口播 | Voicebox 桌面端（本地 17493 端口）+ Node 22+ | 逐句生成，便于单句重做与时间轴重排 |
| 阶段 4 剪辑 | ChatCut Desktop（MCP `chatcut_desktop` 工具）+ Node 22+ | 工具在会话开始时加载，装完要开新对话 |
| BGM | ffmpeg/ffprobe | 曲库与授权台账见下 |

## 脚本

| 脚本 | 作用 |
|---|---|
| `scripts/check-tools.sh` | macOS/Linux 三件套自检（Voicebox 端口 / ChatCut 进程 / Node 版本），会顺手拉起已安装未运行的 App；Windows 下自动转交 `.ps1` |
| `scripts/check-tools.ps1` | 同一件事的 Windows 实现，输出格式与退出码完全一致 |
| `scripts/tts.js` | 按标点切句 → 逐句调 Voicebox → 写 `vo/manifest.json`（含每句真实秒数），`--verify` 做 ASR 回读校验 |
| `scripts/bgm-check.sh` | 量候选 BGM 的时长 / LUFS / 真峰值 / LRA，算出降到 -34 LUFS 需要的 bed gain |

```bash
bash scripts/check-tools.sh                     # 或 --no-launch 只看状态
bash scripts/check-tools.sh --port 17493
node scripts/tts.js --text 01-script-final.md --dry-run
node scripts/tts.js --text 01-script-final.md --out vo --profile "我的音色" --engine qwen --verify
bash scripts/bgm-check.sh ~/Music/bgm/*.mp3 --need 62
```

## 几条踩过的规则

- 镜表的时间轴以口播为绝对时钟：音频出来后用 `manifest.json` 的真实秒数重排，不要反过来改音频凑画面。
- 动效段落自带音效（-16 LUFS 完整混音），要么保留并整段降到 -26 ~ -30 LUFS，要么整段静音，**不要叠两层**。
- BGM 底板先拉到 -32 ~ -36 LUFS（现代曲库母带都很响，bed gain 常在 -20 ~ -24 dB），低频占比超 35% 的先做 120 Hz 低切。
- 平台自带曲库（抖音 / 剪映 / B站 / YouTube Audio Library）授权只覆盖平台内发布，导出 mp4 跨平台分发即越界。
- 素材原声一律静音。

详见 `SKILL.md`。

## 安装到 WorkBuddy

技能分用户级和项目级两种装法。**装完必须开新对话**——技能列表在会话开始时加载，当前这一轮里看不到新技能。

### 用户级（所有项目可用）

```bash
git clone https://github.com/Planeswalker23/dddx-video-production.git \
  ~/.workbuddy/skills/dddx-video-production
```

### 项目级（只在某个工作区可用）

```bash
mkdir -p <工作区>/.workbuddy/skills
git clone https://github.com/Planeswalker23/dddx-video-production.git \
  <工作区>/.workbuddy/skills/dddx-video-production
```

### 更新

```bash
cd ~/.workbuddy/skills/dddx-video-production && git pull
```

### 装完先自检

```bash
bash ~/.workbuddy/skills/dddx-video-production/scripts/check-tools.sh
```

Windows：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.workbuddy\skills\dddx-video-production\scripts\check-tools.ps1"
```

末行 `RESULT: ALL_READY` 才能进阶段 3、4；`RESULT: BLOCKED (...)` 会写明缺哪个。

### 还要单独装的（本仓库不含）

| 依赖 | 怎么装 |
|---|---|
| **onetake**（动效段落） | `git clone https://github.com/feitangyuan/onetake.git ~/.workbuddy/skills/onetake`，再按它的 SKILL.md 装 python 依赖（playwright + chromium、numpy / scipy / pillow / matplotlib / fonttools / brotli / opencv-python）。它是 **PolyForm Noncommercial** 许可，商用需另行取得授权 |
| **Voicebox**（口播 TTS） | macOS：https://voicebox.sh/download?platform=macos ；Windows：https://voicebox.sh/download/windows |
| **ChatCut Desktop**（剪辑） | macOS：`curl -fsSL https://chatcut.io/install.sh \| sh` ；Windows：`irm https://chatcut.io/install.ps1 \| iex` |
| **Node 22+** | https://nodejs.org/en/download |
| **ffmpeg / ffprobe** | `brew install ffmpeg` 或 https://ffmpeg.org/download.html |

ChatCut 装完要**登录**，然后**开新对话**才能拿到 `chatcut_desktop` 工具（工具在会话开始加载，装的那一轮没有）。

### 不在仓库里的东西

- **BGM 曲库**在本地 `~/Music/bgm/`，含 `README.md`（命名规则、选曲标准）和 `license-ledger.md`（授权台账）。曲目受各曲库授权约束，不随仓库分发；换机器时按 `README.md` 的「加新曲子的流程」重建，或整目录拷过去（连同台账）。

