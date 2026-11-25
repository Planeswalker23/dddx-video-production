---
name: dddx-video-production
description: 口播视频全流程制作技能。文案优化（去语病、改口语）→ 剪辑脚本（文案与素材逐句对齐，含转场/文字/音效；**动效镜头用 onetake 制作**，Remotion 只做 alpha 叠层）→ Voicebox TTS 生成逐句口播音频 → ChatCut Desktop 剪辑成片（BGM、结尾关注引导、其余素材静音）。用于「把一篇文案做成带素材和字幕的口播/解说视频」，或用户提到 Voicebox + ChatCut + onetake 组合出片。
whenToUse: 用户说「做一条口播视频」「把这篇文案做成视频」「用我这些素材剪个解说片」「配个音然后剪出来」「加个动效/动画镜头」，或明确要求用 Voicebox / ChatCut / onetake / Remotion 出片时。
user-invocable: true
---

# 口播视频制作

四段流水线，每段产出可检查的文件，下一段只读上一段的产物。**顺序不能跳**：文案没定稿不做音频，音频没定稿不排画面。

**阶段 0–2 的文档部分只写文件，不依赖任何外部软件**：brief、文案、镜表永远能做完。**动效镜头的渲染**（阶段 2 末尾）要 onetake 的 python 环境，阶段 3 要 Voicebox，阶段 4 要 ChatCut Desktop——**进这三个环节先跑自检，不要假设工具在**。缺工具时走降级路径，把能做的做完并标明哪部分是占位。

| 阶段 | 产出 | 通过标准 |
|---|---|---|
| 0 准备 | `project/` 目录结构、`00-brief.md`、素材清单 | 素材总时长 ≥ 口播预估时长（否则先谈补素材） |
| 1 文案 | `01-script-final.md` | 用户明确说"就用这版" |
| 2 剪辑脚本 | `02-edit-plan.md`（镜表）+ `motion/` 动效需求清单（交给 onetake） | 每一句口播都有对应画面，无空档 |
| 3 口播音频 | `vo/*.wav` + `vo/manifest.json` | 逐句 ASR 回读与文案一致 |
| 4 剪辑成片 | ChatCut 工程 + 导出 mp4 | QA 清单全过 |

目录约定（全部放在用户指定的项目目录下）：

```
project/
  00-brief.md          目标、平台、时长、比例、参考片
  01-script-final.md   定稿文案，一句一行
  02-edit-plan.md      镜表
  assets/              用户素材（原样，不改不压）
  bgm/                 选中的 BGM + license-ledger.md（授权台账）
  motion/              onetake 动效工程（comp.html + look.js + sfx）+ motion/out/ 渲染出的段
  remotion/            Remotion 工程（只做需要 alpha 叠在实拍上的元素）
  vo/                  口播音频 + manifest.json
  out/                 导出成品
```

---

## 阶段 0：准备（5 分钟，省掉后面 5 次返工）

**先问清四件事**，缺哪个就停下来问，不要猜：

1. **投放平台与比例**：横屏 1920×1080 / 竖屏 1080×1920 / 方屏。这决定所有素材的裁切策略和字幕安全区。
2. **目标时长**：有硬指标的（如"必须 60 秒内"）写进 brief。
3. **帧率**：默认 30fps。素材有 25/50/60 的要统一——Remotion 和 ChatCut 工程必须同帧率，否则叠加画面会抖。
4. **有没有口播形象**：纯音频 + 素材，还是要出镜画面（出镜要另拍或另生成，不在本技能范围）。

**素材盘点**，用一句话命令拿清单（不要靠肉眼翻文件夹）。按本机系统选一条，输出格式一样（类型 / 字节数 / 相对路径）：

Windows：

```powershell
Get-ChildItem assets -Recurse -File | ForEach-Object {
  $d = if ($_.Extension -match 'mp4|mov|mkv|avi|webm') { 'video' } elseif ($_.Extension -match 'wav|mp3|m4a|aac|flac') { 'audio' } else { 'image' }
  "{0,-6} {1,10:N0}  {2}" -f $d, $_.Length, $_.FullName.Substring((Get-Location).Path.Length + 1)
}
```

macOS / Linux：

```bash
find assets -type f -print0 | while IFS= read -r -d '' f; do
  case "$f" in
    *.mp4|*.mov|*.mkv|*.avi|*.webm) d=video ;;
    *.wav|*.mp3|*.m4a|*.aac|*.flac) d=audio ;;
    *) d=image ;;
  esac
  printf '%-6s %10s  %s\n' "$d" "$(wc -c <"$f" | tr -d ' ')" "$f"
done | sort
```

记进 `00-brief.md`：文件名、类型、大小、大致内容（打开看，别按文件名猜）、可用片段区间。**素材不够填满口播时长时，差多少秒就明说**——这是后面"要不要做 Remotion 补充画面"的依据。

素材命名统一成 `场景-序号-描述`（`采访-01-车间全景.mp4`），ChatCut 的素材面板按文件名排序，命名乱了剪辑时找不到。

---

