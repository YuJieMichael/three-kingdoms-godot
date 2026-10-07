import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {createGameRuntime, executeGame, validateInput, gameActions, GameError, copy, runtimeHash, seededRandom} from '../vendor/legacy/online/runtime.mjs';
import {gameView, worldView, nodeView} from './dto.mjs';
import {managementQuote} from './management-quotes.mjs';
import {executeGrowthSupport, validGrowthSupport, isGrowthSupportOffer} from './growth-support.mjs';
import {PracticeSessions} from './practice-session.mjs';
import {plotPlanKey} from './plot-plan-key.mjs';
import {executeSupplyCommand, isSupplyCommand, validSupplyWorkshop} from './supply-workshop.mjs';

const MAX_BODY = 16 * 1024 * 1024;
const RECEIPT_LIMIT = 32;
const object = value => !!value && typeof value === 'object' && !Array.isArray(value);
const commandKey = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{8,100}$/.test(value);
const authorityKey = value => typeof value === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value);
const stable = value => Array.isArray(value) ? value.map(stable) : object(value) ?
  Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])])) : value;
const digest = value => crypto.createHash('sha256').update(JSON.stringify(stable(value))).digest('hex');
const within = (root, target) => target === root || target.startsWith(root + path.sep);
const mime = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8',
  '.json':'application/json; charset=utf-8','.webmanifest':'application/manifest+json','.txt':'text/plain; charset=utf-8',
  '.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.jpg':'image/jpeg',
  '.jpeg':'image/jpeg','.svg':'image/svg+xml','.ico':'image/x-icon','.webp':'image/webp',
  '.woff':'font/woff','.woff2':'font/woff2','.ttf':'font/ttf','.otf':'font/otf','.ogg':'audio/ogg','.mp3':'audio/mpeg'};

async function atomicJSON(filename, value) {
  const temporary = `${filename}.${process.pid}.${crypto.randomUUID()}.tmp`;
  let handle;
  try {
    handle = await fs.open(temporary, 'wx', 0o600);
    await handle.writeFile(JSON.stringify(value), 'utf8');
    await handle.sync(); await handle.close(); handle = null;
    await fs.rename(temporary, filename);
    // POSIX directory fsync closes the rename durability window. Windows does not support it.
    if (process.platform !== 'win32') {
      const directory = await fs.open(path.dirname(filename), 'r');
      try { await directory.sync(); } finally { await directory.close(); }
    }
  } finally {
    await handle?.close().catch(() => {});
    await fs.unlink(temporary).catch(() => {});
  }
}

async function lockDirectory(dataDir) {
  await fs.mkdir(dataDir, {recursive: true, mode: 0o700});
  const filename = path.join(dataDir, '.bridge.lock');
  const identity = crypto.randomUUID();
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const lock = await fs.open(filename, 'wx', 0o600);
      await lock.writeFile(JSON.stringify({pid: process.pid, identity})); await lock.close();
      return async () => {
        try { const current = JSON.parse(await fs.readFile(filename, 'utf8'));
          if (current.identity === identity) await fs.unlink(filename);
        } catch (error) { if (error.code !== 'ENOENT') throw error; }
      };
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      let current;
      try { current = JSON.parse(await fs.readFile(filename, 'utf8')); }
      catch { throw new GameError('SAVE_LOCKED', '存档锁无法读取，请保留数据并检查现有游戏进程', 409); }
      if (!Number.isSafeInteger(current.pid) || current.pid < 1) throw new GameError('SAVE_LOCKED', '存档锁无效', 409);
      try { process.kill(current.pid, 0); }
      catch (error) {
        if (error.code === 'ESRCH') { await fs.unlink(filename); continue; }
        throw new GameError('SAVE_LOCKED', '无法核对存档进程', 409);
      }
      throw new GameError('SAVE_LOCKED', '同一存档正在另一个游戏进程运行', 409);
    }
  }
  throw new GameError('SAVE_LOCKED', '无法获得存档锁', 409);
}

function runtimeFor(snapshot, now, seed = 1) {
  if (!validGrowthSupport(snapshot) || !validSupplyWorkshop(snapshot)) throw new GameError('BAD_SAVE', '筹备或军需记录无效，原文件已保留');
  try { return createGameRuntime({snapshot, now, random: seededRandom(seed)}); }
  catch { throw new GameError('BAD_SAVE', '存档无法通过原游戏规则校验，原文件已保留', 400); }
}

