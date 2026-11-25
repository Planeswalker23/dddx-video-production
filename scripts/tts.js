#!/usr/bin/env node
// tts.mjs - split a script into sentences, synthesize each one with Voicebox,
// and emit a manifest of real per-sentence durations so the edit plan can be rebuilt.
//
// Node 18+ (global fetch). No npm dependencies on purpose: this must run on a
// freshly installed machine with nothing but node.
//
// Usage:
//   node tts.mjs --text 01-script-final.md --dry-run
//   node tts.mjs --text 01-script-final.md --out vo --profile "我的音色" --engine qwen
//   node tts.mjs --text 01-script-final.md --out vo --profile "我的音色" --verify

import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const API = (process.env.VOICEBOX_API || 'http://127.0.0.1:17493').replace(/\/+$/, '');
const CHARS_PER_SECOND = 4.5; // Chinese narration, moderate pace

// ---------------------------------------------------------------- arguments

function parseArgs(argv) {
  const opts = {
    text: null,
    out: 'vo',
    profile: null,
    engine: null,
    lang: 'zh',
    maxChunk: 800,
    maxLen: 30,
    instruct: null,
    seed: null,
    dryRun: false,
    verify: false,
  };
  const known = {
    '--text': (v) => (opts.text = v),
    '--out': (v) => (opts.out = v),
    '--profile': (v) => (opts.profile = v),
    '--engine': (v) => (opts.engine = v),
    '--lang': (v) => (opts.lang = v),
    '--max-chunk': (v) => (opts.maxChunk = Number(v)),
    '--max-len': (v) => (opts.maxLen = Number(v)),
    '--instruct': (v) => (opts.instruct = v),
    '--seed': (v) => (opts.seed = Number(v)),
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') { opts.dryRun = true; continue; }
    if (a === '--verify') { opts.verify = true; continue; }
    if (a === '--help' || a === '-h') { usage(); process.exit(0); }
    const fn = known[a];
    if (!fn) {
      fail(`未知参数：${a}\n用 --help 看可用参数。`);
    }
    const v = argv[i + 1];
    if (v === undefined || v.startsWith('--')) fail(`参数 ${a} 缺少值。`);
    fn(v);
    i++;
  }
  if (!opts.text) fail('缺少 --text（要念的文案文件）。');
  if (!opts.dryRun && !opts.profile) {
    fail('缺少 --profile（音色 id 或名字）。先跑 curl ' + `${API}/profiles` + ' 看有哪些。');
  }
  return opts;
}

function usage() {
  console.log(`用法：node tts.mjs --text <文件> [选项]

  --text <file>       必填。定稿文案，一句一行。
  --out <dir>         输出目录，默认 vo。
  --profile <id|名字> 音色。--dry-run 时可省。
  --engine <name>     qwen | qwen_custom_voice | chatterbox | chatterbox_turbo | kokoro | luxtts | tada
  --lang <code>       语言，默认 zh。
  --max-chunk <n>     单次请求最大字符，默认 800。
  --max-len <n>       单句最大字数，超过则按逗号二次切分，默认 30。
  --instruct <text>   语气指令。只有 qwen_custom_voice 真正生效。
  --seed <n>          随机种子，便于复现。
  --dry-run           只切句、算预估秒数，不调 API。
  --verify            生成后用 /transcribe 逐句回读校验，写 asr.json。

环境变量：VOICEBOX_API 覆盖服务地址，默认 ${API}`);
}

function fail(msg) {
  console.error(`✗ ${msg}`);
  process.exit(1);
}

// ---------------------------------------------------------------- splitting