## 阶段 1：文案优化

目标读者是**听**的人，不是读的人。改法按优先级：

1. **拆长句**。一口气读不完的句子一律拆开。一屏字幕不超过 20 字，一句话不超过 25 字。
2. **去书面连接词**。「综上所述」「基于此」「值得注意的是」→ 直接删或换成「所以」「这么一来」。
3. **动词前置、主语明确**。「问题的解决需要各方的努力」→「这事儿得大家一起使劲」。
4. **删重复信息**。口播里同一个意思说两遍是浪费时长，尤其段落结尾的总结句。
5. **开头 3 秒给钩子**。第一句不能是"今天我来给大家介绍一下"，要是结论、冲突或数字。
6. **结尾给动作**。不要"谢谢观看"，要具体引导（见阶段 4 的关注引导）。

**数字和专有名词必须预处理**——中文 TTS 读阿拉伯数字和缩写不稳定，这里不改，音频阶段就得重来：

| 原写法 | 改成 | 原因 |
|---|---|---|
| 2026年11月25日 | 二零二六年十一月二十五日 | 年月日连读容易读成"两千零二十六" |
| 3.5% | 百分之三点五 | 小数点 + 百分号组合常读错 |
| 1280 万 | 一千二百八十万 | 大数字单位易丢 |
| K8s / SLA / SDK | Kubernetes / 服务等级协议 / 开发工具包（首次出现） | 缩写读法不可控 |
| 1-2 天 | 一到两天 | 连字符会被读成"减" |

**多音字靠改写规避，不靠标注**。Voicebox 的 Qwen 系列不支持音素级控制，写拼音没用：

- 「重要」→ 如果会被读成 chóng，改成「关键」
- 「行业」→ 读成 xíng 就改成「领域」
- 「重做」→ 改成「再做一遍」

单独建 `01-pronunciation.md` 记下改过的地方，后面 ASR 校验时对照。

**标题、字幕、口播三份文案是分开的**：口播稿里不要掺 `## 小标题` 和镜头说明，否则会被读出来。定稿文件只保留要念的字。

---

## 阶段 2：剪辑脚本

产出一个镜表（`02-edit-plan.md`），每行一个镜头，覆盖整条片子无空档：

| # | 入点 | 出点 | 秒 | 口播句（截前 12 字） | 画面来源 | 转场 | 文字/图形 | 音效 |
|---|---|---|---|---|---|---|---|---|
| 1 | 0.0 | 4.2 | 4.2 | 去年这条产线停了三次 | 采访-01-车间全景 | 硬切 | 标题「三次停机」 | — |
| 2 | 4.2 | 9.8 | 5.6 | 每次平均损失四小时 | onetake:loss-chart | 叠化 0.3s | 数字 4 小时 弹入 | 计算器咔哒 |

规则：

- **时间轴以口播为绝对时钟**。入点出点先按文案预估（中文口播约 4.5 字/秒，慢速 3.5 字/秒），音频生成后用 `vo/manifest.json` 的真实秒数**重排这张表**，不要反过来改音频去凑画面。
- **每个镜头必须有画面来源**，四类之一：`assets/` 里的文件（写文件名 + 裁剪区间）、`onetake:<film>`（动效段落）、`remotion:<composition-id>`（alpha 叠层）、纯色/黑场卡片。写"待定"的镜头数量就是额外工作量，提前暴露。
- **转场克制**：全片硬切为主，只在时间跳跃、场景切换处用叠化（0.3–0.5s）或推拉。每 10 秒超过 2 个花式转场就显得廉价。
- **文字特效只做三类**：标题卡（入片 3 秒内）、关键数字强调（弹入/放大）、章节分隔（可选）。屏幕上同时不超过两行字。
- **音效列只写有必要的**：转场、数字出现、强调点击。一条 60 秒片子 5–8 个音效足够，多了吵。
- **竖屏特别注意**：主体在画面中间偏上 2/3，底部 20% 留给字幕和平台 UI（抖音/视频号的按钮会盖住）。

### 动效镜头：默认交给 onetake，Remotion 只做 alpha 叠层

**凡是要「画出来」的镜头，一律先用 `skill:onetake` 做**，不要拿 Remotion 从零画。onetake 专治动效：动效库 39 个实测过的 move、真实运动模糊、节奏与承接的验收（不承接的 PPT 式切换会被它的 oracle 判掉），出的是成段 mp4。

| 镜头性质 | 用什么 | 产物 |
|---|---|---|
| 能独立成段的动效：片头、数据图/趋势曲线、流程示意、UI 功能演示、章节卡、结尾关注引导 | **onetake** | `motion/out/<film>.mp4`（不带 alpha，整段当画面铺） |
| 需要透明通道叠在实拍上的小元素：一个数字弹入、箭头、标注框、设备参数角标 | Remotion | `remotion/out/<id>.mov`（ProRes 4444） |
| 用户点名要 Remotion，或 onetake 环境跑不起来（见下节自查） | Remotion | 同上 |