function importSnapshot(state, now) {
  if (!object(state)) throw new GameError('BAD_SAVE', '请选择原网页导出的存档 JSON');
  // Never allow an invalid current-format object to be silently reset by init().
  const checker = createGameRuntime({now, random: seededRandom(1)}).Game;
  let candidate;
  try { candidate = checker.migrateSave(copy(state)); }
  catch { throw new GameError('BAD_SAVE', '存档格式或数据无效'); }
  if (!checker.validSave(candidate)) throw new GameError('BAD_SAVE', '存档无法通过原游戏规则校验');
  return copy(runtimeFor(candidate, now).Game.state);
}

function envelope(snapshot, revision, now, runtime = null, authorityId = null) {
  runtime ||= runtimeFor(snapshot, now);
  runtime.Game.tick(now, true); runtime.Game.save();
  if (!runtime.Game.validSave(runtime.Game.state)) throw new GameError('INVALID_RESULT', '状态投影校验失败', 500);
  return {revision, state: copy(runtime.Game.state), view: gameView(runtime.Game, now, runtime), serverTime: now, authorityId};
}

async function readBody(request) {
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers['content-type'] || ''))
    throw new GameError('CONTENT_TYPE', '请求必须使用 application/json', 415);
  const chunks = []; let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY) throw new GameError('BODY_TOO_LARGE', '请求或存档文件过大', 413);
    chunks.push(chunk);
  }
  try { const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!object(value)) throw new Error(); return value;
  } catch { throw new GameError('BAD_JSON', 'JSON 请求格式无效'); }
}

function requireRevision(input) {
  if (!commandKey(input.commandId)) throw new GameError('BAD_COMMAND_ID', '操作编号无效');
  if (!Number.isSafeInteger(input.expectedRevision) || input.expectedRevision < 0)
    throw new GameError('BAD_REVISION', '存档版本无效');
}