// Split into speakable sentences. Drops markdown scaffolding lines that would
// otherwise be read aloud, then splits on strong punctuation, then re-splits
// anything still too long at a comma.
function splitSentences(raw, maxLen) {
  const lines = raw.split(/\r?\n/);
  const kept = [];
  for (const line of lines) {
    const t = line.trim();
    if (!t) continue;
    if (/^[#>\-*|`]/.test(t)) continue; // headings, quotes, bullets, tables, code fences
    if (/^\d+[.)]\s/.test(t)) continue; // ordered list markers
    kept.push(t);
  }
  const joined = kept.join('');

  const rough = joined
    .split(/(?<=[。！？；…!?;])/)
    .map((s) => s.trim())
    .filter(Boolean);

  const out = [];
  for (const s of rough) out.push(...splitLong(s, maxLen));
  return out;
}

function splitLong(sentence, maxLen) {
  if (sentence.length <= maxLen) return [sentence];
  // Prefer breaking after a comma/semicolon; keep the punctuation with the head.
  const parts = sentence
    .split(/(?<=[，,、：:])/)
    .map((s) => s.trim())
    .filter(Boolean);
  if (parts.length === 1) {
    // No comma to break at - hard split so we still produce something speakable.
    const chunks = [];
    for (let i = 0; i < sentence.length; i += maxLen) {
      chunks.push(sentence.slice(i, i + maxLen));
    }
    return chunks;
  }
  const merged = [];
  let buf = '';
  for (const p of parts) {
    if (buf && (buf + p).length > maxLen) {
      merged.push(buf);
      buf = p;
    } else {
      buf = buf ? buf + p : p;
    }
  }
  if (buf) merged.push(buf);
  return merged;
}

function countChars(s) {
  // Count only what gets spoken: no whitespace, no punctuation.
  return s.replace(/[\s\p{P}]/gu, '').length;
}

// ---------------------------------------------------------------- wav probe

// Real duration from the RIFF header: byteRate at offset 28, data chunk size.
function wavSeconds(file) {
  const buf = readFileSync(file);
  if (buf.length < 44 || buf.toString('ascii', 0, 4) !== 'RIFF') return null;
  const byteRate = buf.readUInt32LE(28);
  if (!byteRate) return null;
  let off = 12;
  while (off + 8 <= buf.length) {
    const id = buf.toString('ascii', off, off + 4);
    const size = buf.readUInt32LE(off + 4);
    if (id === 'data') {
      const dataSize = Math.min(size, buf.length - off - 8);
      return dataSize / byteRate;
    }
    off += 8 + size + (size % 2);
  }
  return (buf.length - 44) / byteRate;
}

// ---------------------------------------------------------------- API calls

async function apiFetch(pathname, init) {
  const url = `${API}${pathname}`;
  let res;
  try {
    res = await fetch(url, init);
  } catch (e) {
    fail(
      `连不上 Voicebox（${url}）：${e.message}\n` +
        '先跑 scripts/check-tools.sh（macOS/Linux）或 scripts/check-tools.ps1（Windows）看 state，或手动启动 Voicebox 桌面端。'
    );
  }
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    fail(`Voicebox 返回 ${res.status}：${body.slice(0, 400)}`);
  }
  return res;
}

async function resolveProfile(wanted) {
  const res = await apiFetch('/profiles');
  const list = await res.json();
  if (!Array.isArray(list) || list.length === 0) {
    fail('Voicebox 里没有任何音色。先在桌面端创建/克隆一个再来。');
  }
  const w = String(wanted).toLowerCase();
  const hit =
    list.find((p) => String(p.id).toLowerCase() === w) ||
    list.find((p) => String(p.name || '').toLowerCase() === w);
  if (!hit) {
    const names = list.map((p) => `  ${p.id}  ${p.name || '(未命名)'}`).join('\n');
    fail(`找不到音色 "${wanted}"。可用的有：\n${names}`);
  }
  return hit;
}