**素材能覆盖的一律不用任何代码画面**——画一个真实场景的成本远高于剪一段实拍。

onetake 要点（不是教程，细节读它自己的 SKILL.md）：

- 先调用 `skill:onetake` 加载它的流程。它有硬规则：**拆参考片 → 三个概念给用户选 → 节拍表（节奏 + 承接）→ 素材/复刻 UI → 编排 → 静帧 → 渲染 → 声音 → 验收**。**不要跳过概念环节直接写 comp**，它的验收会因为你抄模板故事而判「没有创造力」。
- 工程放 `motion/<film>/`，`comp.html` 与 `look.js` 同目录；`look.js` 用 `scripts/look.py apply <预设> comp.html` 生成（字体 subset 内联，`file://` 渲染才拿得到真字体）。
- **尺寸帧率必须与阶段 4 的 ChatCut 工程一致**：横屏用默认 1920×1080@30，竖屏加 `--width 1080 --height 1920`。不一致就裁切或抖动。
- **时长对齐该段口播的真实秒数**（`vo/manifest.json`），写进 `window.__meta.dur`；宁可多 0.2 秒进 ChatCut 再裁，不要短。
- 顺序固定：`stills.py` 看静帧 → `render.py` 出 1080p30 草稿 → 用户认可后才 `--final` 4K60。**没人认可就渲 4K60 是浪费**。
- 动效段落**自带音效，而且这就是它该有的声音**：用它的 `scripts/sfx_palette.py`（air/glass/wood/sub/bubble，一个共享房间）配 `score.py` 按 comp 的 `__events()` 打点，母带 -16 LUFS / 真峰 -3.5~-4 dBTP。**不要再给这一段铺一首 BGM**——onetake 的作者被用户明确否决过"音乐太吵、动作声听不见"的版本，它的原则是先做动作声、音乐克制。进 ChatCut 后这段要么保留它的音轨、要么整段静音只留口播底板，**二选一，别叠两层**。
- 字幕仍然只在 ChatCut 做。onetake 里的字是画面元素，不是字幕。

```bash
ONETAKE=~/.workbuddy/skills/onetake
# 静帧先看
$ONETAKE/.venv/bin/python3 $ONETAKE/scripts/stills.py motion/my-film/comp.html \
  --times 0.7,2.4,3.8,6.2 --out motion/stills.png
# 草稿（竖屏加 --width 1080 --height 1920；认可以后才加 --final）
$ONETAKE/.venv/bin/python3 $ONETAKE/scripts/render.py motion/my-film/comp.html \
  --out out/seg-01.mp4 --sfx motion/my-film/sfx.wav
```

### onetake 环境自查（动效开做前跑一次）

依赖装在技能自带 venv（`~/.workbuddy/skills/onetake/.venv`），不要污染系统 python。一条命令看齐不齐：

```bash
~/.workbuddy/skills/onetake/.venv/bin/python3 - <<'PY'
import importlib.util, shutil
need = ["playwright","numpy","scipy","PIL","matplotlib","fontTools","brotli","cv2"]
miss = [m for m in need if not importlib.util.find_spec(m)]
print("python deps:", "ok" if not miss else f"MISSING {miss}")
for b in ("ffmpeg","ffprobe","node"):
    print(f"{b}:", shutil.which(b) or "MISSING")
PY
```

缺了就这样补（一次性，含 chromium）：

```bash
cd ~/.workbuddy/skills/onetake && python3 -m venv .venv
./.venv/bin/python3 -m pip install playwright numpy scipy pillow matplotlib fonttools brotli opencv-python
./.venv/bin/playwright install chromium
```

跑不起来（没网装依赖、机器太慢渲不动）就按上表退回 Remotion，并在交付物里标明哪段动效是降级产物。

### Remotion（只做 alpha 叠层）