export async function startBridge({dataDir, port = 8139, host = '127.0.0.1', token = '', tokenFile = null, allowedOrigins = [], clock = Date.now, readyFile = null, webDir = null} = {}) {
  if (!dataDir) throw new Error('dataDir is required');
  if (!['127.0.0.1', '::1', 'localhost'].includes(host)) throw new Error('Local bridge must bind to loopback');
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error('Invalid port');
  dataDir = path.resolve(dataDir);
  await fs.mkdir(dataDir, {recursive: true, mode: 0o700});
  dataDir = await fs.realpath(dataDir);
  if (readyFile) readyFile = path.resolve(readyFile);
  if (webDir) {
    webDir = await fs.realpath(path.resolve(webDir));
    const tokenPath = tokenFile ? await fs.realpath(path.resolve(tokenFile)) : null;
    if (within(webDir, dataDir) || within(dataDir, webDir) || readyFile && within(webDir, readyFile) || tokenPath && within(webDir, tokenPath))
      throw new Error('Web resources must be separate from private save and ready files');
  }
  const unlock = await lockDirectory(dataDir), filename = path.join(dataDir, 'save.json');
  let stored, closed = false;
  try {
    try { stored = JSON.parse(await fs.readFile(filename, 'utf8')); }
    catch (error) {
      if (error.code !== 'ENOENT') throw new GameError('SAVE_CORRUPT', '存档文件无法读取，未覆盖原文件', 500);
      stored = {schema: 1, authorityId: crypto.randomUUID(), revision: 0, state: copy(createGameRuntime({now: clock(), random: seededRandom(1)}).Game.state), receipts: []};
      await atomicJSON(filename, stored);
    }
    if (!object(stored) || stored.schema !== 1 || stored.authorityId !== undefined && !authorityKey(stored.authorityId) || !Number.isSafeInteger(stored.revision) || stored.revision < 0 ||
        !Array.isArray(stored.receipts) || stored.receipts.length > RECEIPT_LIMIT ||
        stored.receipts.some(r => !object(r) || !commandKey(r.id) || typeof r.fingerprint !== 'string' || !object(r.response)))
      throw new GameError('SAVE_CORRUPT', '桥接存档结构无效，未覆盖原文件', 500);
    importSnapshot(stored.state, clock());
    if (stored.authorityId === undefined) { stored.authorityId = crypto.randomUUID(); await atomicJSON(filename, stored); }
  } catch (error) { await unlock(); throw error; }

  const practices = new PracticeSessions();
  let pending = Promise.resolve();
  const serial = operation => {
    const result = pending.then(operation); pending = result.catch(() => {}); return result;
  };
  const secret = Buffer.from(String(token));
  const authenticated = request => {
    const raw = request.headers.authorization?.replace(/^Bearer\s+/i, '') || request.headers['x-bridge-token'] || '';
    const supplied = Buffer.from(String(raw));
    return secret.length > 0 && supplied.length === secret.length && crypto.timingSafeEqual(supplied, secret);
  };
  const allowedOrigin = origin => {
    if (allowedOrigins.includes(origin)) return true;
    try { const url = new URL(origin); return ['http:', 'https:'].includes(url.protocol) && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname); }
    catch { return false; }
  };
  const server = http.createServer(async (request, response) => {
    const reply = (status, value, extra = {}) => {
      response.writeHead(status, {'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff', ...extra}); response.end(JSON.stringify(value));
    };
    try {
      if (closed) throw new GameError('SHUTTING_DOWN', '游戏服务正在关闭', 503);
      const origin = request.headers.origin;
      if (origin && !allowedOrigin(origin)) throw new GameError('ORIGIN_DENIED', '此网页不能访问本地存档', 403);
      if (origin) {
        response.setHeader('Access-Control-Allow-Origin', origin); response.setHeader('Vary', 'Origin');
        response.setHeader('Access-Control-Allow-Headers', 'Authorization, X-Bridge-Token, Content-Type');
        response.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      }
      if (request.method === 'OPTIONS') { response.writeHead(204); response.end(); return; }
      const url = new URL(request.url, `http://${request.headers.host || '127.0.0.1'}`);
      const route = url.pathname.startsWith('/api/') ? url.pathname.slice(4) : url.pathname;
      const apiRoutes = ['/health', '/state', '/world', '/export', '/node', '/quote', '/practice', '/command', '/import', '/shutdown'];
      if (apiRoutes.includes(route) && route !== '/health' && secret.length && !authenticated(request)) throw new GameError('UNAUTHORIZED', '本地连接密钥不正确', 401);
      if (request.method === 'GET' && route === '/health') {
        reply(200, {ok: true, protocol: 1, runtimeHash, mode: 'local', authentication: !!secret.length, authorityId: stored.authorityId}); return;
      }
      if (request.method === 'POST' && route === '/practice') {
        if ([...url.searchParams.keys()].length) throw new GameError('BAD_PRACTICE_REQUEST', '演练不接受查询参数');
        // Native callers use the existing bearer guard. Browser practice is
        // same-origin even when the ordinary local API has additional origins.
        if (origin) {
          let originURL;
          try { originURL = new URL(origin); } catch { throw new GameError('ORIGIN_DENIED', '演练来源无效', 403); }
          if (originURL.origin !== url.origin)
            throw new GameError('ORIGIN_DENIED', '借调演练须从同源游戏页面进入', 403);
        }
        const input = await readBody(request);
        const result = await serial(() => practices.execute(input, clock(), stored.authorityId));
        reply(200, result); return;
      }
      if (request.method === 'GET' && ['/state', '/world', '/export', '/node'].includes(route)) {
        const result = await serial(() => {
          const now = clock(), runtime = runtimeFor(stored.state, now); runtime.Game.tick(now, true); runtime.Game.save();
          if (route === '/world') return {...worldView(runtime.Game, now), revision: stored.revision, serverTime: now, authorityId: stored.authorityId};
          if (route === '/export') return copy(runtime.Game.state);
          if (route === '/node') {
            const node = runtime.Game.getNode(url.searchParams.get('id'));
            if (!node) throw new GameError('NODE_NOT_FOUND', '目标不存在', 404);
            if (!runtime.Game.landmarkVisible(node.id)) throw new GameError('NODE_HIDDEN', '请先完成当前任务据点', 403);
            return {revision: stored.revision, node: nodeView(runtime.Game, node), serverTime: now, authorityId: stored.authorityId};
          }
          return envelope(stored.state, stored.revision, now, runtime, stored.authorityId);
        });
        reply(200, result, route === '/export' ? {'Content-Disposition': 'attachment; filename="three-kingdoms-save.json"'} : {}); return;
      }
      if (request.method === 'POST' && route === '/quote') {
        if ([...url.searchParams.keys()].length) throw new GameError('BAD_QUOTE', '预览不接受查询参数');
        const input = await readBody(request);
        const result = await serial(() => {
          const now = clock(), runtime = runtimeFor(stored.state, now);
          runtime.Game.tick(now, true);
          return {...managementQuote(runtime, input), revision: stored.revision, serverTime: now, authorityId: stored.authorityId};
        });
        reply(200, result); return;
      }
      if (request.method === 'POST' && ['/command', '/import'].includes(route)) {
        const input = await readBody(request); requireRevision(input);
        const result = await serial(async () => {
          const operation = route === '/import' ? 'import' : 'command';
          const fingerprint = digest({operation, input});
          const receipt = stored.receipts.find(r => r.id === input.commandId);
          if (receipt) {
            if (receipt.fingerprint !== fingerprint) throw new GameError('ID_REUSED', '同一操作编号不能用于不同请求', 409);
            return {...copy(receipt.response), authorityId: stored.authorityId, replayed: true};
          }
          if (input.expectedRevision !== stored.revision) throw new GameError('REVISION_CONFLICT', '存档已更新，请刷新后重试', 409);
          if (stored.revision === Number.MAX_SAFE_INTEGER) throw new GameError('REVISION_LIMIT', '存档版本达到上限', 409);
          const now = clock(); let state, actionResult = null, runtime;
          if (operation === 'import') {
            if (Object.keys(input).some(key => !['commandId', 'expectedRevision', 'state'].includes(key))) throw new GameError('BAD_INPUT', '导入请求含不支持的字段');
            state = importSnapshot(input.state, now); runtime = runtimeFor(state, now);
          } else {
            if (Object.keys(input).some(key => !['commandId', 'expectedRevision', 'type', 'args', 'sourceCity'].includes(key))) throw new GameError('CLIENT_SNAPSHOT_FORBIDDEN', '操作不能替换客户端存档');
            validateInput(input);
            // Also reject inherited namespace names before the legacy dispatcher reads its plain object.
            if (!gameActions.has(input.type) && !isSupplyCommand(input.type) && !/^(wild|hero|heritage|war|onboarding)\.[a-zA-Z]+$/.test(input.type))
              throw new GameError('COMMAND_NOT_ALLOWED', '服务器不支持此操作');
            if (input.sourceCity !== undefined && (typeof input.sourceCity !== 'string' || input.sourceCity.length > 100)) throw new GameError('BAD_CITY', '出发城市格式无效');
            runtime = runtimeFor(stored.state, now, Number.parseInt(fingerprint.slice(0, 8), 16));
            const sourceCity = input.sourceCity || runtime.Game.currentCityId();
            if (!Object.hasOwn(runtime.Game.state.realm.cities, sourceCity)) throw new GameError('CITY_NOT_OWNED', '城市不属于你');
            if (runtime.Game.currentCityId() !== sourceCity) runtime.Game.switchCity(sourceCity);
            if (['dispatch', 'scout', 'dispatchScout'].includes(input.type) && !runtime.Game.landmarkVisible(input.args[0])) throw new GameError('NODE_HIDDEN', '请先完成当前任务据点', 403);
            if (input.type === 'applyPlotTemplate' && input.args.length === 3) {
              // Match the settled read projection before checking the preview;
              // expired construction and automation can change the native plan.
              runtime.Game.tick(now, true);
              const key = input.args[2], quote = runtime.Game.plotTemplateQuote(input.args[0], input.args[1]);
              if (typeof key !== 'string' || !/^[a-f0-9]{64}$/.test(key) || key !== plotPlanKey(runtime.Game, quote))
                throw new GameError('PLAN_CHANGED', '配田方案或受影响田地等级已变化，请重新预览');
            }
            const executed = isSupplyCommand(input.type) ? executeSupplyCommand(runtime, input, now) :
              input.type === 'exchangeCopper' && isGrowthSupportOffer(input.args[0]) ?
              executeGrowthSupport(runtime, input, now) : executeGame(stored.state, input, now, null, runtime);
            state = executed.state; actionResult = executed.result;
          }
          const revision = stored.revision + 1;
          const responseValue = {...envelope(state, revision, now, runtime, stored.authorityId), result: copy(actionResult), replayed: false};
          const candidate = {schema: 1, authorityId: stored.authorityId, revision, state: responseValue.state,
            receipts: [...stored.receipts, {id: input.commandId, fingerprint, response: responseValue}].slice(-RECEIPT_LIMIT)};
          if (operation === 'import') await atomicJSON(path.join(dataDir, 'before-import.json'), stored);
          await atomicJSON(filename, candidate); stored = candidate;
          if (operation === 'import') practices.clear();
          return responseValue;
        });
        reply(200, result); return;
      }
      if (request.method === 'POST' && route === '/shutdown') {
        if (!authenticated(request)) throw new GameError('UNAUTHORIZED', '关闭服务需要连接密钥', 401);
        await pending; reply(200, {ok: true}); setImmediate(() => close().catch(() => {})); return;
      }
      if (webDir && ['GET', 'HEAD'].includes(request.method) && !url.pathname.startsWith('/api/')) {
        let pathname;
        try { pathname = decodeURIComponent(url.pathname); }
        catch { throw new GameError('BAD_PATH', '资源路径无效', 400); }
        if (pathname.includes('\\') || pathname.split('/').some(segment => segment.startsWith('.')))
          throw new GameError('NOT_FOUND', '资源不存在', 404);
        const requested = path.resolve(webDir, '.' + (pathname === '/' ? '/index.html' : pathname));
        if (!within(webDir, requested) || !mime[path.extname(requested).toLowerCase()]) throw new GameError('NOT_FOUND', '资源不存在', 404);
        let resolved, stat;
        try { resolved = await fs.realpath(requested); stat = await fs.stat(resolved); }
        catch { throw new GameError('NOT_FOUND', '资源不存在', 404); }
        if (!within(webDir, resolved) || !stat.isFile()) throw new GameError('NOT_FOUND', '资源不存在', 404);
        response.writeHead(200, {'Content-Type': mime[path.extname(resolved).toLowerCase()] || 'application/octet-stream',
          'Cache-Control':'no-cache','X-Content-Type-Options':'nosniff',
          'Cross-Origin-Opener-Policy':'same-origin','Cross-Origin-Embedder-Policy':'require-corp'});
        response.end(request.method === 'HEAD' ? undefined : await fs.readFile(resolved)); return;
      }
      throw new GameError('NOT_FOUND', '接口不存在', 404);
    } catch (error) {
      const known = error instanceof GameError;
      reply(known ? error.status : 500, {error: {code: known ? error.code : 'INTERNAL_ERROR',
        message: known ? error.message : '本地服务发生错误，原存档未被替换'}, revision: stored.revision});
    }
  });
  server.requestTimeout = 10000; server.headersTimeout = 10000;
  const close = async () => {
    if (closed) return; closed = true;
    await pending;
    practices.clear();
    await new Promise(resolve => server.close(resolve));
    await unlock();
    if (readyFile) await fs.unlink(readyFile).catch(() => {});
  };
  let assignedPort;
  try {
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, host, resolve); });
    // A client can shut down immediately after ready.json is published. Retain
    // the port before that boundary; server.address() is null after close().
    assignedPort = server.address().port;
    if (readyFile) {
      await fs.mkdir(path.dirname(readyFile), {recursive: true, mode: 0o700});
      await atomicJSON(readyFile, {url: `http://${host === '::1' ? '[::1]' : host}:${assignedPort}`, pid: process.pid, protocol: 1});
    }
  } catch (error) { await new Promise(resolve => server.close(resolve)); await unlock(); throw error; }
  return {server, port: assignedPort, host, dataDir, close};
}

