#!/usr/bin/env node
// Universal CDP CLI via bridge
// Usage: node cdp.js list | attach <filter> | eval <expr> | nav <url> | capture [filter] [--scroll] | open <url> | health

const http = require('http');
const BRIDGE = { hostname: '127.0.0.1', port: 9223 };

let SESSION_ID = null;
let TARGET_ID = null;

function cdp(method, params) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ method, params, ...(SESSION_ID ? { sessionId: SESSION_ID } : {}) });
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

async function health() {
  return new Promise((resolve) => {
    http.get({ ...BRIDGE, path: '/health' }, res => resolve(res.statusCode === 200))
      .on('error', () => resolve(false));
  });
}

async function listPages() {
  const pages = await getJson('/json');
  for (const p of pages) {
    if (p.type === 'page') console.log(`${p.id.slice(0,6)}... | ${(p.title||'').slice(0,50)} | ${(p.url||'').slice(0,80)}`);
  }
}

async function attach(filter) {
  const pages = await getJson('/json');
  const target = pages.find(p => p.url?.includes(filter));
  if (!target) { console.error(`No page matching "${filter}"`); process.exit(1); }
  TARGET_ID = target.id;
  const r = await cdp('Target.attachToTarget', { targetId: target.id, flatten: true });
  SESSION_ID = r.result.sessionId;
  console.log(`attached to "${target.title}" [${target.id}]`);
}

async function evaluate(expr) {
  if (!SESSION_ID) { console.error('Not attached. Use: node cdp.js attach <filter> first'); process.exit(1); }
  const r = await cdp('Runtime.evaluate', { expression: expr, returnByValue: true });
  const val = r.result?.result?.value;
  console.log(typeof val === 'string' ? val : JSON.stringify(val, null, 2));
}

async function navigate(url) {
  if (!SESSION_ID) { console.error('Not attached'); process.exit(1); }
  const r = await cdp('Page.navigate', { url });
  console.log('navigated:', r.result?.frameId);
}

async function openTab(url) {
  const r = await cdp('Target.createTarget', { url });
  console.log('new tab:', r.result?.targetId);
}

async function capture(filterArg, scroll) {
  if (filterArg && !SESSION_ID) {
    const pages = await getJson('/json');
    const target = pages.find(p => p.url?.includes(filterArg));
    if (!target) { console.error(`No page matching "${filterArg}"`); process.exit(1); }
    TARGET_ID = target.id;
    const r = await cdp('Target.attachToTarget', { targetId: target.id, flatten: true });
    SESSION_ID = r.result.sessionId;
  }
  if (!SESSION_ID) { console.error('Not attached'); process.exit(1); }

  if (scroll) {
    for (let i = 0; i < 6; i++) {
      await cdp('Runtime.evaluate', {
        expression: `(function(){
          const els = document.querySelectorAll('div');
          for (const el of els) {
            if (el.scrollHeight > el.clientHeight + 200) el.scrollTop = 0;
          }
        })()`,
        returnByValue: true
      });
      await new Promise(r => setTimeout(r, 500));
    }
  }

  const r = await cdp('Runtime.evaluate', {
    expression: 'document.body.innerText.slice(0, 8000)',
    returnByValue: true
  });
  console.log(r.result?.result?.value || '(empty)');
}

function detectCaptcha(text) {
  const markers = ['安全验证', '百度安全验证', '拼图验证', '拖动下方拼图', 'captcha', 'CAPTCHA'];
  for (const m of markers) if (text?.includes(m)) return true;
  return false;
}

async function main() {
  const args = process.argv.slice(2);
  const cmd = args[0];
  if (!cmd) { console.log('Usage: cdp.js list|attach|eval|nav|capture|open|health'); process.exit(0); }

  switch (cmd) {
    case 'list': return listPages();
    case 'attach': return attach(args[1]);
    case 'eval': return evaluate(args.slice(1).join(' '));
    case 'nav': return navigate(args[1]);
    case 'open': return openTab(args[1]);
    case 'health': {
      const ok = await health();
      console.log(ok ? 'OK' : 'Bridge not reachable');
      process.exit(ok ? 0 : 1);
    }
    case 'capture': {
      const filter = args.find(a => !a.startsWith('--') && a !== 'capture');
      const scroll = args.includes('--scroll');
      return capture(filter, scroll);
    }
    default:
      console.log(`Unknown command: ${cmd}`);
  }
}

main().catch(e => { console.error(e.message); process.exit(1); });