async function generate(opts, profile, text) {
  const body = {
    profile_id: profile.id,
    text,
    language: opts.lang,
    max_chunk_chars: opts.maxChunk,
  };
  if (opts.engine) body.engine = opts.engine;
  if (opts.seed !== null) body.seed = opts.seed;
  if (opts.instruct) body.instruct = opts.instruct;
  const res = await apiFetch('/generate', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  return res.json();
}

// ---------------------------------------------------------------- main

async function main() {
  const opts = parseArgs(process.argv);

  let raw;
  try {
    raw = await readFile(opts.text, 'utf8');
  } catch (e) {
    fail(`读不到文案文件 ${opts.text}：${e.message}`);
  }

  const sentences = splitSentences(raw, opts.maxLen);
  if (sentences.length === 0) fail('切出来 0 句。检查文件是否为空，或整篇都是 markdown 结构行。');

  if (opts.dryRun) {
    let chars = 0;
    sentences.forEach((s, i) => {
      const c = countChars(s);
      chars += c;
      console.log(`  ${String(i + 1).padStart(3, '0')} [${c}字] ${s}`);
    });
    const est = chars / CHARS_PER_SECOND;
    console.log('');
    console.log(
      `切出 ${sentences.length} 句，共 ${chars} 字，预估 ${est.toFixed(3)} 秒（${CHARS_PER_SECOND} 字/秒）`
    );
    console.log('--dry-run：未调用 API。检查上面切句是否合理，尤其专有名词有没有被切断。');
    return;
  }

  const profile = await resolveProfile(opts.profile);
  console.log(`音色：${profile.name || '(未命名)'} (${profile.id})`);
  console.log(`引擎：${opts.engine || '(服务端默认)'}　语言：${opts.lang}`);
  console.log(`共 ${sentences.length} 句，输出到 ${opts.out}/`);
  console.log('');

  await mkdir(opts.out, { recursive: true });

  const manifest = {
    generatedAt: new Date().toISOString(),
    api: API,
    engine: opts.engine || null,
    language: opts.lang,
    profile: { id: profile.id, name: profile.name || null },
    totalSeconds: 0,
    sentences: [],
  };

  let cursor = 0;
  for (let i = 0; i < sentences.length; i++) {
    const text = sentences[i];
    const n = i + 1;
    const label = String(n).padStart(3, '0');
    process.stdout.write(`  ${label} 生成中… ${text.slice(0, 24)}${text.length > 24 ? '…' : ''}`);

    const result = await generate(opts, profile, text);
    const file = path.join(opts.out, `${label}.wav`);

    if (result.audio_path && existsSync(result.audio_path)) {
      await copyFile(result.audio_path, file);
    } else if (result.id || result.generation_id) {
      const id = result.id || result.generation_id;
      const res = await apiFetch(`/audio/${id}`);
      const bytes = Buffer.from(await res.arrayBuffer());
      await writeFile(file, bytes);
    } else {
      fail(`第 ${n} 句没有返回 audio_path 也没有 id：${JSON.stringify(result).slice(0, 300)}`);
    }

    const seconds = wavSeconds(file);
    if (seconds === null) {
      fail(`第 ${n} 句落地的文件不是合法 WAV：${file}`);
    }

    manifest.sentences.push({
      index: n,
      text,
      file: `${label}.wav`,
      seconds: Number(seconds.toFixed(3)),
      start: Number(cursor.toFixed(3)),
    });
    cursor += seconds;
    process.stdout.write(`\r  ${label} ${seconds.toFixed(3)}s  累计 ${cursor.toFixed(2)}s   ${text.slice(0, 32)}\n`);
  }

  manifest.totalSeconds = Number(cursor.toFixed(3));
  await writeFile(path.join(opts.out, 'manifest.json'), JSON.stringify(manifest, null, 2), 'utf8');

  console.log('');
  console.log(`完成：${manifest.sentences.length} 句，总时长 ${manifest.totalSeconds} 秒`);
  console.log(`清单：${path.join(opts.out, 'manifest.json')}`);
  console.log('用 manifest.json 里的真实秒数重排镜表（阶段 2），不要反过来改音频去凑画面。');

  if (opts.verify) {
    await verifyAll(opts, manifest);
  }
}

// ---------------------------------------------------------------- verify

// Ignore punctuation and whitespace: ASR output never matches it exactly.
function norm(s) {
  return s.replace(/[\s\p{P}\p{S}]/gu, '');
}

async function verifyAll(opts, manifest) {
  console.log('');
  console.log('ASR 回读校验（逐句 /transcribe）…');
  const report = [];
  let bad = 0;

  for (const item of manifest.sentences) {
    const file = path.join(opts.out, item.file);
    const bytes = await readFile(file);
    const form = new FormData();
    form.append('file', new Blob([bytes], { type: 'audio/wav' }), item.file);
    form.append('language', opts.lang);

    const res = await apiFetch('/transcribe', { method: 'POST', body: form });
    const data = await res.json();
    const heard = data.text || '';
    const same = norm(heard) === norm(item.text);
    if (!same) bad++;
    report.push({
      index: item.index,
      expected: item.text,
      heard,
      match: same,
    });
    console.log(`  ${String(item.index).padStart(3, '0')} ${same ? '✓' : '✗'} ${heard}`);
    if (!same) {
      console.log(`      期望：${item.text}`);
    }
  }

  await writeFile(path.join(opts.out, 'asr.json'), JSON.stringify(report, null, 2), 'utf8');
  console.log('');
  if (bad === 0) {
    console.log(`ASR 校验通过：${report.length} 句全部一致。`);
  } else {
    console.log(`ASR 校验发现 ${bad} 句不一致（详见 ${path.join(opts.out, 'asr.json')}，已忽略标点差异）。`);
    console.log('漏字/多字/专有名词读错必须改；同音字可放过。改文案后重生成那一条。');
  }
}

main().catch((e) => {
  console.error(`✗ ${e.stack || e.message}`);
  process.exit(1);
});