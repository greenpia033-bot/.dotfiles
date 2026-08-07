// Page Content Extractor via CDP Bridge
// Usage: node extract.js [page-filter] [--scroll] [--all]
//   page-filter: substring to match in page URL (e.g., "deepseek", "chatgpt", "baidu", "wanfang", "cnki")
//   --scroll: handle virtual scrolling for SPAs (DeepSeek, ChatGPT, etc.)
//   --all: return all page text (no AI-marker filtering)

const http = require('http');

const BRIDGE = { hostname: '127.0.0.1', port: 9223 };

function cdp(method, params, sessionId) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ method, params, ...(sessionId ? { sessionId } : {}) });
    const req = http.request({ ...BRIDGE, path: '/cdp', method: 'POST', headers: { 'Content-Type': 'application/json' } }, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve(JSON.parse(data)));
    });
    req.on('error', reject);
    req.write(body); req.end();
  });
}

function getJson(path) {
  return new Promise((resolve, reject) => {
    http.get({ ...BRIDGE, path }, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve(JSON.parse(data)));
    }).on('error', reject);
  });
}

async function healthCheck() {
  return new Promise((resolve) => {
    http.get({ ...BRIDGE, path: '/health' }, res => resolve(res.statusCode === 200))
      .on('error', () => resolve(false));
  });
}

function detectCaptcha(text) {
  const markers = ['安全验证', '百度安全验证', '拼图验证', '拖动下方拼图', 'captcha', 'CAPTCHA'];
  for (const m of markers) if (text?.includes(m)) return true;
  return false;
}

async function main() {
  const args = process.argv.slice(2);
  const filter = args.find(a => !a.startsWith('--') && a !== 'true') || '';
  const shouldScroll = args.includes('--scroll');
  const showAll = args.includes('--all');

  if (!(await healthCheck())) {
    console.error('Bridge not running. Start: node cdp-bridge.js (use tty session, NOT just `&`)');
    process.exit(1);
  }

  const pages = await getJson('/json');
  const target = pages.find(p => p.url?.includes(filter));
  if (!target) {
    console.log(`No page matching "${filter}". Open pages:`);
    for (const p of pages) {
      if (p.type === 'page') console.log(`  ${(p.title||'?').slice(0,40)} | ${(p.url||'').slice(0,80)}`);
    }
    return;
  }

  console.log(`=== ${target.title} ===`);
  console.log(`URL: ${target.url}\n`);

  const attach = await cdp('Target.attachToTarget', { targetId: target.id, flatten: true });
  const sid = attach.result.sessionId;
  await cdp('Runtime.enable', {}, sid);

  // Virtual scroll handling
  if (shouldScroll) {
    for (let i = 0; i < 8; i++) {
      await cdp('Runtime.evaluate', {
        expression: `(function(){
          const els = document.querySelectorAll('div');
          for (const el of els) {
            if (el.scrollHeight > el.clientHeight + 200) { el.scrollTop = 0; }
          }
        })()`,
        returnByValue: true
      }, sid);
      await new Promise(r => setTimeout(r, 600));
    }
  }

  if (showAll) {
    const result = await cdp('Runtime.evaluate', { expression: 'document.body.innerText', returnByValue: true }, sid);
    const text = result.result?.result?.value || 'no content';

    // CAPTCHA detection
    if (detectCaptcha(text)) {
      console.log('CAPTCHA DETECTED - Please complete verification in the Edge window, then re-run.');
      await cdp('Target.detachFromTarget', {}, sid);
      return;
    }

    console.log(text);
  } else {
    // AI chat extraction
    const markers = process.env.MARKERS || '内容由 AI 生成,深度思考,复制代码,Copy code,ChatGPT,Claude,Regenerate';
    const markerList = markers.split(',').map(m => m.trim());

    const result = await cdp('Runtime.evaluate', {
      expression: `(function() {
        const markers = ${JSON.stringify(markerList)};
        const divs = document.querySelectorAll('div');
        let best = null;
        for (const d of divs) {
          const t = d.innerText || '';
          if (t.length > 100 && t.length < 100000 && markers.some(m => t.includes(m))) {
            if (!best || t.length > best.length) best = t;
          }
        }
        if (best) return best;
        return document.body?.innerText?.slice(0, 8000) || 'empty';
      })()`,
      returnByValue: true
    }, sid);
    const text = result.result?.result?.value || 'no content';
    console.log(text);
  }

  await cdp('Target.detachFromTarget', {}, sid);
}

main().catch(e => { console.error(e.message); process.exit(1); });