- 工程放在 `remotion/`，一个 composition 一个镜头，`id` 与镜表里的 `remotion:<id>` 对应。
- **尺寸和帧率必须与 ChatCut 工程完全一致**（1920×1080@30 或 1080×1920@30）。不一致就会出现叠加抖动或裁切。
- `durationInFrames = Math.ceil(该句音频秒数 * fps)`。**宁可多 3 帧后面裁掉，不要短**——短了会露出底层画面。
- 透明背景输出（叠在素材上）：

  macOS / Linux：

  ```bash
  npx remotion render <id> ../out/<id>.mov --codec=prores --prores-profile=4444 \
    --pixel-format=yuva444p10le --image-format=png
  ```

  Windows（PowerShell 续行符是反引号）：

  ```powershell
  npx remotion render <id> ..\out\<id>.mov --codec=prores --prores-profile=4444 `
    --pixel-format=yuva444p10le --image-format=png
  ```

  要小体积可用 `--codec=vp8 --pixel-format=yuva420p` 出 `.webm`，但 ChatCut 对 WebM alpha 支持不稳，**优先 ProRes 4444**。
- 如果叠加画面里嵌了带 alpha 的视频，`<OffthreadVideo>` 要加 `transparent` 属性；用 `@remotion/media` 的 `<Video>` 则不需要。
- **不要在 Remotion 里做字幕**。字幕统一由 ChatCut 从口播音频转写生成，两处都做必然错位。

---

## 工具自检（阶段 3、阶段 4 开头必做）

阶段 0–2 的文档部分（brief、文案、镜表）只写文件，**不需要任何外部工具**。动效渲染要 onetake（见阶段 2 的环境自查），阶段 3 要 Voicebox，阶段 4 要 ChatCut Desktop——**进入这三个环节的第一件事是自检，而不是假设工具在**。

### 一条命令看清三件套

同一件事有两个实现，**输出格式、state 取值、退出码完全一致**，按操作系统选入口就行（不确定就 `uname -s`：`Darwin` = macOS，`Linux` = Linux，Windows 用 PowerShell）：

| 系统 | 命令 |
|---|---|
| macOS / Linux | `bash <技能目录>/scripts/check-tools.sh` |
| Windows | `powershell -NoProfile -ExecutionPolicy Bypass -File <技能目录>/scripts/check-tools.ps1` |

`check-tools.sh` 自带系统判断：在 **WSL / Git Bash** 里跑会自动转交给 `check-tools.ps1`，所以不用自己写 `if os ==`，选对入口即可。

只查状态、不自动拉起（排查用）：

```bash
bash <技能目录>/scripts/check-tools.sh --no-launch        # macOS / Linux
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <技能目录>/scripts/check-tools.ps1 -NoLaunch
```

输出三段，每段一个 `state`：

| 工具 | 判定方式 | state 取值 |
|---|---|---|
| Voicebox | **TCP 连 `127.0.0.1:17493`**（端口通 = API 就绪，比找进程可靠） | `ready` / `installed-not-running` / `not-installed` |
| ChatCut | 进程是否存在（Windows 看 `ChatCut` 进程 + 注册表/常见目录找 exe；macOS 看进程 + `/Applications`、`~/Applications`、Spotlight 找 `.app`） | `running` / `installed-not-running` / `not-installed` |
| Node | `command -v node` / `Get-Command node` 且主版本 ≥ 22（Remotion 要求） | `ok` / `too-old` / `not-installed` |

末行是 `RESULT: ALL_READY`（退出码 0）或 `RESULT: BLOCKED (...)`（退出码 2）。**看末行判断，不要只瞟中间**。

两个脚本都会在 Linux 上把 ChatCut 判成 `not-installed` 并注明「Desktop 无 Linux 版」——这是事实，不是误报。

### 拿到结果后按 state 分支处理

**`ready` / `running` / `ok`** → 直接进本阶段，不要多嘴解释工具怎么装的。

**`installed-not-running`** → 脚本**已经自己拉起过并等了 45 秒（Voicebox）/ 25 秒（ChatCut）**。还是没起来说明它需要人操作（首次下模型、首次登录）。这时：

- 告诉用户「已帮你打开 X，但它在等首次下载/登录，请看一下它的窗口」
- **不要重复启动**（Windows 别再来一次 `Start-Process`，macOS 别再来一次 `open -a`），也不要循环重试
- 不要因为起不来就跳过阶段，先把该阶段能做的部分做完（见下面「降级路径」）

**`not-installed`** → 把安装地址原样给用户，**一句话，不要长篇教程**：

| 工具 | Windows | macOS |
|---|---|---|
| Voicebox | `https://voicebox.sh/download/windows`（MSI，装完首次启动会下模型，几百 MB 到几 GB） | `https://voicebox.sh/download?platform=macos`（DMG，拖进「应用程序」，首次启动同样要下模型） |
| ChatCut Desktop | PowerShell 里跑 `irm https://chatcut.io/install.ps1 \| iex` | 终端里跑 `curl -fsSL https://chatcut.io/install.sh \| sh`（要 macOS 13+，非 root） |
| Node < 22 | `https://nodejs.org/en/download`（要 22 LTS 或更高） | 同左；或用 `brew install node@22` |

给完地址就**停下来等用户装**，同时把「装好之前我们能先做什么」摆出来——不要干等，也不要假装做完了。

### 自动拉起的安全边界

脚本自动启动的是**桌面 GUI 程序**（Windows `Start-Process` / macOS `open`），不是后台服务，符合「未打开就帮用户打开」的要求。但有三件事脚本故意不做，必须人来：

1. **不装东西**。下载安装包、跑 installer 都得用户点头。
2. **不登录**。ChatCut 和 Voicebox 的账号态没法代劳。
3. **不下载模型**。Voicebox 首次启动的模型下载会占几 GB 磁盘和长时间带宽。

### 降级路径（工具缺失时仍要交付价值）

