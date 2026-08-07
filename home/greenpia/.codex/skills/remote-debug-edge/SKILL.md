---
name: remote-debug-edge
description: Remote debug Microsoft Edge browser via CDP from WSL2. Use when Codex needs to extract page content, control browser tabs, read AI chat conversations (DeepSeek, ChatGPT, Claude, Doubao), or interact with any web page open in the user's Edge browser. Requires Edge running with --remote-debugging-port=9222 on Windows and a CDP bridge in WSL2.
---

# Edge Remote Debug

Remotely control the user's Microsoft Edge browser from WSL2 via Chrome DevTools Protocol (CDP).

## Quick Start

1. **Windows side** - Open `edge://inspect/#remote-debugging`, enable "Allow remote debugging"
2. **WSL side** - Start bridge: `node scripts/cdp-bridge.js` (keep running — see session notes below)
3. **Use** - `node scripts/cdp.js attach <url-filter>` → `eval`, `nav`, `capture`, `open`

## Windows Side: Enable Debugging

**Option A (Recommended):** Open `edge://inspect/#remote-debugging`, check "Allow remote debugging for this browser instance". Server runs at `127.0.0.1:9222`.

**Option B (NAT mode, need 0.0.0.0):**
```powershell
& "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --remote-debugging-port=9222 --remote-debugging-address=0.0.0.0 --user-data-dir="D:\edge-debug"
```

## WSL Side: Start CDP Bridge

```bash
node scripts/cdp-bridge.js   # keep this running!
```
Creates HTTP relay at `127.0.0.1:9223`, forwarding to Edge CDP. Requires `ws` (`apt install node-ws`).

**CRITICAL: Sandbox Trap!** Codex sandbox uses `--unshare-net`. Any curl to `localhost:9222`/`localhost:9223` inside sandbox **always fails** with "Could not connect". **Always use `sandbox_permissions: "require_escalated"`** for CDP calls. Test with: `curl -sS localhost:9223/health` (escalated).

**Bridge lifecycle:** Using `&` or `nohup` inside escalated exec → process dies when session ends. Use a **PTY session** (tty=true) to keep it alive. Stop with `write_stdin(session_id, "\\x03")`.

## Core CDP via curl

```
GET  /json                    → list pages
POST /cdp {"method":"Target.attachToTarget","params":{"targetId":"<ID>","flatten":true}}
     /cdp {"method":"Runtime.evaluate","params":{"expression":"...","returnByValue":true},"sessionId":"<SID>"}
     /cdp {"method":"Target.createTarget","params":{"url":"about:blank"}}
```

Python inline helper (escalated):

```python
def cdp(method, params=None, session_id=None):
    body = {"method": method, "params": params or {}}
    if session_id: body["sessionId"] = session_id
    req = Request("http://localhost:9223/cdp", data=json.dumps(body).encode(), headers={"Content-Type":"application/json"})
    return json.load(urlopen(req, timeout=30))
```

## cdp.js CLI

`scripts/cdp.js` wraps common ops:

```bash
node cdp.js list                    # list pages
node cdp.js attach <url-filter>     # attach
node cdp.js eval "document.title"   # evaluate JS
node cdp.js nav <url>               # navigate
node cdp.js capture [filter] [--scroll]  # extract text
node cdp.js open <url>              # new tab
node cdp.js health                  # check bridge
```

## CAPTCHA / Chinese Sites

CNKI, Baidu Scholar, etc. **trigger CAPTCHA on automated navigation**. Workflow:

1. Navigate → wait 3-5s → check `document.title` or page text
2. If text contains "安全验证" / "百度安全验证" / "拼图验证": tell user to complete verification in Edge window, wait 15-30s, re-check
3. Continue extraction after verification passes

**Site tips:**
- CNKI: too-specific terms → "暂无数据". Use broader keywords ("电动汽车 充电 配电网" not "老旧小区 充电桩 变压器")
- Wanfang: best for journal vol/issue/page metadata, less aggressive CAPTCHA
- Baidu Scholar: moderate CAPTCHA, good for quick metadata
- `extract.js` auto-detects CAPTCHA (`--all` mode)

## Page Extraction

- **AI chats**: `node extract.js deepseek --scroll` (handles virtual scrolling for SPA)
- **Research pages**: `node extract.js baidu --all` (full text + CAPTCHA detection)
- **Structured extraction**: Use Python CDP helper via escalated curl (see Core CDP section)
- **Sites**: Forums: site-specific selectors; Documentation: `<main>`/`<article>`; Search: `#b_results li.b_algo` (Bing)
- **Search results**: Target `#b_results li.b_algo` (Bing) or `#search .g` (Google)
- **Forums/bbs**: Target topic titles and post content using site-specific CSS selectors

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| curl "Failed to connect" | Inside sandbox | Use `require_escalated` |
| Bridge unreachable | Died with `&` | Use PTY session (tty=true) |
| Edge CDP not reachable | Debugging not enabled | Check `edge://inspect`, verify with `curl localhost:9222/json/version` (escalated) |
| SPA returns empty | Virtual scroll | `--scroll` flag, or 6-8x scroll-top loop |
| CNKI "暂无数据" | Search terms too specific | Use broader terms |
| CNKI/Baidu stuck | CAPTCHA | Check title, notify user to verify |
| Session detached | Page navigated | Re-attach |
| MCP browser fails | No WebSocket to bridge | Use direct escaled curl instead |

## Common Mistakes (TL;DR)

1. **Testing in sandbox** → curl always fails. Always escalate.
2. **Bridge with `&`** → dies with session. Use PTY session (tty=true).
3. **No CAPTCHA detection** → hangs on CNKI/Baidu. Check page title for "安全验证".
4. **Too-specific CNKI terms** → zero results. Go broader.
5. **Edge debug not enabled** → 9222 unreachable. Always verify with escalated curl first.
