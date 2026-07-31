---
name: remote-debug-edge
description: Remote debug Microsoft Edge browser via CDP from WSL2. Use when Codex needs to extract page content, control browser tabs, read AI chat conversations (DeepSeek, ChatGPT, Claude, Doubao), or interact with any web page open in the user's Edge browser. Requires Edge running with --remote-debugging-port=9222 on Windows and a CDP bridge in WSL2.
---

# Edge Remote Debug

Remotely control the user's Microsoft Edge browser from WSL2 via Chrome DevTools Protocol (CDP).

## Prerequisites

**Windows side** -- user must start Edge with remote debugging:

```powershell
taskkill /f /im msedge.exe 2>$null
& "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" `
  --remote-debugging-port=9222 `
  --remote-debugging-address=0.0.0.0 `
  --user-data-dir="D:\edge-debug"
```

WSL2 mirrored-mode auto-maps `localhost:9222` from WSL2 to the Windows Edge CDP endpoint. No additional networking config needed.

**WSL2 side** -- user must start the CDP bridge (once per session):

```bash
node ~/WORKS/remote-debug-edge/scripts/cdp-bridge.js &
```

Requires `ws` system module (`apt install node-ws`). The bridge creates an HTTP relay on `127.0.0.1:9223` that Codex MCP browser tools can reach, forwarding CDP commands to Edge's WebSocket.

## Architecture

```
Codex MCP browser  --HTTP-->  :9223 bridge  --WS-->  Edge :9222 CDP
(playwright/chrome)          (Node.js relay)          (Windows host)
```

The MCP browser tools (`browser_evaluate`, `browser_run_code_unsafe`) can send HTTP requests to `localhost:9223`. The bridge relays POST `/cdp` to Edge CDP and returns responses. GET requests are forwarded to Edge's HTTP API (`/json`, `/json/version`, etc.).

## Core CDP Flow

### 1. List open pages

```
GET http://localhost:9223/json
```

Returns array of page objects with `id`, `url`, `title`, `webSocketDebuggerUrl`.

### 2. Attach to a page

Send via POST `/cdp`:
```json
{"method": "Target.attachToTarget", "params": {"targetId": "<PAGE_ID>", "flatten": true}}
```
Returns `{"result": {"sessionId": "<SID>"}}`.

### 3. Run JavaScript on the page

```json
{"method": "Runtime.evaluate", "params": {"expression": "document.title", "returnByValue": true}, "sessionId": "<SID>"}
```

### 4. Detach

```json
{"method": "Target.detachFromTarget", "params": {}, "sessionId": "<SID>"}
```

## Extracting Page Content

Use `scripts/extract.js` for common extraction tasks, or implement inline via MCP tools.

### Quick extraction via script

```bash
# Extract from a page matching URL substring, with virtual scroll handling
node scripts/extract.js deepseek --scroll
node scripts/extract.js chatgpt --scroll
node scripts/extract.js bing
```

### Inline extraction via MCP browser

When extracting from MCP tools, send CDP commands via `fetch` to `http://localhost:9223/cdp` from within `browser_evaluate`:

```js
// Attach
const r = await fetch('http://localhost:9223/cdp', {
  method: 'POST', headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({method: 'Target.attachToTarget', params: {targetId: pageId, flatten: true}})
});
const {result: {sessionId}} = await r.json();

// Evaluate
const r2 = await fetch('http://localhost:9223/cdp', {
  method: 'POST', headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({method: 'Runtime.evaluate', params: {expression: 'document.body.innerText', returnByValue: true}, sessionId})
});
const text = (await r2.json()).result?.result?.value;
```

## Handling Virtual Scrolling (SPAs)

Single-page apps (DeepSeek, ChatGPT, etc.) use virtual scrolling: DOM nodes outside the viewport are recycled. Only visible messages exist in the DOM at any time.

**Fix**: Scroll the chat container to top before extraction, repeating several times to force all messages to render:

```js
for (let i = 0; i < 8; i++) {
  await cdp('Runtime.evaluate', {
    expression: `(function(){
      const els = document.querySelectorAll('div');
      for (const el of els) {
        if (el.scrollHeight > el.clientHeight + 200) { el.scrollTop = 0; }
      }
    })()`,
    returnByValue: true
  }, sessionId);
  await new Promise(r => setTimeout(r, 600));
}
```

After scrolling, re-extract the page content -- all messages should now be in the DOM.

## AI Chat Extraction Strategy

For AI chat pages (DeepSeek, ChatGPT, Claude, Doubao), the chat messages are in the main content area. To find them:

1. Attach to the page via CDP
2. If the page shows only sidebar (conversation list), click a conversation to load it:
   ```js
   const divs = document.querySelectorAll('div');
   for (const d of divs) {
     if (d.innerText?.trim() === 'CONVERSATION_TITLE' && !d.querySelector('*')) {
       d.parentElement?.click(); break;
     }
   }
   ```
3. Handle virtual scrolling (see above)
4. Extract the largest text container containing AI markers

Common AI markers to search for: `内容由 AI 生成`, `深度思考`, `复制代码`, `Copy code`, `ChatGPT`, `Claude`, `Regenerate`.

## Non-AI Page Extraction

For regular web pages (forums, search results, documentation):

- **Search results**: Target `#b_results li.b_algo` (Bing) or `#search .g` (Google)
- **Forums**: Target topic titles and post content using site-specific selectors
- **Documentation**: Extract from `<main>`, `<article>`, or the largest text block

Use `document.querySelector` or `document.querySelectorAll` with site-specific CSS selectors for structured extraction.

## Troubleshooting

- **Bridge not reachable**: Check `curl http://localhost:9223/health` returns `OK`. If not, restart the bridge.
- **Edge CDP not reachable**: Confirm Edge is running with `--remote-debugging-port=9222`. Check `curl http://localhost:9222/json/version`.
- **WebSocket 403 from MCP browser**: Normal -- browser-to-browser WebSocket connections are blocked. Always go through the bridge.
- **Empty extraction from SPA**: Page uses virtual scrolling. Use `--scroll` flag or the scroll-top loop before extracting.
- **Session detached**: Page navigation or tab switch may detach the CDP session. Re-attach before subsequent operations.