| 缺什么 | 还能做完 | 明确告诉用户 |
|---|---|---|
| 缺 onetake 环境（python/playwright/ffmpeg 缺失，或渲不动） | 阶段 0–2 的文档全部；动效段落退回 Remotion（能做纯卡片/图表类，做不出 onetake 那种承接与运动模糊） | 交付物里标明哪几段动效是降级产物，以及补装依赖后可以重做 |
| 缺 Voicebox | 阶段 0–2 全部；阶段 3 只能给**逐句字数/预估秒数**（`tts.js --dry-run` 不需要 API） | 镜表时间轴先用预估秒数占位，标 `[待实测]`，音频出来必须重排 |
| 缺 ChatCut | 阶段 0–3 全部；`vo/` 出来之后可以先生成一份**给剪辑师看的导入清单**（素材顺序、入出点、音量、字幕文案） | 不要承诺"我帮你剪"，没有 `chatcut_desktop` 工具就动不了时间线 |
| 缺 Node | 只有阶段 0–2；`tts.js` 跑不了，连预估秒数也给不了 | 用「中文 4.5 字/秒」粗估并在文档里标明是估算 |

**降级时必须在交付物里写清哪一段是占位、哪一段是实测**，否则用户会把估算当成最终时间轴。

### 一个容易踩的坑

ChatCut 的 MCP 工具**在会话开始时加载**。用户在这一轮装了 ChatCut，当前对话里仍然没有 `chatcut_desktop` 工具——必须**开新对话**才能用。这不是装错了，重装没用。

---

## 阶段 3：口播音频（Voicebox）

### 3.1 前置检查（先自检，再干活）

进入本阶段第一件事是跑工具自检（`scripts/check-tools.sh` 或 `scripts/check-tools.ps1`，按系统选，用法见上一节），**不要假设 Voicebox 在跑**。看 `[voicebox] state=`：

- `ready` → 继续 3.2。
- `installed-not-running` → 脚本已自动拉起并等过 45 秒仍未监听。**提示用户看一眼 Voicebox 窗口**（首次启动在下载模型），不要重复启动、不要循环重试。
- `not-installed` → 给用户安装地址（Windows `https://voicebox.sh/download/windows` / macOS `https://voicebox.sh/download?platform=macos`），然后**只做阶段 3 的降级部分**：`tts.js --dry-run` 能离线算出每句字数和预估秒数，镜表先用预估秒数占位并标 `[待实测]`。音频没实测出来前，时间轴不算定稿。

要单独确认 API 是否通，随时可以（Windows 用 `curl.exe`，macOS / Linux 用 `curl`）：

```bash
curl -s http://127.0.0.1:17493/profiles
```

- 返回 JSON 数组 → API 就绪。
- 首次生成会下载模型（几百 MB 到几 GB），要等，别当卡死。

### 3.2 选引擎

| 引擎 | 用它的场景 |
|---|---|
| `qwen`（Qwen3-TTS 0.6B/1.7B） | **中文口播默认选它**，支持克隆 + 自然语言演绎控制 |
| `qwen_custom_voice` | 不想录参考音频，用内置 9 个预设音色 |
| `chatterbox` | 需要非中文（23 语言） |
| `chatterbox_turbo` | 需要 `[laugh]` `[sigh]` 这类副语言标签（仅英文） |
| `kokoro` | 只要快、CPU 也能跑 |

只有 `qwen_custom_voice` 真正支持 `instruct`（"语速稍慢、亲切一点"），Qwen Base 会**静默忽略**它——别指望用 instruct 调语气。

### 3.3 逐句生成（用脚本，不要手工点）

`scripts/tts.js` 做三件事：按标点切句 → 逐段调 Voicebox → 写 `vo/manifest.json`（含每段真实秒数）。脚本路径相对本技能目录，执行时换成绝对路径。Windows / macOS 命令完全一致（都只要 `node`），区别只在路径分隔符——用绝对路径时统一写正斜杠最省事。

```bash
# 先干跑，只看切句对不对（不调 API，不需要音色）
node <技能目录>/scripts/tts.js --text 01-script-final.md --dry-run

# 确认后真跑
node <技能目录>/scripts/tts.js --text 01-script-final.md --out vo --profile "我的音色" --engine qwen --lang zh

# 生成后自动 ASR 回读校验（逐句转写 + diff）
node <技能目录>/scripts/tts.js --text 01-script-final.md --out vo --profile "我的音色" --verify
```

干跑会列出每句字数和预估秒数，并警告超过 30 字又无逗号可切的句子——那些必须回阶段 1 手动拆。

**为什么逐句生成而不是整篇一次生成**：整篇生成后你只有一条几十秒的音频，想改一句话就得全部重来，而且无法精确知道每句在时间轴上的位置。逐句生成后每句一个 wav，`manifest.json` 记着每句秒数和累计起点，要改就只重生成那一条，镜表重排也有确切数字。

### 3.4 断句与自然度

- **一句一行**写在 `01-script-final.md` 里。脚本按 `。！？；…` 和换行切，句内逗号保留给 TTS 做气口。
- 单句 8–25 字最自然。超过 30 字在脚本里会二次按逗号切，切点可能不理想，**宁可回阶段 1 拆句**。
- 不要用长破折号 `——`、省略号连打、括号注释：这些在音频里是静默或怪停顿。
- 语气靠**标点和词序**控制，不靠括号指令。想要强调就单独成句。

