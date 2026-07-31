// CDP Bridge: HTTP relay to Edge CDP WebSocket
// Start: node cdp-bridge.js
// Listens on :9223, relays POST /cdp to Edge CDP, GET /* to Edge HTTP API
// Requires: npm install ws in the skill directory

const http = require('http');
const WebSocket = require('ws');

async function main() {
  const resp = await fetch('http://localhost:9222/json/version');
  if (!resp.ok) throw new Error('Edge CDP not accessible at localhost:9222. Start Edge with --remote-debugging-port=9222');
  const info = await resp.json();
  const browserWsUrl = info.webSocketDebuggerUrl;

  const edge = new WebSocket(browserWsUrl);

  await new Promise((resolve, reject) => {
    edge.on('open', resolve);
    edge.on('error', reject);
    setTimeout(() => reject(new Error('Edge WebSocket timeout')), 5000);
  });

  console.log('Connected to Edge CDP');

  const pending = new Map();
  let reqId = 0;

  edge.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.id && pending.has(msg.id)) {
      const res = pending.get(msg.id);
      clearTimeout(res.timer);
      res.resolve(msg);
      pending.delete(msg.id);
    }
  });

  const server = http.createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') { res.writeHead(200); res.end(); return; }
    if (req.method === 'GET' && req.url === '/health') { res.writeHead(200); res.end('OK'); return; }

    if (req.method === 'POST' && req.url === '/cdp') {
      let body = '';
      req.on('data', c => body += c);
      req.on('end', () => {
        const id = ++reqId;
        const cdp = JSON.parse(body);
        cdp.id = id;
        const timer = setTimeout(() => { pending.delete(id); res.writeHead(500); res.end('timeout'); }, 30000);
        pending.set(id, { resolve: (msg) => { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(msg)); }, timer });
        edge.send(JSON.stringify(cdp));
      });
      return;
    }

    if (req.method === 'GET') {
      const edgeUrl = 'http://localhost:9222' + (req.url === '/' ? '/json' : req.url);
      fetch(edgeUrl).then(r => r.text()).then(text => { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(text); })
        .catch(e => { res.writeHead(500); res.end(e.message); });
      return;
    }

    res.writeHead(404); res.end('not found');
  });

  server.listen(9223, '127.0.0.1', () => { console.log('Bridge on http://127.0.0.1:9223'); });
}

main().catch(e => { console.error(e.message); process.exit(1); });
