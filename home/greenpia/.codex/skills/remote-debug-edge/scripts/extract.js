// Page Content Extractor via CDP Bridge
// Usage: node extract.js [page-filter] [--scroll]
//   page-filter: substring to match in page URL (e.g., "deepseek", "chatgpt", "bing")
//   --scroll: scroll to top first to load all virtual-scroll content (SPAs)
// 
// Examples:
//   node extract.js deepseek --scroll    # Extract DeepSeek chat, handle virtual scroll
//   node extract.js bing                 # Extract Bing search results
//   node extract.js debiancn             # Extract Debian forum content

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

async function main() {
  const args = process.argv.slice(2);
  const filter = args.find(a => !a.startsWith('--')) || '';
  const shouldScroll = args.includes('--scroll');

  if (!(await healthCheck())) {
    console.error('Bridge not running. Start with: node cdp-bridge.js &');
    process.exit(1);
  }

  const pages = await getJson('/json');
  const target = pages.find(p => p.url?.includes(filter));
  if (!target) { console.log(`No page matching "${filter}" found. Open pages: ${pages.map(p => p.url).join(', ')}`); return; }

  console.log(`=== ${target.title} ===`);
  console.log(`URL: ${target.url}\n`);

  const attach = await cdp('Target.attachToTarget', { targetId: target.id, flatten: true });
  const sid = attach.result.sessionId;
  await cdp('Runtime.enable', {}, sid);

  // Virtual scroll handling: scroll to top repeatedly to force lazy-loaded content into DOM
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

  // Extract content: find largest meaningful text container
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
      // Fallback: return visible page text (excluding obvious nav/sidebar)
      return document.body?.innerText?.slice(0, 8000) || 'empty';
    })()`,
    returnByValue: true
  }, sid);

  const text = result.result?.result?.value || 'no content';
  console.log(text);

  await cdp('Target.detachFromTarget', {}, sid);
}

main().catch(e => { console.error(e.message); process.exit(1); });