### 3.5 必须做的 ASR 回读校验

生成完**不能只看文字对不对，要听回来对不对**。`--verify` 会把每个 wav 丢给 `/transcribe`，写 `vo/asr.json` 并逐句打印不一致的地方（已忽略标点差异）。

要人工复核时打开 `vo/asr.json` 对着 `vo/manifest.json` 的 `text` 看。**不允许的差异**是漏字、多字、专有名词读错；同音字和标点差异可以放过。

发现读错的，**改文案重生成那一条**，不要试图用后期修。改法优先换词（见阶段 1 多音字那节），连续两次读错说明这个说法本身不适合 TTS。

---

## 阶段 4：ChatCut Desktop 剪辑

### 4.1 前置检查（先自检，再干活）

进入本阶段第一件事是跑工具自检（`scripts/check-tools.sh` 或 `scripts/check-tools.ps1`，按系统选，用法见「工具自检」一节）。看 `[chatcut] state=`：

- `running` → 再确认**当前对话有没有 `chatcut_desktop` 工具**。进程在跑但工具不在，是会话加载的问题，不是安装问题 → 让用户**开新对话**。
- `installed-not-running` → 脚本已自动拉起并等过 25 秒。还没进程说明要人工登录，提示用户点开它。
- `not-installed` → 按系统给命令，让用户自己跑：

```powershell
# Windows（PowerShell）
irm https://chatcut.io/install.ps1 | iex
```

```bash
# macOS（终端，脚本自带签名校验，不需要 sudo）
curl -fsSL https://chatcut.io/install.sh | sh
```

装完让用户在 ChatCut 里**登录**，然后**开一个新对话**（工具在会话开始加载，装的那一轮拿不到）。DSH 不在自动连接列表里，要在 ChatCut 的 **Agents on this computer → Connect any agent** 手动加。

ChatCut 缺失时的降级：阶段 0–3 照做，`vo/` 出来后输出一份**给剪辑师看的导入清单**（素材顺序、入切点、每轨音量、字幕文案、BGM 要求），把「剪」这一步交给人。**不要承诺"我帮你剪好了"**——没有工具就动不了时间线。

其他硬限制，先跟用户说清楚再动手：

- **Linux 不支持**，Windows 10 (2004+) x64 或 macOS 13+。
- **不能离线**，登录和托管生成都要网。
- **积分**：上传/转写/手动剪/本地导出免费；**agent 每一轮对话和所有 AI 生成都扣积分**。
- **云导出 4K 出不来**，4K 只能 Desktop 本地渲染。
- **agent 提交的云导出不弹确认框直接扣钱**——导出一律要求走浏览器或 Desktop 本地。

### 4.2 标准操作序列

1. `create_project` 建工程（或 `target_project` 选中已有工程，`openWindow=true` 才开窗）。
2. `read_project` 确认现有 timeline 和 asset，**别在没读之前就动**。
3. `push_asset` 逐个推入：`assets/` 全部素材、`vo/*.wav`、`motion/out/*.mp4`（onetake 动效段）、`remotion/out/*.mov`、（BGM 若已在本地）。
4. **先铺口播**：按 `manifest.json` 顺序把 wav 首尾相接铺满主音轨，这是整条片子的时基。中间不留空隙（除非镜表里明确写了留白）。
5. 按镜表放画面。素材原声的片段**音量设 0**（用户明确要求；也让口播清楚）。onetake 动效段自带音效：**要么保留它、要么整段静音**，别和 BGM 叠两层（口播压在它上面时统一降到 -18 dB 以下）。
6. 转写**用口播音频**（不是素材原声），生成字幕，逐条校对专有名词和数字。
7. 加 BGM（见 4.3）。
8. 结尾关注引导（见 4.4）。
9. 自查 QA 清单，再导出。

### 4.3 BGM：从哪来、怎么挑、怎么量

#### 4.3.0 先分清三种声音（来源完全不同，别混）

| 声音 | 谁出 | 结论 |
|---|---|---|
| **整片底板 BGM**（铺满全片的那一首） | 外部授权曲库 | 只能去 4.3.1 找。onetake 和 Remotion **都不产音乐**，别指望它们 |
| **动效段内部的音效与打点**（onetake 出的段） | onetake 自己：`sfx_palette.py` + `score.py`，按 `__events()` 打点、所有声音共用一个房间、母带 -16 LUFS | 段内自带。**不要再给它铺一首 BGM**——它的作者被用户否决过"音乐太吵、动作声听不见"的版本 |
| **Remotion 叠层的 1–2 个音效** | 现成音效库，或从 onetake 的 palette 导一个 wav | Remotion 不做音乐，只有 `<Audio>` 摆位，不进 BGM 决策 |
| **实在找不到合适曲子** | AI 生成：`skill:chatcut-music`（ChatCut / Suno 路线） | 兜底用。生成物别注册到任何版权系统，商用条款按平台现行版本 |

一句话：**底板归曲库，段内音效归 onetake，AI 只做兜底。**

#### 4.3.1 整片底板 BGM 去哪找（按优先级）