export function parseArguments(args) {
  const options = {port: 8139, dataDir: path.resolve('data/local-save'), token: '', allowedOrigins: []};
  for (let i = 0; i < args.length; i++) {
    const key = args[i], value = args[++i];
    if (!value) throw new Error(`Missing value for ${key}`);
    if (key === '--port') options.port = Number(value);
    else if (key === '--data-dir') options.dataDir = path.resolve(value);
    else if (key === '--token') options.token = value;
    else if (key === '--token-file') options.tokenFile = path.resolve(value);
    else if (key === '--allowed-origin') options.allowedOrigins.push(value);
    else if (key === '--ready-file') options.readyFile = path.resolve(value);
    else if (key === '--web-dir') options.webDir = path.resolve(value);
    else throw new Error(`Unknown option ${key}`);
  }
  return options;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.tokenFile) options.token = (await fs.readFile(options.tokenFile, 'utf8')).trim();
    const bridge = await startBridge(options);
    console.log(JSON.stringify({event: 'ready', host: bridge.host, port: bridge.port, protocol: 1}));
    const stop = async () => { await bridge.close(); process.exit(0); };
    process.once('SIGINT', stop); process.once('SIGTERM', stop);
  } catch (error) { console.error(JSON.stringify({error: error.code || 'START_FAILED', message: error.message})); process.exitCode = 1; }
}