| 情况 | 去哪 | 授权要点 |
|---|---|---|
| **默认**：免费商用、要跨平台分发 | Pixabay Music `https://pixabay.com/music/` | 免署名、可商用、下载不用账号，29 万+ 首。**带盾牌图标的曲子已在 YouTube Content ID 注册**，优先挑没盾牌的；下载页的链接 + 文件名 + 授权说明存进台账 |
| 要更精致的电影感，仍免费 | Mixkit `https://mixkit.co/free-stock-music/` | 免注册、免署名；音乐授权只覆盖线上/社媒/VOD/播客/广告，**不含影视、游戏、电视广播** |
| 中文检索、国风/民俗/民乐 | 爱给网 `https://www.aigei.com/music/` | 只在 **CC 专区**挑标注 CC0 / 公共版权的（16 万+ 首）；其余是付费授权，别顺手拿 |
| 想在多个源里一次搜 | 淘声网 `https://www.tosound.com/` | 它只是聚合搜索，授权沿用原始来源。**必须点进详情看协议**：CC0 / CC BY（要署名）/ CC BY-NC（**非商用**，商用账号不能用） |
| 高频产出、要授权凭证兜底 | Uppbeat（约 $6.99/月起）、Epidemic Sound、国内光厂（59 元/首起，随片永久 + 授权书） | 付费档才有广告/客户项目权限；Uppbeat 免费档 3 首/月且必须署名 |
| 实在找不到合适的 | `skill:chatcut-music` 生成（ChatCut AI 音乐约 0.22 积分/条） | 生成物别注册版权系统；生成曲没有"手工作曲"的细腻度，只用在不抢口播的底 |

Mixkit 的直链可以脚本化抓取（分类页里的 JSON-LD 带 `name`/`byArtist`/`duration`/`url`），Pixabay 有反爬、只能手动下——所以本地曲库现在全是 Mixkit。

**两个必须知道的坑**：

1. **平台自带曲库不能跨平台用**。抖音商用音乐库、剪映曲库、B 站音频库、YouTube Audio Library 的授权都绑定"在该平台内发布"。我们导出的是 mp4、再用分发工具发到视频号/小红书/B 站——这已经是越界。**多平台分发只能自带曲库的曲子**。
2. **"免费下载" ≠ "可商用"**。CC BY-NC 的 NC 就是非商用；商用账号发出去照样侵权。只认 CC0 或明确写 commercial use allowed 的来源。

#### 4.3.2 口播片挑曲的五条硬指标

1. **无强人声**。有人声会和口播抢频段，中文尤其明显。
2. **BPM 70–110 或没有明显鼓点**。口播要的是"垫"，不是"推"。
3. **低频薄**。底鼓/贝斯厚的曲子会把口播压糊，试听重点听 100 Hz 以下。
4. **时长 ≥ 全片 × 1.2**，或本身是 loop 友好结构；结尾留 1–2 秒淡出，不要突然截断。
5. **情绪与段落一致**（讲问题→低频铺底、悬停感；讲结果→明亮上行）。**整片一首**，别中途切歌。

#### 4.3.3 音量和量化（先量再调）

| 轨道 | 目标 | 说明 |
|---|---|---|
| 口播 | 主导，全片唯一"必须听清"的轨 | 峰值不削波，整体对齐 -14 LUFS（ChatCut 的预览/导出口径） |
| BGM | 比口播低 18–22 dB | 换算成绝对值：**先拉到 -32 ~ -36 LUFS**，再按耳朵微调；开口处 ducking，句间可回升 2–3 dB |
| 素材原声 | **0（静音）** | 用户要求；需要保留的环境音单独提出来做很低的一层 |
| 音效 | 峰值不超过口播 -6 dB | 只在转场/强调点出现 |
| onetake 动效段（保留其音轨时） | 整段先降到 **-26 ~ -30 LUFS** | 它自带的是 -16 LUFS 的完整混音，比口播只低 2 dB——原样放会顶掉人声。降下来后再叠 BGM 就变成三层，所以规定：**保留段音轨时，全片不再铺 BGM** |

别靠耳朵猜候选曲的响度，先量：

```bash
bash <技能目录>/scripts/bgm-check.sh ~/Music/bgm/*.mp3 --need 62
```

输出每首的时长、integrated LUFS、真峰值、LRA，并给出"降到 -34 LUFS 需要的增益"；时长不够全片、或本身已经是 -20 LUFS 以上的响母带，会直接标出来。

#### 4.3.4 本地曲库 + 台账（一次建库，长期复用）

- **库里已经有货了**：`~/Music/bgm/` 现有 6 首 Mixkit（`calm` ×2 / `uplift` / `tense` / `tech` / `outro`），索引见 `~/Music/bgm/README.md`，授权与实测响度见 `~/Music/bgm/license-ledger.md`。**先从这里挑，挑不到再去 4.3.1 找。**
- 命名 `情绪-时长-来源-曲名`：`calm-2m14-mixkit-finding-myself.mp3`。按情绪前缀筛，比每次重新搜快得多。
- 现代曲库的母带都很响（实测这批 -10 ~ -12 LUFS），进 ChatCut 的 **bed gain 基本在 -20 ~ -24 dB**，不是象征性降几个 dB。低频占比（<120 Hz）超 35% 的曲子，压之前先做 120 Hz 低切。
- 每个项目复制一份台账到 `bgm/license-ledger.md`：

  | 文件 | 曲名 | 作者 | 授权 | 实测响度 | 用在哪 |
  |---|---|---|---|---|---|
  | calm-2m14-mixkit-finding-myself.mp3 | Finding Myself | Michael Ramir C. | Mixkit Free（免署名，商用可） | -21.9 LUFS，bed gain -12.1 dB | 全片底 |

  被平台判侵权时，这张表就是申诉材料。**没有台账的曲子不进成片。**

### 4.4 结尾关注引导

单独一段，2–3 秒，固定版式：

- 画面：账号头像/Logo + 账号名 + "关注"按钮示意（**优先用 onetake 做一个 2–3 秒的动效段**，落款/字标带承接；简单版可退 Remotion 文字卡或 ChatCut 动效）
- 文案：一句具体的话（"想看成片背后的完整方案，主页有"），不要"点赞关注不迷路"这种通用套话
- 音频：口播念这句，或纯 BGM 留白都可，但**不要突然静音**——BGM 淡出而不是切断

### 4.5 导出

```text
格式：MP4 (H.264)
分辨率：横屏 1920×1080 / 竖屏 1080×1920
帧率：与工程一致（30fps）
音频：AAC 192kbps 以上
```

**必须本地渲染**（Desktop 本地导出或浏览器导出），云渲染上限 1080p 且 agent 提交不确认扣费。4K 只有 Desktop 本地能出。

---

## QA 清单（逐项真跑，不许写"应该没问题"）

1. `vo/manifest.json` 总秒数 vs 目标时长，偏差超 ±8% 说明文案或语速要调。
2. 逐句 ASR 回读 diff 干净（阶段 3.5 已做，这里复看一遍）。
3. 抽三帧看：首帧、任一 onetake 动效段的中间帧（确认没有黑场/串帧）、任一 Remotion 叠加帧（确认透明通道正确、没黑边）、结尾引导帧。
4. **完整看一遍带声音**：口播有没有被 BGM 盖住、切点有没有跳帧、字幕有没有超出安全区、有没有露出的黑场。
5. 素材原声片段音量确认是 0。
6. BGM 已量过（`bgm-check.sh`）、已拉到 -32 ~ -36 LUFS，`bgm/license-ledger.md` 有这一首的授权记录。
7. 导出文件用播放器再开一次（不是只看 ChatCut 预览），确认时长和音轨都在。

---

## 失败处理

| 现象 | 处理 |
|---|---|
| `curl /profiles` 连不上 | Voicebox 没启动，让用户开桌面端；不要反复重试 |
| 首次生成卡很久 | 在下模型，看 Voicebox UI 的下载进度，别 kill |
| 生成音频有电流声/截断 | 换 `max_chunk_chars` 调小（默认 800 → 400），或把该句拆短重生成 |
| ASR 回读漏字 | 该句重生成；连续两次失败就改文案（改用词而非调参数） |
| ChatCut 工具不存在 | 装 Desktop → 登录 → **开新对话**；重装没用 |
| `create_project` 却没开窗 | 正常，窗口默认关闭。记下 project ID，要看得再 `target_project` 加 `openWindow=true`，且 Desktop 必须已在运行 |
| Remotion 叠加画面抖动 | 帧率不一致。工程、Remotion、导出三处必须同 fps |
| 叠加画面边缘有黑底 | 透明参数没生效。检查 `--codec=prores --prores-profile=4444 --pixel-format=yuva444p10le`，或改用 `@remotion/media` 的 `<Video>` |
| onetake 静帧全黑/空页 | comp 的 `window.__ready` 没解析（字体或图片没加载完）。先跑 `look.py apply` 生成 `look.js` 并在 comp 前加载，确认 `__ready` 串联了 `LOOK.ready` |
| onetake 渲染极慢 | 草稿别用 `--final`；`--workers` 默认 核心数−2，别超过 8；WebGL 的 comp 必须加 `--gpu`，否则软件渲染慢约 4 倍。**开渲前把预计耗时告诉用户** |
| onetake 出的段进 ChatCut 后音画不同步 | 段内自带音效轨被拖偏。整段连同音轨一起移动，或整段静音只留口播+BGM |
| 导出被发现扣了积分 | 走了云导出。下次明确要求本地/浏览器导出 |

---

## 授权与边界

- **语音克隆只用于用户本人或有明确书面授权的声音**。要克隆他人声音，先要授权凭据，没有就不做。
- 素材版权：用户提供的素材默认其有权使用；引用的第三方画面/音乐在成片里要标注来源，商用前提醒用户确认。
- 不在成片里生成真人肖像（数字人）除非用户提供了肖像权依据。