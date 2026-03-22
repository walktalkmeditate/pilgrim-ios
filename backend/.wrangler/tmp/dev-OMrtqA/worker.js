var __freeze = Object.freeze;
var __defProp = Object.defineProperty;
var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __publicField = (obj, key, value) => {
  __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);
  return value;
};
var __template = (cooked, raw2) => __freeze(__defProp(cooked, "raw", { value: __freeze(raw2 || cooked.slice()) }));

// .wrangler/tmp/bundle-6Fy5QV/strip-cf-connecting-ip-header.js
function stripCfConnectingIPHeader(input, init) {
  const request = new Request(input, init);
  request.headers.delete("CF-Connecting-IP");
  return request;
}
__name(stripCfConnectingIPHeader, "stripCfConnectingIPHeader");
globalThis.fetch = new Proxy(globalThis.fetch, {
  apply(target, thisArg, argArray) {
    return Reflect.apply(target, thisArg, [
      stripCfConnectingIPHeader.apply(null, argArray)
    ]);
  }
});

// node_modules/unenv/dist/runtime/_internal/utils.mjs
function createNotImplementedError(name) {
  return new Error(`[unenv] ${name} is not implemented yet!`);
}
__name(createNotImplementedError, "createNotImplementedError");
function notImplemented(name) {
  const fn = /* @__PURE__ */ __name(() => {
    throw createNotImplementedError(name);
  }, "fn");
  return Object.assign(fn, { __unenv__: true });
}
__name(notImplemented, "notImplemented");
function notImplementedClass(name) {
  return class {
    __unenv__ = true;
    constructor() {
      throw new Error(`[unenv] ${name} is not implemented yet!`);
    }
  };
}
__name(notImplementedClass, "notImplementedClass");

// node_modules/unenv/dist/runtime/node/internal/perf_hooks/performance.mjs
var _timeOrigin = globalThis.performance?.timeOrigin ?? Date.now();
var _performanceNow = globalThis.performance?.now ? globalThis.performance.now.bind(globalThis.performance) : () => Date.now() - _timeOrigin;
var nodeTiming = {
  name: "node",
  entryType: "node",
  startTime: 0,
  duration: 0,
  nodeStart: 0,
  v8Start: 0,
  bootstrapComplete: 0,
  environment: 0,
  loopStart: 0,
  loopExit: 0,
  idleTime: 0,
  uvMetricsInfo: {
    loopCount: 0,
    events: 0,
    eventsWaiting: 0
  },
  detail: void 0,
  toJSON() {
    return this;
  }
};
var PerformanceEntry = class {
  __unenv__ = true;
  detail;
  entryType = "event";
  name;
  startTime;
  constructor(name, options) {
    this.name = name;
    this.startTime = options?.startTime || _performanceNow();
    this.detail = options?.detail;
  }
  get duration() {
    return _performanceNow() - this.startTime;
  }
  toJSON() {
    return {
      name: this.name,
      entryType: this.entryType,
      startTime: this.startTime,
      duration: this.duration,
      detail: this.detail
    };
  }
};
__name(PerformanceEntry, "PerformanceEntry");
var PerformanceMark = /* @__PURE__ */ __name(class PerformanceMark2 extends PerformanceEntry {
  entryType = "mark";
  constructor() {
    super(...arguments);
  }
  get duration() {
    return 0;
  }
}, "PerformanceMark");
var PerformanceMeasure = class extends PerformanceEntry {
  entryType = "measure";
};
__name(PerformanceMeasure, "PerformanceMeasure");
var PerformanceResourceTiming = class extends PerformanceEntry {
  entryType = "resource";
  serverTiming = [];
  connectEnd = 0;
  connectStart = 0;
  decodedBodySize = 0;
  domainLookupEnd = 0;
  domainLookupStart = 0;
  encodedBodySize = 0;
  fetchStart = 0;
  initiatorType = "";
  name = "";
  nextHopProtocol = "";
  redirectEnd = 0;
  redirectStart = 0;
  requestStart = 0;
  responseEnd = 0;
  responseStart = 0;
  secureConnectionStart = 0;
  startTime = 0;
  transferSize = 0;
  workerStart = 0;
  responseStatus = 0;
};
__name(PerformanceResourceTiming, "PerformanceResourceTiming");
var PerformanceObserverEntryList = class {
  __unenv__ = true;
  getEntries() {
    return [];
  }
  getEntriesByName(_name, _type) {
    return [];
  }
  getEntriesByType(type) {
    return [];
  }
};
__name(PerformanceObserverEntryList, "PerformanceObserverEntryList");
var Performance = class {
  __unenv__ = true;
  timeOrigin = _timeOrigin;
  eventCounts = /* @__PURE__ */ new Map();
  _entries = [];
  _resourceTimingBufferSize = 0;
  navigation = void 0;
  timing = void 0;
  timerify(_fn, _options) {
    throw createNotImplementedError("Performance.timerify");
  }
  get nodeTiming() {
    return nodeTiming;
  }
  eventLoopUtilization() {
    return {};
  }
  markResourceTiming() {
    return new PerformanceResourceTiming("");
  }
  onresourcetimingbufferfull = null;
  now() {
    if (this.timeOrigin === _timeOrigin) {
      return _performanceNow();
    }
    return Date.now() - this.timeOrigin;
  }
  clearMarks(markName) {
    this._entries = markName ? this._entries.filter((e) => e.name !== markName) : this._entries.filter((e) => e.entryType !== "mark");
  }
  clearMeasures(measureName) {
    this._entries = measureName ? this._entries.filter((e) => e.name !== measureName) : this._entries.filter((e) => e.entryType !== "measure");
  }
  clearResourceTimings() {
    this._entries = this._entries.filter((e) => e.entryType !== "resource" || e.entryType !== "navigation");
  }
  getEntries() {
    return this._entries;
  }
  getEntriesByName(name, type) {
    return this._entries.filter((e) => e.name === name && (!type || e.entryType === type));
  }
  getEntriesByType(type) {
    return this._entries.filter((e) => e.entryType === type);
  }
  mark(name, options) {
    const entry = new PerformanceMark(name, options);
    this._entries.push(entry);
    return entry;
  }
  measure(measureName, startOrMeasureOptions, endMark) {
    let start;
    let end;
    if (typeof startOrMeasureOptions === "string") {
      start = this.getEntriesByName(startOrMeasureOptions, "mark")[0]?.startTime;
      end = this.getEntriesByName(endMark, "mark")[0]?.startTime;
    } else {
      start = Number.parseFloat(startOrMeasureOptions?.start) || this.now();
      end = Number.parseFloat(startOrMeasureOptions?.end) || this.now();
    }
    const entry = new PerformanceMeasure(measureName, {
      startTime: start,
      detail: {
        start,
        end
      }
    });
    this._entries.push(entry);
    return entry;
  }
  setResourceTimingBufferSize(maxSize) {
    this._resourceTimingBufferSize = maxSize;
  }
  addEventListener(type, listener, options) {
    throw createNotImplementedError("Performance.addEventListener");
  }
  removeEventListener(type, listener, options) {
    throw createNotImplementedError("Performance.removeEventListener");
  }
  dispatchEvent(event) {
    throw createNotImplementedError("Performance.dispatchEvent");
  }
  toJSON() {
    return this;
  }
};
__name(Performance, "Performance");
var PerformanceObserver = class {
  __unenv__ = true;
  _callback = null;
  constructor(callback) {
    this._callback = callback;
  }
  takeRecords() {
    return [];
  }
  disconnect() {
    throw createNotImplementedError("PerformanceObserver.disconnect");
  }
  observe(options) {
    throw createNotImplementedError("PerformanceObserver.observe");
  }
  bind(fn) {
    return fn;
  }
  runInAsyncScope(fn, thisArg, ...args) {
    return fn.call(thisArg, ...args);
  }
  asyncId() {
    return 0;
  }
  triggerAsyncId() {
    return 0;
  }
  emitDestroy() {
    return this;
  }
};
__name(PerformanceObserver, "PerformanceObserver");
__publicField(PerformanceObserver, "supportedEntryTypes", []);
var performance = globalThis.performance && "addEventListener" in globalThis.performance ? globalThis.performance : new Performance();

// node_modules/@cloudflare/unenv-preset/dist/runtime/polyfill/performance.mjs
globalThis.performance = performance;
globalThis.Performance = Performance;
globalThis.PerformanceEntry = PerformanceEntry;
globalThis.PerformanceMark = PerformanceMark;
globalThis.PerformanceMeasure = PerformanceMeasure;
globalThis.PerformanceObserver = PerformanceObserver;
globalThis.PerformanceObserverEntryList = PerformanceObserverEntryList;
globalThis.PerformanceResourceTiming = PerformanceResourceTiming;

// node_modules/unenv/dist/runtime/node/console.mjs
import { Writable } from "node:stream";

// node_modules/unenv/dist/runtime/mock/noop.mjs
var noop_default = Object.assign(() => {
}, { __unenv__: true });

// node_modules/unenv/dist/runtime/node/console.mjs
var _console = globalThis.console;
var _ignoreErrors = true;
var _stderr = new Writable();
var _stdout = new Writable();
var log = _console?.log ?? noop_default;
var info = _console?.info ?? log;
var trace = _console?.trace ?? info;
var debug = _console?.debug ?? log;
var table = _console?.table ?? log;
var error = _console?.error ?? log;
var warn = _console?.warn ?? error;
var createTask = _console?.createTask ?? /* @__PURE__ */ notImplemented("console.createTask");
var clear = _console?.clear ?? noop_default;
var count = _console?.count ?? noop_default;
var countReset = _console?.countReset ?? noop_default;
var dir = _console?.dir ?? noop_default;
var dirxml = _console?.dirxml ?? noop_default;
var group = _console?.group ?? noop_default;
var groupEnd = _console?.groupEnd ?? noop_default;
var groupCollapsed = _console?.groupCollapsed ?? noop_default;
var profile = _console?.profile ?? noop_default;
var profileEnd = _console?.profileEnd ?? noop_default;
var time = _console?.time ?? noop_default;
var timeEnd = _console?.timeEnd ?? noop_default;
var timeLog = _console?.timeLog ?? noop_default;
var timeStamp = _console?.timeStamp ?? noop_default;
var Console = _console?.Console ?? /* @__PURE__ */ notImplementedClass("console.Console");
var _times = /* @__PURE__ */ new Map();
var _stdoutErrorHandler = noop_default;
var _stderrErrorHandler = noop_default;

// node_modules/@cloudflare/unenv-preset/dist/runtime/node/console.mjs
var workerdConsole = globalThis["console"];
var {
  assert,
  clear: clear2,
  // @ts-expect-error undocumented public API
  context,
  count: count2,
  countReset: countReset2,
  // @ts-expect-error undocumented public API
  createTask: createTask2,
  debug: debug2,
  dir: dir2,
  dirxml: dirxml2,
  error: error2,
  group: group2,
  groupCollapsed: groupCollapsed2,
  groupEnd: groupEnd2,
  info: info2,
  log: log2,
  profile: profile2,
  profileEnd: profileEnd2,
  table: table2,
  time: time2,
  timeEnd: timeEnd2,
  timeLog: timeLog2,
  timeStamp: timeStamp2,
  trace: trace2,
  warn: warn2
} = workerdConsole;
Object.assign(workerdConsole, {
  Console,
  _ignoreErrors,
  _stderr,
  _stderrErrorHandler,
  _stdout,
  _stdoutErrorHandler,
  _times
});
var console_default = workerdConsole;

// node_modules/wrangler/_virtual_unenv_global_polyfill-@cloudflare-unenv-preset-node-console
globalThis.console = console_default;

// node_modules/unenv/dist/runtime/node/internal/process/hrtime.mjs
var hrtime = /* @__PURE__ */ Object.assign(/* @__PURE__ */ __name(function hrtime2(startTime) {
  const now = Date.now();
  const seconds = Math.trunc(now / 1e3);
  const nanos = now % 1e3 * 1e6;
  if (startTime) {
    let diffSeconds = seconds - startTime[0];
    let diffNanos = nanos - startTime[0];
    if (diffNanos < 0) {
      diffSeconds = diffSeconds - 1;
      diffNanos = 1e9 + diffNanos;
    }
    return [diffSeconds, diffNanos];
  }
  return [seconds, nanos];
}, "hrtime"), { bigint: /* @__PURE__ */ __name(function bigint() {
  return BigInt(Date.now() * 1e6);
}, "bigint") });

// node_modules/unenv/dist/runtime/node/internal/process/process.mjs
import { EventEmitter } from "node:events";

// node_modules/unenv/dist/runtime/node/internal/tty/read-stream.mjs
import { Socket } from "node:net";
var ReadStream = class extends Socket {
  fd;
  constructor(fd) {
    super();
    this.fd = fd;
  }
  isRaw = false;
  setRawMode(mode) {
    this.isRaw = mode;
    return this;
  }
  isTTY = false;
};
__name(ReadStream, "ReadStream");

// node_modules/unenv/dist/runtime/node/internal/tty/write-stream.mjs
import { Socket as Socket2 } from "node:net";
var WriteStream = class extends Socket2 {
  fd;
  constructor(fd) {
    super();
    this.fd = fd;
  }
  clearLine(dir3, callback) {
    callback && callback();
    return false;
  }
  clearScreenDown(callback) {
    callback && callback();
    return false;
  }
  cursorTo(x, y, callback) {
    callback && typeof callback === "function" && callback();
    return false;
  }
  moveCursor(dx, dy, callback) {
    callback && callback();
    return false;
  }
  getColorDepth(env2) {
    return 1;
  }
  hasColors(count3, env2) {
    return false;
  }
  getWindowSize() {
    return [this.columns, this.rows];
  }
  columns = 80;
  rows = 24;
  isTTY = false;
};
__name(WriteStream, "WriteStream");

// node_modules/unenv/dist/runtime/node/internal/process/process.mjs
var Process = class extends EventEmitter {
  env;
  hrtime;
  nextTick;
  constructor(impl) {
    super();
    this.env = impl.env;
    this.hrtime = impl.hrtime;
    this.nextTick = impl.nextTick;
    for (const prop of [...Object.getOwnPropertyNames(Process.prototype), ...Object.getOwnPropertyNames(EventEmitter.prototype)]) {
      const value = this[prop];
      if (typeof value === "function") {
        this[prop] = value.bind(this);
      }
    }
  }
  emitWarning(warning, type, code) {
    console.warn(`${code ? `[${code}] ` : ""}${type ? `${type}: ` : ""}${warning}`);
  }
  emit(...args) {
    return super.emit(...args);
  }
  listeners(eventName) {
    return super.listeners(eventName);
  }
  #stdin;
  #stdout;
  #stderr;
  get stdin() {
    return this.#stdin ??= new ReadStream(0);
  }
  get stdout() {
    return this.#stdout ??= new WriteStream(1);
  }
  get stderr() {
    return this.#stderr ??= new WriteStream(2);
  }
  #cwd = "/";
  chdir(cwd2) {
    this.#cwd = cwd2;
  }
  cwd() {
    return this.#cwd;
  }
  arch = "";
  platform = "";
  argv = [];
  argv0 = "";
  execArgv = [];
  execPath = "";
  title = "";
  pid = 200;
  ppid = 100;
  get version() {
    return "";
  }
  get versions() {
    return {};
  }
  get allowedNodeEnvironmentFlags() {
    return /* @__PURE__ */ new Set();
  }
  get sourceMapsEnabled() {
    return false;
  }
  get debugPort() {
    return 0;
  }
  get throwDeprecation() {
    return false;
  }
  get traceDeprecation() {
    return false;
  }
  get features() {
    return {};
  }
  get release() {
    return {};
  }
  get connected() {
    return false;
  }
  get config() {
    return {};
  }
  get moduleLoadList() {
    return [];
  }
  constrainedMemory() {
    return 0;
  }
  availableMemory() {
    return 0;
  }
  uptime() {
    return 0;
  }
  resourceUsage() {
    return {};
  }
  ref() {
  }
  unref() {
  }
  umask() {
    throw createNotImplementedError("process.umask");
  }
  getBuiltinModule() {
    return void 0;
  }
  getActiveResourcesInfo() {
    throw createNotImplementedError("process.getActiveResourcesInfo");
  }
  exit() {
    throw createNotImplementedError("process.exit");
  }
  reallyExit() {
    throw createNotImplementedError("process.reallyExit");
  }
  kill() {
    throw createNotImplementedError("process.kill");
  }
  abort() {
    throw createNotImplementedError("process.abort");
  }
  dlopen() {
    throw createNotImplementedError("process.dlopen");
  }
  setSourceMapsEnabled() {
    throw createNotImplementedError("process.setSourceMapsEnabled");
  }
  loadEnvFile() {
    throw createNotImplementedError("process.loadEnvFile");
  }
  disconnect() {
    throw createNotImplementedError("process.disconnect");
  }
  cpuUsage() {
    throw createNotImplementedError("process.cpuUsage");
  }
  setUncaughtExceptionCaptureCallback() {
    throw createNotImplementedError("process.setUncaughtExceptionCaptureCallback");
  }
  hasUncaughtExceptionCaptureCallback() {
    throw createNotImplementedError("process.hasUncaughtExceptionCaptureCallback");
  }
  initgroups() {
    throw createNotImplementedError("process.initgroups");
  }
  openStdin() {
    throw createNotImplementedError("process.openStdin");
  }
  assert() {
    throw createNotImplementedError("process.assert");
  }
  binding() {
    throw createNotImplementedError("process.binding");
  }
  permission = { has: /* @__PURE__ */ notImplemented("process.permission.has") };
  report = {
    directory: "",
    filename: "",
    signal: "SIGUSR2",
    compact: false,
    reportOnFatalError: false,
    reportOnSignal: false,
    reportOnUncaughtException: false,
    getReport: /* @__PURE__ */ notImplemented("process.report.getReport"),
    writeReport: /* @__PURE__ */ notImplemented("process.report.writeReport")
  };
  finalization = {
    register: /* @__PURE__ */ notImplemented("process.finalization.register"),
    unregister: /* @__PURE__ */ notImplemented("process.finalization.unregister"),
    registerBeforeExit: /* @__PURE__ */ notImplemented("process.finalization.registerBeforeExit")
  };
  memoryUsage = Object.assign(() => ({
    arrayBuffers: 0,
    rss: 0,
    external: 0,
    heapTotal: 0,
    heapUsed: 0
  }), { rss: () => 0 });
  mainModule = void 0;
  domain = void 0;
  send = void 0;
  exitCode = void 0;
  channel = void 0;
  getegid = void 0;
  geteuid = void 0;
  getgid = void 0;
  getgroups = void 0;
  getuid = void 0;
  setegid = void 0;
  seteuid = void 0;
  setgid = void 0;
  setgroups = void 0;
  setuid = void 0;
  _events = void 0;
  _eventsCount = void 0;
  _exiting = void 0;
  _maxListeners = void 0;
  _debugEnd = void 0;
  _debugProcess = void 0;
  _fatalException = void 0;
  _getActiveHandles = void 0;
  _getActiveRequests = void 0;
  _kill = void 0;
  _preload_modules = void 0;
  _rawDebug = void 0;
  _startProfilerIdleNotifier = void 0;
  _stopProfilerIdleNotifier = void 0;
  _tickCallback = void 0;
  _disconnect = void 0;
  _handleQueue = void 0;
  _pendingMessage = void 0;
  _channel = void 0;
  _send = void 0;
  _linkedBinding = void 0;
};
__name(Process, "Process");

// node_modules/@cloudflare/unenv-preset/dist/runtime/node/process.mjs
var globalProcess = globalThis["process"];
var getBuiltinModule = globalProcess.getBuiltinModule;
var { exit, platform, nextTick } = getBuiltinModule(
  "node:process"
);
var unenvProcess = new Process({
  env: globalProcess.env,
  hrtime,
  nextTick
});
var {
  abort,
  addListener,
  allowedNodeEnvironmentFlags,
  hasUncaughtExceptionCaptureCallback,
  setUncaughtExceptionCaptureCallback,
  loadEnvFile,
  sourceMapsEnabled,
  arch,
  argv,
  argv0,
  chdir,
  config,
  connected,
  constrainedMemory,
  availableMemory,
  cpuUsage,
  cwd,
  debugPort,
  dlopen,
  disconnect,
  emit,
  emitWarning,
  env,
  eventNames,
  execArgv,
  execPath,
  finalization,
  features,
  getActiveResourcesInfo,
  getMaxListeners,
  hrtime: hrtime3,
  kill,
  listeners,
  listenerCount,
  memoryUsage,
  on,
  off,
  once,
  pid,
  ppid,
  prependListener,
  prependOnceListener,
  rawListeners,
  release,
  removeAllListeners,
  removeListener,
  report,
  resourceUsage,
  setMaxListeners,
  setSourceMapsEnabled,
  stderr,
  stdin,
  stdout,
  title,
  throwDeprecation,
  traceDeprecation,
  umask,
  uptime,
  version,
  versions,
  domain,
  initgroups,
  moduleLoadList,
  reallyExit,
  openStdin,
  assert: assert2,
  binding,
  send,
  exitCode,
  channel,
  getegid,
  geteuid,
  getgid,
  getgroups,
  getuid,
  setegid,
  seteuid,
  setgid,
  setgroups,
  setuid,
  permission,
  mainModule,
  _events,
  _eventsCount,
  _exiting,
  _maxListeners,
  _debugEnd,
  _debugProcess,
  _fatalException,
  _getActiveHandles,
  _getActiveRequests,
  _kill,
  _preload_modules,
  _rawDebug,
  _startProfilerIdleNotifier,
  _stopProfilerIdleNotifier,
  _tickCallback,
  _disconnect,
  _handleQueue,
  _pendingMessage,
  _channel,
  _send,
  _linkedBinding
} = unenvProcess;
var _process = {
  abort,
  addListener,
  allowedNodeEnvironmentFlags,
  hasUncaughtExceptionCaptureCallback,
  setUncaughtExceptionCaptureCallback,
  loadEnvFile,
  sourceMapsEnabled,
  arch,
  argv,
  argv0,
  chdir,
  config,
  connected,
  constrainedMemory,
  availableMemory,
  cpuUsage,
  cwd,
  debugPort,
  dlopen,
  disconnect,
  emit,
  emitWarning,
  env,
  eventNames,
  execArgv,
  execPath,
  exit,
  finalization,
  features,
  getBuiltinModule,
  getActiveResourcesInfo,
  getMaxListeners,
  hrtime: hrtime3,
  kill,
  listeners,
  listenerCount,
  memoryUsage,
  nextTick,
  on,
  off,
  once,
  pid,
  platform,
  ppid,
  prependListener,
  prependOnceListener,
  rawListeners,
  release,
  removeAllListeners,
  removeListener,
  report,
  resourceUsage,
  setMaxListeners,
  setSourceMapsEnabled,
  stderr,
  stdin,
  stdout,
  title,
  throwDeprecation,
  traceDeprecation,
  umask,
  uptime,
  version,
  versions,
  // @ts-expect-error old API
  domain,
  initgroups,
  moduleLoadList,
  reallyExit,
  openStdin,
  assert: assert2,
  binding,
  send,
  exitCode,
  channel,
  getegid,
  geteuid,
  getgid,
  getgroups,
  getuid,
  setegid,
  seteuid,
  setgid,
  setgroups,
  setuid,
  permission,
  mainModule,
  _events,
  _eventsCount,
  _exiting,
  _maxListeners,
  _debugEnd,
  _debugProcess,
  _fatalException,
  _getActiveHandles,
  _getActiveRequests,
  _kill,
  _preload_modules,
  _rawDebug,
  _startProfilerIdleNotifier,
  _stopProfilerIdleNotifier,
  _tickCallback,
  _disconnect,
  _handleQueue,
  _pendingMessage,
  _channel,
  _send,
  _linkedBinding
};
var process_default = _process;

// node_modules/wrangler/_virtual_unenv_global_polyfill-@cloudflare-unenv-preset-node-process
globalThis.process = process_default;

// node_modules/hono/dist/utils/body.js
var parseBody = /* @__PURE__ */ __name(async (request, options = /* @__PURE__ */ Object.create(null)) => {
  const { all = false, dot = false } = options;
  const headers = request instanceof HonoRequest ? request.raw.headers : request.headers;
  const contentType = headers.get("Content-Type");
  if (contentType?.startsWith("multipart/form-data") || contentType?.startsWith("application/x-www-form-urlencoded")) {
    return parseFormData(request, { all, dot });
  }
  return {};
}, "parseBody");
async function parseFormData(request, options) {
  const formData = await request.formData();
  if (formData) {
    return convertFormDataToBodyData(formData, options);
  }
  return {};
}
__name(parseFormData, "parseFormData");
function convertFormDataToBodyData(formData, options) {
  const form = /* @__PURE__ */ Object.create(null);
  formData.forEach((value, key) => {
    const shouldParseAllValues = options.all || key.endsWith("[]");
    if (!shouldParseAllValues) {
      form[key] = value;
    } else {
      handleParsingAllValues(form, key, value);
    }
  });
  if (options.dot) {
    Object.entries(form).forEach(([key, value]) => {
      const shouldParseDotValues = key.includes(".");
      if (shouldParseDotValues) {
        handleParsingNestedValues(form, key, value);
        delete form[key];
      }
    });
  }
  return form;
}
__name(convertFormDataToBodyData, "convertFormDataToBodyData");
var handleParsingAllValues = /* @__PURE__ */ __name((form, key, value) => {
  if (form[key] !== void 0) {
    if (Array.isArray(form[key])) {
      ;
      form[key].push(value);
    } else {
      form[key] = [form[key], value];
    }
  } else {
    form[key] = value;
  }
}, "handleParsingAllValues");
var handleParsingNestedValues = /* @__PURE__ */ __name((form, key, value) => {
  let nestedForm = form;
  const keys = key.split(".");
  keys.forEach((key2, index) => {
    if (index === keys.length - 1) {
      nestedForm[key2] = value;
    } else {
      if (!nestedForm[key2] || typeof nestedForm[key2] !== "object" || Array.isArray(nestedForm[key2]) || nestedForm[key2] instanceof File) {
        nestedForm[key2] = /* @__PURE__ */ Object.create(null);
      }
      nestedForm = nestedForm[key2];
    }
  });
}, "handleParsingNestedValues");

// node_modules/hono/dist/utils/url.js
var splitPath = /* @__PURE__ */ __name((path) => {
  const paths = path.split("/");
  if (paths[0] === "") {
    paths.shift();
  }
  return paths;
}, "splitPath");
var splitRoutingPath = /* @__PURE__ */ __name((routePath) => {
  const { groups, path } = extractGroupsFromPath(routePath);
  const paths = splitPath(path);
  return replaceGroupMarks(paths, groups);
}, "splitRoutingPath");
var extractGroupsFromPath = /* @__PURE__ */ __name((path) => {
  const groups = [];
  path = path.replace(/\{[^}]+\}/g, (match, index) => {
    const mark = `@${index}`;
    groups.push([mark, match]);
    return mark;
  });
  return { groups, path };
}, "extractGroupsFromPath");
var replaceGroupMarks = /* @__PURE__ */ __name((paths, groups) => {
  for (let i = groups.length - 1; i >= 0; i--) {
    const [mark] = groups[i];
    for (let j = paths.length - 1; j >= 0; j--) {
      if (paths[j].includes(mark)) {
        paths[j] = paths[j].replace(mark, groups[i][1]);
        break;
      }
    }
  }
  return paths;
}, "replaceGroupMarks");
var patternCache = {};
var getPattern = /* @__PURE__ */ __name((label) => {
  if (label === "*") {
    return "*";
  }
  const match = label.match(/^\:([^\{\}]+)(?:\{(.+)\})?$/);
  if (match) {
    if (!patternCache[label]) {
      if (match[2]) {
        patternCache[label] = [label, match[1], new RegExp("^" + match[2] + "$")];
      } else {
        patternCache[label] = [label, match[1], true];
      }
    }
    return patternCache[label];
  }
  return null;
}, "getPattern");
var tryDecode = /* @__PURE__ */ __name((str, decoder) => {
  try {
    return decoder(str);
  } catch {
    return str.replace(/(?:%[0-9A-Fa-f]{2})+/g, (match) => {
      try {
        return decoder(match);
      } catch {
        return match;
      }
    });
  }
}, "tryDecode");
var tryDecodeURI = /* @__PURE__ */ __name((str) => tryDecode(str, decodeURI), "tryDecodeURI");
var getPath = /* @__PURE__ */ __name((request) => {
  const url = request.url;
  const start = url.indexOf("/", 8);
  let i = start;
  for (; i < url.length; i++) {
    const charCode = url.charCodeAt(i);
    if (charCode === 37) {
      const queryIndex = url.indexOf("?", i);
      const path = url.slice(start, queryIndex === -1 ? void 0 : queryIndex);
      return tryDecodeURI(path.includes("%25") ? path.replace(/%25/g, "%2525") : path);
    } else if (charCode === 63) {
      break;
    }
  }
  return url.slice(start, i);
}, "getPath");
var getPathNoStrict = /* @__PURE__ */ __name((request) => {
  const result = getPath(request);
  return result.length > 1 && result[result.length - 1] === "/" ? result.slice(0, -1) : result;
}, "getPathNoStrict");
var mergePath = /* @__PURE__ */ __name((...paths) => {
  let p = "";
  let endsWithSlash = false;
  for (let path of paths) {
    if (p[p.length - 1] === "/") {
      p = p.slice(0, -1);
      endsWithSlash = true;
    }
    if (path[0] !== "/") {
      path = `/${path}`;
    }
    if (path === "/" && endsWithSlash) {
      p = `${p}/`;
    } else if (path !== "/") {
      p = `${p}${path}`;
    }
    if (path === "/" && p === "") {
      p = "/";
    }
  }
  return p;
}, "mergePath");
var checkOptionalParameter = /* @__PURE__ */ __name((path) => {
  if (!path.match(/\:.+\?$/)) {
    return null;
  }
  const segments = path.split("/");
  const results = [];
  let basePath = "";
  segments.forEach((segment) => {
    if (segment !== "" && !/\:/.test(segment)) {
      basePath += "/" + segment;
    } else if (/\:/.test(segment)) {
      if (/\?/.test(segment)) {
        if (results.length === 0 && basePath === "") {
          results.push("/");
        } else {
          results.push(basePath);
        }
        const optionalSegment = segment.replace("?", "");
        basePath += "/" + optionalSegment;
        results.push(basePath);
      } else {
        basePath += "/" + segment;
      }
    }
  });
  return results.filter((v, i, a) => a.indexOf(v) === i);
}, "checkOptionalParameter");
var _decodeURI = /* @__PURE__ */ __name((value) => {
  if (!/[%+]/.test(value)) {
    return value;
  }
  if (value.indexOf("+") !== -1) {
    value = value.replace(/\+/g, " ");
  }
  return value.indexOf("%") !== -1 ? decodeURIComponent_(value) : value;
}, "_decodeURI");
var _getQueryParam = /* @__PURE__ */ __name((url, key, multiple) => {
  let encoded;
  if (!multiple && key && !/[%+]/.test(key)) {
    let keyIndex2 = url.indexOf(`?${key}`, 8);
    if (keyIndex2 === -1) {
      keyIndex2 = url.indexOf(`&${key}`, 8);
    }
    while (keyIndex2 !== -1) {
      const trailingKeyCode = url.charCodeAt(keyIndex2 + key.length + 1);
      if (trailingKeyCode === 61) {
        const valueIndex = keyIndex2 + key.length + 2;
        const endIndex = url.indexOf("&", valueIndex);
        return _decodeURI(url.slice(valueIndex, endIndex === -1 ? void 0 : endIndex));
      } else if (trailingKeyCode == 38 || isNaN(trailingKeyCode)) {
        return "";
      }
      keyIndex2 = url.indexOf(`&${key}`, keyIndex2 + 1);
    }
    encoded = /[%+]/.test(url);
    if (!encoded) {
      return void 0;
    }
  }
  const results = {};
  encoded ??= /[%+]/.test(url);
  let keyIndex = url.indexOf("?", 8);
  while (keyIndex !== -1) {
    const nextKeyIndex = url.indexOf("&", keyIndex + 1);
    let valueIndex = url.indexOf("=", keyIndex);
    if (valueIndex > nextKeyIndex && nextKeyIndex !== -1) {
      valueIndex = -1;
    }
    let name = url.slice(
      keyIndex + 1,
      valueIndex === -1 ? nextKeyIndex === -1 ? void 0 : nextKeyIndex : valueIndex
    );
    if (encoded) {
      name = _decodeURI(name);
    }
    keyIndex = nextKeyIndex;
    if (name === "") {
      continue;
    }
    let value;
    if (valueIndex === -1) {
      value = "";
    } else {
      value = url.slice(valueIndex + 1, nextKeyIndex === -1 ? void 0 : nextKeyIndex);
      if (encoded) {
        value = _decodeURI(value);
      }
    }
    if (multiple) {
      if (!(results[name] && Array.isArray(results[name]))) {
        results[name] = [];
      }
      ;
      results[name].push(value);
    } else {
      results[name] ??= value;
    }
  }
  return key ? results[key] : results;
}, "_getQueryParam");
var getQueryParam = _getQueryParam;
var getQueryParams = /* @__PURE__ */ __name((url, key) => {
  return _getQueryParam(url, key, true);
}, "getQueryParams");
var decodeURIComponent_ = decodeURIComponent;

// node_modules/hono/dist/request.js
var tryDecodeURIComponent = /* @__PURE__ */ __name((str) => tryDecode(str, decodeURIComponent_), "tryDecodeURIComponent");
var HonoRequest = /* @__PURE__ */ __name(class {
  raw;
  #validatedData;
  #matchResult;
  routeIndex = 0;
  path;
  bodyCache = {};
  constructor(request, path = "/", matchResult = [[]]) {
    this.raw = request;
    this.path = path;
    this.#matchResult = matchResult;
    this.#validatedData = {};
  }
  param(key) {
    return key ? this.#getDecodedParam(key) : this.#getAllDecodedParams();
  }
  #getDecodedParam(key) {
    const paramKey = this.#matchResult[0][this.routeIndex][1][key];
    const param = this.#getParamValue(paramKey);
    return param ? /\%/.test(param) ? tryDecodeURIComponent(param) : param : void 0;
  }
  #getAllDecodedParams() {
    const decoded = {};
    const keys = Object.keys(this.#matchResult[0][this.routeIndex][1]);
    for (const key of keys) {
      const value = this.#getParamValue(this.#matchResult[0][this.routeIndex][1][key]);
      if (value && typeof value === "string") {
        decoded[key] = /\%/.test(value) ? tryDecodeURIComponent(value) : value;
      }
    }
    return decoded;
  }
  #getParamValue(paramKey) {
    return this.#matchResult[1] ? this.#matchResult[1][paramKey] : paramKey;
  }
  query(key) {
    return getQueryParam(this.url, key);
  }
  queries(key) {
    return getQueryParams(this.url, key);
  }
  header(name) {
    if (name) {
      return this.raw.headers.get(name.toLowerCase()) ?? void 0;
    }
    const headerData = {};
    this.raw.headers.forEach((value, key) => {
      headerData[key] = value;
    });
    return headerData;
  }
  async parseBody(options) {
    return this.bodyCache.parsedBody ??= await parseBody(this, options);
  }
  #cachedBody = (key) => {
    const { bodyCache, raw: raw2 } = this;
    const cachedBody = bodyCache[key];
    if (cachedBody) {
      return cachedBody;
    }
    const anyCachedKey = Object.keys(bodyCache)[0];
    if (anyCachedKey) {
      return bodyCache[anyCachedKey].then((body) => {
        if (anyCachedKey === "json") {
          body = JSON.stringify(body);
        }
        return new Response(body)[key]();
      });
    }
    return bodyCache[key] = raw2[key]();
  };
  json() {
    return this.#cachedBody("json");
  }
  text() {
    return this.#cachedBody("text");
  }
  arrayBuffer() {
    return this.#cachedBody("arrayBuffer");
  }
  blob() {
    return this.#cachedBody("blob");
  }
  formData() {
    return this.#cachedBody("formData");
  }
  addValidatedData(target, data) {
    this.#validatedData[target] = data;
  }
  valid(target) {
    return this.#validatedData[target];
  }
  get url() {
    return this.raw.url;
  }
  get method() {
    return this.raw.method;
  }
  get matchedRoutes() {
    return this.#matchResult[0].map(([[, route]]) => route);
  }
  get routePath() {
    return this.#matchResult[0].map(([[, route]]) => route)[this.routeIndex].path;
  }
}, "HonoRequest");

// node_modules/hono/dist/utils/html.js
var HtmlEscapedCallbackPhase = {
  Stringify: 1,
  BeforeStream: 2,
  Stream: 3
};
var raw = /* @__PURE__ */ __name((value, callbacks) => {
  const escapedString = new String(value);
  escapedString.isEscaped = true;
  escapedString.callbacks = callbacks;
  return escapedString;
}, "raw");
var escapeRe = /[&<>'"]/;
var stringBufferToString = /* @__PURE__ */ __name(async (buffer, callbacks) => {
  let str = "";
  callbacks ||= [];
  const resolvedBuffer = await Promise.all(buffer);
  for (let i = resolvedBuffer.length - 1; ; i--) {
    str += resolvedBuffer[i];
    i--;
    if (i < 0) {
      break;
    }
    let r = resolvedBuffer[i];
    if (typeof r === "object") {
      callbacks.push(...r.callbacks || []);
    }
    const isEscaped = r.isEscaped;
    r = await (typeof r === "object" ? r.toString() : r);
    if (typeof r === "object") {
      callbacks.push(...r.callbacks || []);
    }
    if (r.isEscaped ?? isEscaped) {
      str += r;
    } else {
      const buf = [str];
      escapeToBuffer(r, buf);
      str = buf[0];
    }
  }
  return raw(str, callbacks);
}, "stringBufferToString");
var escapeToBuffer = /* @__PURE__ */ __name((str, buffer) => {
  const match = str.search(escapeRe);
  if (match === -1) {
    buffer[0] += str;
    return;
  }
  let escape;
  let index;
  let lastIndex = 0;
  for (index = match; index < str.length; index++) {
    switch (str.charCodeAt(index)) {
      case 34:
        escape = "&quot;";
        break;
      case 39:
        escape = "&#39;";
        break;
      case 38:
        escape = "&amp;";
        break;
      case 60:
        escape = "&lt;";
        break;
      case 62:
        escape = "&gt;";
        break;
      default:
        continue;
    }
    buffer[0] += str.substring(lastIndex, index) + escape;
    lastIndex = index + 1;
  }
  buffer[0] += str.substring(lastIndex, index);
}, "escapeToBuffer");
var resolveCallbackSync = /* @__PURE__ */ __name((str) => {
  const callbacks = str.callbacks;
  if (!callbacks?.length) {
    return str;
  }
  const buffer = [str];
  const context2 = {};
  callbacks.forEach((c) => c({ phase: HtmlEscapedCallbackPhase.Stringify, buffer, context: context2 }));
  return buffer[0];
}, "resolveCallbackSync");
var resolveCallback = /* @__PURE__ */ __name(async (str, phase, preserveCallbacks, context2, buffer) => {
  if (typeof str === "object" && !(str instanceof String)) {
    if (!(str instanceof Promise)) {
      str = str.toString();
    }
    if (str instanceof Promise) {
      str = await str;
    }
  }
  const callbacks = str.callbacks;
  if (!callbacks?.length) {
    return Promise.resolve(str);
  }
  if (buffer) {
    buffer[0] += str;
  } else {
    buffer = [str];
  }
  const resStr = Promise.all(callbacks.map((c) => c({ phase, buffer, context: context2 }))).then(
    (res) => Promise.all(
      res.filter(Boolean).map((str2) => resolveCallback(str2, phase, false, context2, buffer))
    ).then(() => buffer[0])
  );
  if (preserveCallbacks) {
    return raw(await resStr, callbacks);
  } else {
    return resStr;
  }
}, "resolveCallback");

// node_modules/hono/dist/context.js
var TEXT_PLAIN = "text/plain; charset=UTF-8";
var setHeaders = /* @__PURE__ */ __name((headers, map2 = {}) => {
  for (const key of Object.keys(map2)) {
    headers.set(key, map2[key]);
  }
  return headers;
}, "setHeaders");
var Context = /* @__PURE__ */ __name(class {
  #rawRequest;
  #req;
  env = {};
  #var;
  finalized = false;
  error;
  #status = 200;
  #executionCtx;
  #headers;
  #preparedHeaders;
  #res;
  #isFresh = true;
  #layout;
  #renderer;
  #notFoundHandler;
  #matchResult;
  #path;
  constructor(req, options) {
    this.#rawRequest = req;
    if (options) {
      this.#executionCtx = options.executionCtx;
      this.env = options.env;
      this.#notFoundHandler = options.notFoundHandler;
      this.#path = options.path;
      this.#matchResult = options.matchResult;
    }
  }
  get req() {
    this.#req ??= new HonoRequest(this.#rawRequest, this.#path, this.#matchResult);
    return this.#req;
  }
  get event() {
    if (this.#executionCtx && "respondWith" in this.#executionCtx) {
      return this.#executionCtx;
    } else {
      throw Error("This context has no FetchEvent");
    }
  }
  get executionCtx() {
    if (this.#executionCtx) {
      return this.#executionCtx;
    } else {
      throw Error("This context has no ExecutionContext");
    }
  }
  get res() {
    this.#isFresh = false;
    return this.#res ||= new Response("404 Not Found", { status: 404 });
  }
  set res(_res) {
    this.#isFresh = false;
    if (this.#res && _res) {
      try {
        for (const [k, v] of this.#res.headers.entries()) {
          if (k === "content-type") {
            continue;
          }
          if (k === "set-cookie") {
            const cookies = this.#res.headers.getSetCookie();
            _res.headers.delete("set-cookie");
            for (const cookie of cookies) {
              _res.headers.append("set-cookie", cookie);
            }
          } else {
            _res.headers.set(k, v);
          }
        }
      } catch (e) {
        if (e instanceof TypeError && e.message.includes("immutable")) {
          this.res = new Response(_res.body, {
            headers: _res.headers,
            status: _res.status
          });
          return;
        } else {
          throw e;
        }
      }
    }
    this.#res = _res;
    this.finalized = true;
  }
  render = (...args) => {
    this.#renderer ??= (content) => this.html(content);
    return this.#renderer(...args);
  };
  setLayout = (layout) => this.#layout = layout;
  getLayout = () => this.#layout;
  setRenderer = (renderer) => {
    this.#renderer = renderer;
  };
  header = (name, value, options) => {
    if (value === void 0) {
      if (this.#headers) {
        this.#headers.delete(name);
      } else if (this.#preparedHeaders) {
        delete this.#preparedHeaders[name.toLocaleLowerCase()];
      }
      if (this.finalized) {
        this.res.headers.delete(name);
      }
      return;
    }
    if (options?.append) {
      if (!this.#headers) {
        this.#isFresh = false;
        this.#headers = new Headers(this.#preparedHeaders);
        this.#preparedHeaders = {};
      }
      this.#headers.append(name, value);
    } else {
      if (this.#headers) {
        this.#headers.set(name, value);
      } else {
        this.#preparedHeaders ??= {};
        this.#preparedHeaders[name.toLowerCase()] = value;
      }
    }
    if (this.finalized) {
      if (options?.append) {
        this.res.headers.append(name, value);
      } else {
        this.res.headers.set(name, value);
      }
    }
  };
  status = (status) => {
    this.#isFresh = false;
    this.#status = status;
  };
  set = (key, value) => {
    this.#var ??= /* @__PURE__ */ new Map();
    this.#var.set(key, value);
  };
  get = (key) => {
    return this.#var ? this.#var.get(key) : void 0;
  };
  get var() {
    if (!this.#var) {
      return {};
    }
    return Object.fromEntries(this.#var);
  }
  #newResponse(data, arg, headers) {
    if (this.#isFresh && !headers && !arg && this.#status === 200) {
      return new Response(data, {
        headers: this.#preparedHeaders
      });
    }
    if (arg && typeof arg !== "number") {
      const header = new Headers(arg.headers);
      if (this.#headers) {
        this.#headers.forEach((v, k) => {
          if (k === "set-cookie") {
            header.append(k, v);
          } else {
            header.set(k, v);
          }
        });
      }
      const headers2 = setHeaders(header, this.#preparedHeaders);
      return new Response(data, {
        headers: headers2,
        status: arg.status ?? this.#status
      });
    }
    const status = typeof arg === "number" ? arg : this.#status;
    this.#preparedHeaders ??= {};
    this.#headers ??= new Headers();
    setHeaders(this.#headers, this.#preparedHeaders);
    if (this.#res) {
      this.#res.headers.forEach((v, k) => {
        if (k === "set-cookie") {
          this.#headers?.append(k, v);
        } else {
          this.#headers?.set(k, v);
        }
      });
      setHeaders(this.#headers, this.#preparedHeaders);
    }
    headers ??= {};
    for (const [k, v] of Object.entries(headers)) {
      if (typeof v === "string") {
        this.#headers.set(k, v);
      } else {
        this.#headers.delete(k);
        for (const v2 of v) {
          this.#headers.append(k, v2);
        }
      }
    }
    return new Response(data, {
      status,
      headers: this.#headers
    });
  }
  newResponse = (...args) => this.#newResponse(...args);
  body = (data, arg, headers) => {
    return typeof arg === "number" ? this.#newResponse(data, arg, headers) : this.#newResponse(data, arg);
  };
  text = (text, arg, headers) => {
    if (!this.#preparedHeaders) {
      if (this.#isFresh && !headers && !arg) {
        return new Response(text);
      }
      this.#preparedHeaders = {};
    }
    this.#preparedHeaders["content-type"] = TEXT_PLAIN;
    return typeof arg === "number" ? this.#newResponse(text, arg, headers) : this.#newResponse(text, arg);
  };
  json = (object, arg, headers) => {
    const body = JSON.stringify(object);
    this.#preparedHeaders ??= {};
    this.#preparedHeaders["content-type"] = "application/json; charset=UTF-8";
    return typeof arg === "number" ? this.#newResponse(body, arg, headers) : this.#newResponse(body, arg);
  };
  html = (html2, arg, headers) => {
    this.#preparedHeaders ??= {};
    this.#preparedHeaders["content-type"] = "text/html; charset=UTF-8";
    if (typeof html2 === "object") {
      return resolveCallback(html2, HtmlEscapedCallbackPhase.Stringify, false, {}).then((html22) => {
        return typeof arg === "number" ? this.#newResponse(html22, arg, headers) : this.#newResponse(html22, arg);
      });
    }
    return typeof arg === "number" ? this.#newResponse(html2, arg, headers) : this.#newResponse(html2, arg);
  };
  redirect = (location, status) => {
    this.#headers ??= new Headers();
    this.#headers.set("Location", String(location));
    return this.newResponse(null, status ?? 302);
  };
  notFound = () => {
    this.#notFoundHandler ??= () => new Response();
    return this.#notFoundHandler(this);
  };
}, "Context");

// node_modules/hono/dist/compose.js
var compose = /* @__PURE__ */ __name((middleware2, onError, onNotFound) => {
  return (context2, next) => {
    let index = -1;
    const isContext = context2 instanceof Context;
    return dispatch(0);
    async function dispatch(i) {
      if (i <= index) {
        throw new Error("next() called multiple times");
      }
      index = i;
      let res;
      let isError = false;
      let handler;
      if (middleware2[i]) {
        handler = middleware2[i][0][0];
        if (isContext) {
          context2.req.routeIndex = i;
        }
      } else {
        handler = i === middleware2.length && next || void 0;
      }
      if (!handler) {
        if (isContext && context2.finalized === false && onNotFound) {
          res = await onNotFound(context2);
        }
      } else {
        try {
          res = await handler(context2, () => {
            return dispatch(i + 1);
          });
        } catch (err) {
          if (err instanceof Error && isContext && onError) {
            context2.error = err;
            res = await onError(err, context2);
            isError = true;
          } else {
            throw err;
          }
        }
      }
      if (res && (context2.finalized === false || isError)) {
        context2.res = res;
      }
      return context2;
    }
    __name(dispatch, "dispatch");
  };
}, "compose");

// node_modules/hono/dist/router.js
var METHOD_NAME_ALL = "ALL";
var METHOD_NAME_ALL_LOWERCASE = "all";
var METHODS = ["get", "post", "put", "delete", "options", "patch"];
var MESSAGE_MATCHER_IS_ALREADY_BUILT = "Can not add a route since the matcher is already built.";
var UnsupportedPathError = /* @__PURE__ */ __name(class extends Error {
}, "UnsupportedPathError");

// node_modules/hono/dist/hono-base.js
var COMPOSED_HANDLER = Symbol("composedHandler");
var notFoundHandler = /* @__PURE__ */ __name((c) => {
  return c.text("404 Not Found", 404);
}, "notFoundHandler");
var errorHandler = /* @__PURE__ */ __name((err, c) => {
  if ("getResponse" in err) {
    return err.getResponse();
  }
  console.error(err);
  return c.text("Internal Server Error", 500);
}, "errorHandler");
var Hono = /* @__PURE__ */ __name(class {
  get;
  post;
  put;
  delete;
  options;
  patch;
  all;
  on;
  use;
  router;
  getPath;
  _basePath = "/";
  #path = "/";
  routes = [];
  constructor(options = {}) {
    const allMethods = [...METHODS, METHOD_NAME_ALL_LOWERCASE];
    allMethods.forEach((method) => {
      this[method] = (args1, ...args) => {
        if (typeof args1 === "string") {
          this.#path = args1;
        } else {
          this.#addRoute(method, this.#path, args1);
        }
        args.forEach((handler) => {
          this.#addRoute(method, this.#path, handler);
        });
        return this;
      };
    });
    this.on = (method, path, ...handlers) => {
      for (const p of [path].flat()) {
        this.#path = p;
        for (const m of [method].flat()) {
          handlers.map((handler) => {
            this.#addRoute(m.toUpperCase(), this.#path, handler);
          });
        }
      }
      return this;
    };
    this.use = (arg1, ...handlers) => {
      if (typeof arg1 === "string") {
        this.#path = arg1;
      } else {
        this.#path = "*";
        handlers.unshift(arg1);
      }
      handlers.forEach((handler) => {
        this.#addRoute(METHOD_NAME_ALL, this.#path, handler);
      });
      return this;
    };
    const strict = options.strict ?? true;
    delete options.strict;
    Object.assign(this, options);
    this.getPath = strict ? options.getPath ?? getPath : getPathNoStrict;
  }
  #clone() {
    const clone = new Hono({
      router: this.router,
      getPath: this.getPath
    });
    clone.routes = this.routes;
    return clone;
  }
  #notFoundHandler = notFoundHandler;
  errorHandler = errorHandler;
  route(path, app2) {
    const subApp = this.basePath(path);
    app2.routes.map((r) => {
      let handler;
      if (app2.errorHandler === errorHandler) {
        handler = r.handler;
      } else {
        handler = /* @__PURE__ */ __name(async (c, next) => (await compose([], app2.errorHandler)(c, () => r.handler(c, next))).res, "handler");
        handler[COMPOSED_HANDLER] = r.handler;
      }
      subApp.#addRoute(r.method, r.path, handler);
    });
    return this;
  }
  basePath(path) {
    const subApp = this.#clone();
    subApp._basePath = mergePath(this._basePath, path);
    return subApp;
  }
  onError = (handler) => {
    this.errorHandler = handler;
    return this;
  };
  notFound = (handler) => {
    this.#notFoundHandler = handler;
    return this;
  };
  mount(path, applicationHandler, options) {
    let replaceRequest;
    let optionHandler;
    if (options) {
      if (typeof options === "function") {
        optionHandler = options;
      } else {
        optionHandler = options.optionHandler;
        replaceRequest = options.replaceRequest;
      }
    }
    const getOptions = optionHandler ? (c) => {
      const options2 = optionHandler(c);
      return Array.isArray(options2) ? options2 : [options2];
    } : (c) => {
      let executionContext = void 0;
      try {
        executionContext = c.executionCtx;
      } catch {
      }
      return [c.env, executionContext];
    };
    replaceRequest ||= (() => {
      const mergedPath = mergePath(this._basePath, path);
      const pathPrefixLength = mergedPath === "/" ? 0 : mergedPath.length;
      return (request) => {
        const url = new URL(request.url);
        url.pathname = url.pathname.slice(pathPrefixLength) || "/";
        return new Request(url, request);
      };
    })();
    const handler = /* @__PURE__ */ __name(async (c, next) => {
      const res = await applicationHandler(replaceRequest(c.req.raw), ...getOptions(c));
      if (res) {
        return res;
      }
      await next();
    }, "handler");
    this.#addRoute(METHOD_NAME_ALL, mergePath(path, "*"), handler);
    return this;
  }
  #addRoute(method, path, handler) {
    method = method.toUpperCase();
    path = mergePath(this._basePath, path);
    const r = { path, method, handler };
    this.router.add(method, path, [handler, r]);
    this.routes.push(r);
  }
  #handleError(err, c) {
    if (err instanceof Error) {
      return this.errorHandler(err, c);
    }
    throw err;
  }
  #dispatch(request, executionCtx, env2, method) {
    if (method === "HEAD") {
      return (async () => new Response(null, await this.#dispatch(request, executionCtx, env2, "GET")))();
    }
    const path = this.getPath(request, { env: env2 });
    const matchResult = this.router.match(method, path);
    const c = new Context(request, {
      path,
      matchResult,
      env: env2,
      executionCtx,
      notFoundHandler: this.#notFoundHandler
    });
    if (matchResult[0].length === 1) {
      let res;
      try {
        res = matchResult[0][0][0][0](c, async () => {
          c.res = await this.#notFoundHandler(c);
        });
      } catch (err) {
        return this.#handleError(err, c);
      }
      return res instanceof Promise ? res.then(
        (resolved) => resolved || (c.finalized ? c.res : this.#notFoundHandler(c))
      ).catch((err) => this.#handleError(err, c)) : res ?? this.#notFoundHandler(c);
    }
    const composed = compose(matchResult[0], this.errorHandler, this.#notFoundHandler);
    return (async () => {
      try {
        const context2 = await composed(c);
        if (!context2.finalized) {
          throw new Error(
            "Context is not finalized. Did you forget to return a Response object or `await next()`?"
          );
        }
        return context2.res;
      } catch (err) {
        return this.#handleError(err, c);
      }
    })();
  }
  fetch = (request, ...rest) => {
    return this.#dispatch(request, rest[1], rest[0], request.method);
  };
  request = (input, requestInit, Env, executionCtx) => {
    if (input instanceof Request) {
      return this.fetch(requestInit ? new Request(input, requestInit) : input, Env, executionCtx);
    }
    input = input.toString();
    return this.fetch(
      new Request(
        /^https?:\/\//.test(input) ? input : `http://localhost${mergePath("/", input)}`,
        requestInit
      ),
      Env,
      executionCtx
    );
  };
  fire = () => {
    addEventListener("fetch", (event) => {
      event.respondWith(this.#dispatch(event.request, event, void 0, event.request.method));
    });
  };
}, "Hono");

// node_modules/hono/dist/router/reg-exp-router/node.js
var LABEL_REG_EXP_STR = "[^/]+";
var ONLY_WILDCARD_REG_EXP_STR = ".*";
var TAIL_WILDCARD_REG_EXP_STR = "(?:|/.*)";
var PATH_ERROR = Symbol();
var regExpMetaChars = new Set(".\\+*[^]$()");
function compareKey(a, b) {
  if (a.length === 1) {
    return b.length === 1 ? a < b ? -1 : 1 : -1;
  }
  if (b.length === 1) {
    return 1;
  }
  if (a === ONLY_WILDCARD_REG_EXP_STR || a === TAIL_WILDCARD_REG_EXP_STR) {
    return 1;
  } else if (b === ONLY_WILDCARD_REG_EXP_STR || b === TAIL_WILDCARD_REG_EXP_STR) {
    return -1;
  }
  if (a === LABEL_REG_EXP_STR) {
    return 1;
  } else if (b === LABEL_REG_EXP_STR) {
    return -1;
  }
  return a.length === b.length ? a < b ? -1 : 1 : b.length - a.length;
}
__name(compareKey, "compareKey");
var Node = /* @__PURE__ */ __name(class {
  #index;
  #varIndex;
  #children = /* @__PURE__ */ Object.create(null);
  insert(tokens, index, paramMap, context2, pathErrorCheckOnly) {
    if (tokens.length === 0) {
      if (this.#index !== void 0) {
        throw PATH_ERROR;
      }
      if (pathErrorCheckOnly) {
        return;
      }
      this.#index = index;
      return;
    }
    const [token, ...restTokens] = tokens;
    const pattern = token === "*" ? restTokens.length === 0 ? ["", "", ONLY_WILDCARD_REG_EXP_STR] : ["", "", LABEL_REG_EXP_STR] : token === "/*" ? ["", "", TAIL_WILDCARD_REG_EXP_STR] : token.match(/^\:([^\{\}]+)(?:\{(.+)\})?$/);
    let node;
    if (pattern) {
      const name = pattern[1];
      let regexpStr = pattern[2] || LABEL_REG_EXP_STR;
      if (name && pattern[2]) {
        regexpStr = regexpStr.replace(/^\((?!\?:)(?=[^)]+\)$)/, "(?:");
        if (/\((?!\?:)/.test(regexpStr)) {
          throw PATH_ERROR;
        }
      }
      node = this.#children[regexpStr];
      if (!node) {
        if (Object.keys(this.#children).some(
          (k) => k !== ONLY_WILDCARD_REG_EXP_STR && k !== TAIL_WILDCARD_REG_EXP_STR
        )) {
          throw PATH_ERROR;
        }
        if (pathErrorCheckOnly) {
          return;
        }
        node = this.#children[regexpStr] = new Node();
        if (name !== "") {
          node.#varIndex = context2.varIndex++;
        }
      }
      if (!pathErrorCheckOnly && name !== "") {
        paramMap.push([name, node.#varIndex]);
      }
    } else {
      node = this.#children[token];
      if (!node) {
        if (Object.keys(this.#children).some(
          (k) => k.length > 1 && k !== ONLY_WILDCARD_REG_EXP_STR && k !== TAIL_WILDCARD_REG_EXP_STR
        )) {
          throw PATH_ERROR;
        }
        if (pathErrorCheckOnly) {
          return;
        }
        node = this.#children[token] = new Node();
      }
    }
    node.insert(restTokens, index, paramMap, context2, pathErrorCheckOnly);
  }
  buildRegExpStr() {
    const childKeys = Object.keys(this.#children).sort(compareKey);
    const strList = childKeys.map((k) => {
      const c = this.#children[k];
      return (typeof c.#varIndex === "number" ? `(${k})@${c.#varIndex}` : regExpMetaChars.has(k) ? `\\${k}` : k) + c.buildRegExpStr();
    });
    if (typeof this.#index === "number") {
      strList.unshift(`#${this.#index}`);
    }
    if (strList.length === 0) {
      return "";
    }
    if (strList.length === 1) {
      return strList[0];
    }
    return "(?:" + strList.join("|") + ")";
  }
}, "Node");

// node_modules/hono/dist/router/reg-exp-router/trie.js
var Trie = /* @__PURE__ */ __name(class {
  #context = { varIndex: 0 };
  #root = new Node();
  insert(path, index, pathErrorCheckOnly) {
    const paramAssoc = [];
    const groups = [];
    for (let i = 0; ; ) {
      let replaced = false;
      path = path.replace(/\{[^}]+\}/g, (m) => {
        const mark = `@\\${i}`;
        groups[i] = [mark, m];
        i++;
        replaced = true;
        return mark;
      });
      if (!replaced) {
        break;
      }
    }
    const tokens = path.match(/(?::[^\/]+)|(?:\/\*$)|./g) || [];
    for (let i = groups.length - 1; i >= 0; i--) {
      const [mark] = groups[i];
      for (let j = tokens.length - 1; j >= 0; j--) {
        if (tokens[j].indexOf(mark) !== -1) {
          tokens[j] = tokens[j].replace(mark, groups[i][1]);
          break;
        }
      }
    }
    this.#root.insert(tokens, index, paramAssoc, this.#context, pathErrorCheckOnly);
    return paramAssoc;
  }
  buildRegExp() {
    let regexp = this.#root.buildRegExpStr();
    if (regexp === "") {
      return [/^$/, [], []];
    }
    let captureIndex = 0;
    const indexReplacementMap = [];
    const paramReplacementMap = [];
    regexp = regexp.replace(/#(\d+)|@(\d+)|\.\*\$/g, (_, handlerIndex, paramIndex) => {
      if (handlerIndex !== void 0) {
        indexReplacementMap[++captureIndex] = Number(handlerIndex);
        return "$()";
      }
      if (paramIndex !== void 0) {
        paramReplacementMap[Number(paramIndex)] = ++captureIndex;
        return "";
      }
      return "";
    });
    return [new RegExp(`^${regexp}`), indexReplacementMap, paramReplacementMap];
  }
}, "Trie");

// node_modules/hono/dist/router/reg-exp-router/router.js
var emptyParam = [];
var nullMatcher = [/^$/, [], /* @__PURE__ */ Object.create(null)];
var wildcardRegExpCache = /* @__PURE__ */ Object.create(null);
function buildWildcardRegExp(path) {
  return wildcardRegExpCache[path] ??= new RegExp(
    path === "*" ? "" : `^${path.replace(
      /\/\*$|([.\\+*[^\]$()])/g,
      (_, metaChar) => metaChar ? `\\${metaChar}` : "(?:|/.*)"
    )}$`
  );
}
__name(buildWildcardRegExp, "buildWildcardRegExp");
function clearWildcardRegExpCache() {
  wildcardRegExpCache = /* @__PURE__ */ Object.create(null);
}
__name(clearWildcardRegExpCache, "clearWildcardRegExpCache");
function buildMatcherFromPreprocessedRoutes(routes) {
  const trie = new Trie();
  const handlerData = [];
  if (routes.length === 0) {
    return nullMatcher;
  }
  const routesWithStaticPathFlag = routes.map(
    (route) => [!/\*|\/:/.test(route[0]), ...route]
  ).sort(
    ([isStaticA, pathA], [isStaticB, pathB]) => isStaticA ? 1 : isStaticB ? -1 : pathA.length - pathB.length
  );
  const staticMap = /* @__PURE__ */ Object.create(null);
  for (let i = 0, j = -1, len = routesWithStaticPathFlag.length; i < len; i++) {
    const [pathErrorCheckOnly, path, handlers] = routesWithStaticPathFlag[i];
    if (pathErrorCheckOnly) {
      staticMap[path] = [handlers.map(([h]) => [h, /* @__PURE__ */ Object.create(null)]), emptyParam];
    } else {
      j++;
    }
    let paramAssoc;
    try {
      paramAssoc = trie.insert(path, j, pathErrorCheckOnly);
    } catch (e) {
      throw e === PATH_ERROR ? new UnsupportedPathError(path) : e;
    }
    if (pathErrorCheckOnly) {
      continue;
    }
    handlerData[j] = handlers.map(([h, paramCount]) => {
      const paramIndexMap = /* @__PURE__ */ Object.create(null);
      paramCount -= 1;
      for (; paramCount >= 0; paramCount--) {
        const [key, value] = paramAssoc[paramCount];
        paramIndexMap[key] = value;
      }
      return [h, paramIndexMap];
    });
  }
  const [regexp, indexReplacementMap, paramReplacementMap] = trie.buildRegExp();
  for (let i = 0, len = handlerData.length; i < len; i++) {
    for (let j = 0, len2 = handlerData[i].length; j < len2; j++) {
      const map2 = handlerData[i][j]?.[1];
      if (!map2) {
        continue;
      }
      const keys = Object.keys(map2);
      for (let k = 0, len3 = keys.length; k < len3; k++) {
        map2[keys[k]] = paramReplacementMap[map2[keys[k]]];
      }
    }
  }
  const handlerMap = [];
  for (const i in indexReplacementMap) {
    handlerMap[i] = handlerData[indexReplacementMap[i]];
  }
  return [regexp, handlerMap, staticMap];
}
__name(buildMatcherFromPreprocessedRoutes, "buildMatcherFromPreprocessedRoutes");
function findMiddleware(middleware2, path) {
  if (!middleware2) {
    return void 0;
  }
  for (const k of Object.keys(middleware2).sort((a, b) => b.length - a.length)) {
    if (buildWildcardRegExp(k).test(path)) {
      return [...middleware2[k]];
    }
  }
  return void 0;
}
__name(findMiddleware, "findMiddleware");
var RegExpRouter = /* @__PURE__ */ __name(class {
  name = "RegExpRouter";
  #middleware;
  #routes;
  constructor() {
    this.#middleware = { [METHOD_NAME_ALL]: /* @__PURE__ */ Object.create(null) };
    this.#routes = { [METHOD_NAME_ALL]: /* @__PURE__ */ Object.create(null) };
  }
  add(method, path, handler) {
    const middleware2 = this.#middleware;
    const routes = this.#routes;
    if (!middleware2 || !routes) {
      throw new Error(MESSAGE_MATCHER_IS_ALREADY_BUILT);
    }
    if (!middleware2[method]) {
      ;
      [middleware2, routes].forEach((handlerMap) => {
        handlerMap[method] = /* @__PURE__ */ Object.create(null);
        Object.keys(handlerMap[METHOD_NAME_ALL]).forEach((p) => {
          handlerMap[method][p] = [...handlerMap[METHOD_NAME_ALL][p]];
        });
      });
    }
    if (path === "/*") {
      path = "*";
    }
    const paramCount = (path.match(/\/:/g) || []).length;
    if (/\*$/.test(path)) {
      const re = buildWildcardRegExp(path);
      if (method === METHOD_NAME_ALL) {
        Object.keys(middleware2).forEach((m) => {
          middleware2[m][path] ||= findMiddleware(middleware2[m], path) || findMiddleware(middleware2[METHOD_NAME_ALL], path) || [];
        });
      } else {
        middleware2[method][path] ||= findMiddleware(middleware2[method], path) || findMiddleware(middleware2[METHOD_NAME_ALL], path) || [];
      }
      Object.keys(middleware2).forEach((m) => {
        if (method === METHOD_NAME_ALL || method === m) {
          Object.keys(middleware2[m]).forEach((p) => {
            re.test(p) && middleware2[m][p].push([handler, paramCount]);
          });
        }
      });
      Object.keys(routes).forEach((m) => {
        if (method === METHOD_NAME_ALL || method === m) {
          Object.keys(routes[m]).forEach(
            (p) => re.test(p) && routes[m][p].push([handler, paramCount])
          );
        }
      });
      return;
    }
    const paths = checkOptionalParameter(path) || [path];
    for (let i = 0, len = paths.length; i < len; i++) {
      const path2 = paths[i];
      Object.keys(routes).forEach((m) => {
        if (method === METHOD_NAME_ALL || method === m) {
          routes[m][path2] ||= [
            ...findMiddleware(middleware2[m], path2) || findMiddleware(middleware2[METHOD_NAME_ALL], path2) || []
          ];
          routes[m][path2].push([handler, paramCount - len + i + 1]);
        }
      });
    }
  }
  match(method, path) {
    clearWildcardRegExpCache();
    const matchers = this.#buildAllMatchers();
    this.match = (method2, path2) => {
      const matcher = matchers[method2] || matchers[METHOD_NAME_ALL];
      const staticMatch = matcher[2][path2];
      if (staticMatch) {
        return staticMatch;
      }
      const match = path2.match(matcher[0]);
      if (!match) {
        return [[], emptyParam];
      }
      const index = match.indexOf("", 1);
      return [matcher[1][index], match];
    };
    return this.match(method, path);
  }
  #buildAllMatchers() {
    const matchers = /* @__PURE__ */ Object.create(null);
    Object.keys(this.#routes).concat(Object.keys(this.#middleware)).forEach((method) => {
      matchers[method] ||= this.#buildMatcher(method);
    });
    this.#middleware = this.#routes = void 0;
    return matchers;
  }
  #buildMatcher(method) {
    const routes = [];
    let hasOwnRoute = method === METHOD_NAME_ALL;
    [this.#middleware, this.#routes].forEach((r) => {
      const ownRoute = r[method] ? Object.keys(r[method]).map((path) => [path, r[method][path]]) : [];
      if (ownRoute.length !== 0) {
        hasOwnRoute ||= true;
        routes.push(...ownRoute);
      } else if (method !== METHOD_NAME_ALL) {
        routes.push(
          ...Object.keys(r[METHOD_NAME_ALL]).map((path) => [path, r[METHOD_NAME_ALL][path]])
        );
      }
    });
    if (!hasOwnRoute) {
      return null;
    } else {
      return buildMatcherFromPreprocessedRoutes(routes);
    }
  }
}, "RegExpRouter");

// node_modules/hono/dist/router/smart-router/router.js
var SmartRouter = /* @__PURE__ */ __name(class {
  name = "SmartRouter";
  #routers = [];
  #routes = [];
  constructor(init) {
    this.#routers = init.routers;
  }
  add(method, path, handler) {
    if (!this.#routes) {
      throw new Error(MESSAGE_MATCHER_IS_ALREADY_BUILT);
    }
    this.#routes.push([method, path, handler]);
  }
  match(method, path) {
    if (!this.#routes) {
      throw new Error("Fatal error");
    }
    const routers = this.#routers;
    const routes = this.#routes;
    const len = routers.length;
    let i = 0;
    let res;
    for (; i < len; i++) {
      const router = routers[i];
      try {
        for (let i2 = 0, len2 = routes.length; i2 < len2; i2++) {
          router.add(...routes[i2]);
        }
        res = router.match(method, path);
      } catch (e) {
        if (e instanceof UnsupportedPathError) {
          continue;
        }
        throw e;
      }
      this.match = router.match.bind(router);
      this.#routers = [router];
      this.#routes = void 0;
      break;
    }
    if (i === len) {
      throw new Error("Fatal error");
    }
    this.name = `SmartRouter + ${this.activeRouter.name}`;
    return res;
  }
  get activeRouter() {
    if (this.#routes || this.#routers.length !== 1) {
      throw new Error("No active router has been determined yet.");
    }
    return this.#routers[0];
  }
}, "SmartRouter");

// node_modules/hono/dist/router/trie-router/node.js
var Node2 = /* @__PURE__ */ __name(class {
  #methods;
  #children;
  #patterns;
  #order = 0;
  #params = /* @__PURE__ */ Object.create(null);
  constructor(method, handler, children) {
    this.#children = children || /* @__PURE__ */ Object.create(null);
    this.#methods = [];
    if (method && handler) {
      const m = /* @__PURE__ */ Object.create(null);
      m[method] = { handler, possibleKeys: [], score: 0 };
      this.#methods = [m];
    }
    this.#patterns = [];
  }
  insert(method, path, handler) {
    this.#order = ++this.#order;
    let curNode = this;
    const parts = splitRoutingPath(path);
    const possibleKeys = [];
    for (let i = 0, len = parts.length; i < len; i++) {
      const p = parts[i];
      if (Object.keys(curNode.#children).includes(p)) {
        curNode = curNode.#children[p];
        const pattern2 = getPattern(p);
        if (pattern2) {
          possibleKeys.push(pattern2[1]);
        }
        continue;
      }
      curNode.#children[p] = new Node2();
      const pattern = getPattern(p);
      if (pattern) {
        curNode.#patterns.push(pattern);
        possibleKeys.push(pattern[1]);
      }
      curNode = curNode.#children[p];
    }
    const m = /* @__PURE__ */ Object.create(null);
    const handlerSet = {
      handler,
      possibleKeys: possibleKeys.filter((v, i, a) => a.indexOf(v) === i),
      score: this.#order
    };
    m[method] = handlerSet;
    curNode.#methods.push(m);
    return curNode;
  }
  #getHandlerSets(node, method, nodeParams, params) {
    const handlerSets = [];
    for (let i = 0, len = node.#methods.length; i < len; i++) {
      const m = node.#methods[i];
      const handlerSet = m[method] || m[METHOD_NAME_ALL];
      const processedSet = {};
      if (handlerSet !== void 0) {
        handlerSet.params = /* @__PURE__ */ Object.create(null);
        for (let i2 = 0, len2 = handlerSet.possibleKeys.length; i2 < len2; i2++) {
          const key = handlerSet.possibleKeys[i2];
          const processed = processedSet[handlerSet.score];
          handlerSet.params[key] = params[key] && !processed ? params[key] : nodeParams[key] ?? params[key];
          processedSet[handlerSet.score] = true;
        }
        handlerSets.push(handlerSet);
      }
    }
    return handlerSets;
  }
  search(method, path) {
    const handlerSets = [];
    this.#params = /* @__PURE__ */ Object.create(null);
    const curNode = this;
    let curNodes = [curNode];
    const parts = splitPath(path);
    for (let i = 0, len = parts.length; i < len; i++) {
      const part = parts[i];
      const isLast = i === len - 1;
      const tempNodes = [];
      for (let j = 0, len2 = curNodes.length; j < len2; j++) {
        const node = curNodes[j];
        const nextNode = node.#children[part];
        if (nextNode) {
          nextNode.#params = node.#params;
          if (isLast) {
            if (nextNode.#children["*"]) {
              handlerSets.push(
                ...this.#getHandlerSets(
                  nextNode.#children["*"],
                  method,
                  node.#params,
                  /* @__PURE__ */ Object.create(null)
                )
              );
            }
            handlerSets.push(
              ...this.#getHandlerSets(nextNode, method, node.#params, /* @__PURE__ */ Object.create(null))
            );
          } else {
            tempNodes.push(nextNode);
          }
        }
        for (let k = 0, len3 = node.#patterns.length; k < len3; k++) {
          const pattern = node.#patterns[k];
          const params = { ...node.#params };
          if (pattern === "*") {
            const astNode = node.#children["*"];
            if (astNode) {
              handlerSets.push(
                ...this.#getHandlerSets(astNode, method, node.#params, /* @__PURE__ */ Object.create(null))
              );
              tempNodes.push(astNode);
            }
            continue;
          }
          if (part === "") {
            continue;
          }
          const [key, name, matcher] = pattern;
          const child = node.#children[key];
          const restPathString = parts.slice(i).join("/");
          if (matcher instanceof RegExp && matcher.test(restPathString)) {
            params[name] = restPathString;
            handlerSets.push(...this.#getHandlerSets(child, method, node.#params, params));
            continue;
          }
          if (matcher === true || matcher.test(part)) {
            params[name] = part;
            if (isLast) {
              handlerSets.push(...this.#getHandlerSets(child, method, params, node.#params));
              if (child.#children["*"]) {
                handlerSets.push(
                  ...this.#getHandlerSets(child.#children["*"], method, params, node.#params)
                );
              }
            } else {
              child.#params = params;
              tempNodes.push(child);
            }
          }
        }
      }
      curNodes = tempNodes;
    }
    if (handlerSets.length > 1) {
      handlerSets.sort((a, b) => {
        return a.score - b.score;
      });
    }
    return [handlerSets.map(({ handler, params }) => [handler, params])];
  }
}, "Node");

// node_modules/hono/dist/router/trie-router/router.js
var TrieRouter = /* @__PURE__ */ __name(class {
  name = "TrieRouter";
  #node;
  constructor() {
    this.#node = new Node2();
  }
  add(method, path, handler) {
    const results = checkOptionalParameter(path);
    if (results) {
      for (let i = 0, len = results.length; i < len; i++) {
        this.#node.insert(method, results[i], handler);
      }
      return;
    }
    this.#node.insert(method, path, handler);
  }
  match(method, path) {
    return this.#node.search(method, path);
  }
}, "TrieRouter");

// node_modules/hono/dist/hono.js
var Hono2 = /* @__PURE__ */ __name(class extends Hono {
  constructor(options = {}) {
    super(options);
    this.router = options.router ?? new SmartRouter({
      routers: [new RegExpRouter(), new TrieRouter()]
    });
  }
}, "Hono");

// node_modules/hono/dist/middleware/cors/index.js
var cors = /* @__PURE__ */ __name((options) => {
  const defaults = {
    origin: "*",
    allowMethods: ["GET", "HEAD", "PUT", "POST", "DELETE", "PATCH"],
    allowHeaders: [],
    exposeHeaders: []
  };
  const opts = {
    ...defaults,
    ...options
  };
  const findAllowOrigin = ((optsOrigin) => {
    if (typeof optsOrigin === "string") {
      if (optsOrigin === "*") {
        return () => optsOrigin;
      } else {
        return (origin) => optsOrigin === origin ? origin : null;
      }
    } else if (typeof optsOrigin === "function") {
      return optsOrigin;
    } else {
      return (origin) => optsOrigin.includes(origin) ? origin : null;
    }
  })(opts.origin);
  return /* @__PURE__ */ __name(async function cors2(c, next) {
    function set(key, value) {
      c.res.headers.set(key, value);
    }
    __name(set, "set");
    const allowOrigin = findAllowOrigin(c.req.header("origin") || "", c);
    if (allowOrigin) {
      set("Access-Control-Allow-Origin", allowOrigin);
    }
    if (opts.origin !== "*") {
      const existingVary = c.req.header("Vary");
      if (existingVary) {
        set("Vary", existingVary);
      } else {
        set("Vary", "Origin");
      }
    }
    if (opts.credentials) {
      set("Access-Control-Allow-Credentials", "true");
    }
    if (opts.exposeHeaders?.length) {
      set("Access-Control-Expose-Headers", opts.exposeHeaders.join(","));
    }
    if (c.req.method === "OPTIONS") {
      if (opts.maxAge != null) {
        set("Access-Control-Max-Age", opts.maxAge.toString());
      }
      if (opts.allowMethods?.length) {
        set("Access-Control-Allow-Methods", opts.allowMethods.join(","));
      }
      let headers = opts.allowHeaders;
      if (!headers?.length) {
        const requestHeaders = c.req.header("Access-Control-Request-Headers");
        if (requestHeaders) {
          headers = requestHeaders.split(/\s*,\s*/);
        }
      }
      if (headers?.length) {
        set("Access-Control-Allow-Headers", headers.join(","));
        c.res.headers.append("Vary", "Access-Control-Request-Headers");
      }
      c.res.headers.delete("Content-Length");
      c.res.headers.delete("Content-Type");
      return new Response(null, {
        headers: c.res.headers,
        status: 204,
        statusText: c.res.statusText
      });
    }
    await next();
  }, "cors2");
}, "cors");

// node_modules/hono/dist/http-exception.js
var HTTPException = /* @__PURE__ */ __name(class extends Error {
  res;
  status;
  constructor(status = 500, options) {
    super(options?.message, { cause: options?.cause });
    this.res = options?.res;
    this.status = status;
  }
  getResponse() {
    if (this.res) {
      const newResponse = new Response(this.res.body, {
        status: this.status,
        headers: this.res.headers
      });
      return newResponse;
    }
    return new Response(this.message, {
      status: this.status
    });
  }
}, "HTTPException");

// node_modules/zod/v3/external.js
var external_exports = {};
__export(external_exports, {
  BRAND: () => BRAND,
  DIRTY: () => DIRTY,
  EMPTY_PATH: () => EMPTY_PATH,
  INVALID: () => INVALID,
  NEVER: () => NEVER,
  OK: () => OK,
  ParseStatus: () => ParseStatus,
  Schema: () => ZodType,
  ZodAny: () => ZodAny,
  ZodArray: () => ZodArray,
  ZodBigInt: () => ZodBigInt,
  ZodBoolean: () => ZodBoolean,
  ZodBranded: () => ZodBranded,
  ZodCatch: () => ZodCatch,
  ZodDate: () => ZodDate,
  ZodDefault: () => ZodDefault,
  ZodDiscriminatedUnion: () => ZodDiscriminatedUnion,
  ZodEffects: () => ZodEffects,
  ZodEnum: () => ZodEnum,
  ZodError: () => ZodError,
  ZodFirstPartyTypeKind: () => ZodFirstPartyTypeKind,
  ZodFunction: () => ZodFunction,
  ZodIntersection: () => ZodIntersection,
  ZodIssueCode: () => ZodIssueCode,
  ZodLazy: () => ZodLazy,
  ZodLiteral: () => ZodLiteral,
  ZodMap: () => ZodMap,
  ZodNaN: () => ZodNaN,
  ZodNativeEnum: () => ZodNativeEnum,
  ZodNever: () => ZodNever,
  ZodNull: () => ZodNull,
  ZodNullable: () => ZodNullable,
  ZodNumber: () => ZodNumber,
  ZodObject: () => ZodObject,
  ZodOptional: () => ZodOptional,
  ZodParsedType: () => ZodParsedType,
  ZodPipeline: () => ZodPipeline,
  ZodPromise: () => ZodPromise,
  ZodReadonly: () => ZodReadonly,
  ZodRecord: () => ZodRecord,
  ZodSchema: () => ZodType,
  ZodSet: () => ZodSet,
  ZodString: () => ZodString,
  ZodSymbol: () => ZodSymbol,
  ZodTransformer: () => ZodEffects,
  ZodTuple: () => ZodTuple,
  ZodType: () => ZodType,
  ZodUndefined: () => ZodUndefined,
  ZodUnion: () => ZodUnion,
  ZodUnknown: () => ZodUnknown,
  ZodVoid: () => ZodVoid,
  addIssueToContext: () => addIssueToContext,
  any: () => anyType,
  array: () => arrayType,
  bigint: () => bigIntType,
  boolean: () => booleanType,
  coerce: () => coerce,
  custom: () => custom,
  date: () => dateType,
  datetimeRegex: () => datetimeRegex,
  defaultErrorMap: () => en_default,
  discriminatedUnion: () => discriminatedUnionType,
  effect: () => effectsType,
  enum: () => enumType,
  function: () => functionType,
  getErrorMap: () => getErrorMap,
  getParsedType: () => getParsedType,
  instanceof: () => instanceOfType,
  intersection: () => intersectionType,
  isAborted: () => isAborted,
  isAsync: () => isAsync,
  isDirty: () => isDirty,
  isValid: () => isValid,
  late: () => late,
  lazy: () => lazyType,
  literal: () => literalType,
  makeIssue: () => makeIssue,
  map: () => mapType,
  nan: () => nanType,
  nativeEnum: () => nativeEnumType,
  never: () => neverType,
  null: () => nullType,
  nullable: () => nullableType,
  number: () => numberType,
  object: () => objectType,
  objectUtil: () => objectUtil,
  oboolean: () => oboolean,
  onumber: () => onumber,
  optional: () => optionalType,
  ostring: () => ostring,
  pipeline: () => pipelineType,
  preprocess: () => preprocessType,
  promise: () => promiseType,
  quotelessJson: () => quotelessJson,
  record: () => recordType,
  set: () => setType,
  setErrorMap: () => setErrorMap,
  strictObject: () => strictObjectType,
  string: () => stringType,
  symbol: () => symbolType,
  transformer: () => effectsType,
  tuple: () => tupleType,
  undefined: () => undefinedType,
  union: () => unionType,
  unknown: () => unknownType,
  util: () => util,
  void: () => voidType
});

// node_modules/zod/v3/helpers/util.js
var util;
(function(util2) {
  util2.assertEqual = (_) => {
  };
  function assertIs(_arg) {
  }
  __name(assertIs, "assertIs");
  util2.assertIs = assertIs;
  function assertNever(_x) {
    throw new Error();
  }
  __name(assertNever, "assertNever");
  util2.assertNever = assertNever;
  util2.arrayToEnum = (items) => {
    const obj = {};
    for (const item of items) {
      obj[item] = item;
    }
    return obj;
  };
  util2.getValidEnumValues = (obj) => {
    const validKeys = util2.objectKeys(obj).filter((k) => typeof obj[obj[k]] !== "number");
    const filtered = {};
    for (const k of validKeys) {
      filtered[k] = obj[k];
    }
    return util2.objectValues(filtered);
  };
  util2.objectValues = (obj) => {
    return util2.objectKeys(obj).map(function(e) {
      return obj[e];
    });
  };
  util2.objectKeys = typeof Object.keys === "function" ? (obj) => Object.keys(obj) : (object) => {
    const keys = [];
    for (const key in object) {
      if (Object.prototype.hasOwnProperty.call(object, key)) {
        keys.push(key);
      }
    }
    return keys;
  };
  util2.find = (arr, checker) => {
    for (const item of arr) {
      if (checker(item))
        return item;
    }
    return void 0;
  };
  util2.isInteger = typeof Number.isInteger === "function" ? (val) => Number.isInteger(val) : (val) => typeof val === "number" && Number.isFinite(val) && Math.floor(val) === val;
  function joinValues(array, separator = " | ") {
    return array.map((val) => typeof val === "string" ? `'${val}'` : val).join(separator);
  }
  __name(joinValues, "joinValues");
  util2.joinValues = joinValues;
  util2.jsonStringifyReplacer = (_, value) => {
    if (typeof value === "bigint") {
      return value.toString();
    }
    return value;
  };
})(util || (util = {}));
var objectUtil;
(function(objectUtil2) {
  objectUtil2.mergeShapes = (first, second) => {
    return {
      ...first,
      ...second
      // second overwrites first
    };
  };
})(objectUtil || (objectUtil = {}));
var ZodParsedType = util.arrayToEnum([
  "string",
  "nan",
  "number",
  "integer",
  "float",
  "boolean",
  "date",
  "bigint",
  "symbol",
  "function",
  "undefined",
  "null",
  "array",
  "object",
  "unknown",
  "promise",
  "void",
  "never",
  "map",
  "set"
]);
var getParsedType = /* @__PURE__ */ __name((data) => {
  const t = typeof data;
  switch (t) {
    case "undefined":
      return ZodParsedType.undefined;
    case "string":
      return ZodParsedType.string;
    case "number":
      return Number.isNaN(data) ? ZodParsedType.nan : ZodParsedType.number;
    case "boolean":
      return ZodParsedType.boolean;
    case "function":
      return ZodParsedType.function;
    case "bigint":
      return ZodParsedType.bigint;
    case "symbol":
      return ZodParsedType.symbol;
    case "object":
      if (Array.isArray(data)) {
        return ZodParsedType.array;
      }
      if (data === null) {
        return ZodParsedType.null;
      }
      if (data.then && typeof data.then === "function" && data.catch && typeof data.catch === "function") {
        return ZodParsedType.promise;
      }
      if (typeof Map !== "undefined" && data instanceof Map) {
        return ZodParsedType.map;
      }
      if (typeof Set !== "undefined" && data instanceof Set) {
        return ZodParsedType.set;
      }
      if (typeof Date !== "undefined" && data instanceof Date) {
        return ZodParsedType.date;
      }
      return ZodParsedType.object;
    default:
      return ZodParsedType.unknown;
  }
}, "getParsedType");

// node_modules/zod/v3/ZodError.js
var ZodIssueCode = util.arrayToEnum([
  "invalid_type",
  "invalid_literal",
  "custom",
  "invalid_union",
  "invalid_union_discriminator",
  "invalid_enum_value",
  "unrecognized_keys",
  "invalid_arguments",
  "invalid_return_type",
  "invalid_date",
  "invalid_string",
  "too_small",
  "too_big",
  "invalid_intersection_types",
  "not_multiple_of",
  "not_finite"
]);
var quotelessJson = /* @__PURE__ */ __name((obj) => {
  const json = JSON.stringify(obj, null, 2);
  return json.replace(/"([^"]+)":/g, "$1:");
}, "quotelessJson");
var ZodError = class extends Error {
  get errors() {
    return this.issues;
  }
  constructor(issues) {
    super();
    this.issues = [];
    this.addIssue = (sub) => {
      this.issues = [...this.issues, sub];
    };
    this.addIssues = (subs = []) => {
      this.issues = [...this.issues, ...subs];
    };
    const actualProto = new.target.prototype;
    if (Object.setPrototypeOf) {
      Object.setPrototypeOf(this, actualProto);
    } else {
      this.__proto__ = actualProto;
    }
    this.name = "ZodError";
    this.issues = issues;
  }
  format(_mapper) {
    const mapper = _mapper || function(issue) {
      return issue.message;
    };
    const fieldErrors = { _errors: [] };
    const processError = /* @__PURE__ */ __name((error4) => {
      for (const issue of error4.issues) {
        if (issue.code === "invalid_union") {
          issue.unionErrors.map(processError);
        } else if (issue.code === "invalid_return_type") {
          processError(issue.returnTypeError);
        } else if (issue.code === "invalid_arguments") {
          processError(issue.argumentsError);
        } else if (issue.path.length === 0) {
          fieldErrors._errors.push(mapper(issue));
        } else {
          let curr = fieldErrors;
          let i = 0;
          while (i < issue.path.length) {
            const el = issue.path[i];
            const terminal = i === issue.path.length - 1;
            if (!terminal) {
              curr[el] = curr[el] || { _errors: [] };
            } else {
              curr[el] = curr[el] || { _errors: [] };
              curr[el]._errors.push(mapper(issue));
            }
            curr = curr[el];
            i++;
          }
        }
      }
    }, "processError");
    processError(this);
    return fieldErrors;
  }
  static assert(value) {
    if (!(value instanceof ZodError)) {
      throw new Error(`Not a ZodError: ${value}`);
    }
  }
  toString() {
    return this.message;
  }
  get message() {
    return JSON.stringify(this.issues, util.jsonStringifyReplacer, 2);
  }
  get isEmpty() {
    return this.issues.length === 0;
  }
  flatten(mapper = (issue) => issue.message) {
    const fieldErrors = {};
    const formErrors = [];
    for (const sub of this.issues) {
      if (sub.path.length > 0) {
        const firstEl = sub.path[0];
        fieldErrors[firstEl] = fieldErrors[firstEl] || [];
        fieldErrors[firstEl].push(mapper(sub));
      } else {
        formErrors.push(mapper(sub));
      }
    }
    return { formErrors, fieldErrors };
  }
  get formErrors() {
    return this.flatten();
  }
};
__name(ZodError, "ZodError");
ZodError.create = (issues) => {
  const error4 = new ZodError(issues);
  return error4;
};

// node_modules/zod/v3/locales/en.js
var errorMap = /* @__PURE__ */ __name((issue, _ctx) => {
  let message;
  switch (issue.code) {
    case ZodIssueCode.invalid_type:
      if (issue.received === ZodParsedType.undefined) {
        message = "Required";
      } else {
        message = `Expected ${issue.expected}, received ${issue.received}`;
      }
      break;
    case ZodIssueCode.invalid_literal:
      message = `Invalid literal value, expected ${JSON.stringify(issue.expected, util.jsonStringifyReplacer)}`;
      break;
    case ZodIssueCode.unrecognized_keys:
      message = `Unrecognized key(s) in object: ${util.joinValues(issue.keys, ", ")}`;
      break;
    case ZodIssueCode.invalid_union:
      message = `Invalid input`;
      break;
    case ZodIssueCode.invalid_union_discriminator:
      message = `Invalid discriminator value. Expected ${util.joinValues(issue.options)}`;
      break;
    case ZodIssueCode.invalid_enum_value:
      message = `Invalid enum value. Expected ${util.joinValues(issue.options)}, received '${issue.received}'`;
      break;
    case ZodIssueCode.invalid_arguments:
      message = `Invalid function arguments`;
      break;
    case ZodIssueCode.invalid_return_type:
      message = `Invalid function return type`;
      break;
    case ZodIssueCode.invalid_date:
      message = `Invalid date`;
      break;
    case ZodIssueCode.invalid_string:
      if (typeof issue.validation === "object") {
        if ("includes" in issue.validation) {
          message = `Invalid input: must include "${issue.validation.includes}"`;
          if (typeof issue.validation.position === "number") {
            message = `${message} at one or more positions greater than or equal to ${issue.validation.position}`;
          }
        } else if ("startsWith" in issue.validation) {
          message = `Invalid input: must start with "${issue.validation.startsWith}"`;
        } else if ("endsWith" in issue.validation) {
          message = `Invalid input: must end with "${issue.validation.endsWith}"`;
        } else {
          util.assertNever(issue.validation);
        }
      } else if (issue.validation !== "regex") {
        message = `Invalid ${issue.validation}`;
      } else {
        message = "Invalid";
      }
      break;
    case ZodIssueCode.too_small:
      if (issue.type === "array")
        message = `Array must contain ${issue.exact ? "exactly" : issue.inclusive ? `at least` : `more than`} ${issue.minimum} element(s)`;
      else if (issue.type === "string")
        message = `String must contain ${issue.exact ? "exactly" : issue.inclusive ? `at least` : `over`} ${issue.minimum} character(s)`;
      else if (issue.type === "number")
        message = `Number must be ${issue.exact ? `exactly equal to ` : issue.inclusive ? `greater than or equal to ` : `greater than `}${issue.minimum}`;
      else if (issue.type === "bigint")
        message = `Number must be ${issue.exact ? `exactly equal to ` : issue.inclusive ? `greater than or equal to ` : `greater than `}${issue.minimum}`;
      else if (issue.type === "date")
        message = `Date must be ${issue.exact ? `exactly equal to ` : issue.inclusive ? `greater than or equal to ` : `greater than `}${new Date(Number(issue.minimum))}`;
      else
        message = "Invalid input";
      break;
    case ZodIssueCode.too_big:
      if (issue.type === "array")
        message = `Array must contain ${issue.exact ? `exactly` : issue.inclusive ? `at most` : `less than`} ${issue.maximum} element(s)`;
      else if (issue.type === "string")
        message = `String must contain ${issue.exact ? `exactly` : issue.inclusive ? `at most` : `under`} ${issue.maximum} character(s)`;
      else if (issue.type === "number")
        message = `Number must be ${issue.exact ? `exactly` : issue.inclusive ? `less than or equal to` : `less than`} ${issue.maximum}`;
      else if (issue.type === "bigint")
        message = `BigInt must be ${issue.exact ? `exactly` : issue.inclusive ? `less than or equal to` : `less than`} ${issue.maximum}`;
      else if (issue.type === "date")
        message = `Date must be ${issue.exact ? `exactly` : issue.inclusive ? `smaller than or equal to` : `smaller than`} ${new Date(Number(issue.maximum))}`;
      else
        message = "Invalid input";
      break;
    case ZodIssueCode.custom:
      message = `Invalid input`;
      break;
    case ZodIssueCode.invalid_intersection_types:
      message = `Intersection results could not be merged`;
      break;
    case ZodIssueCode.not_multiple_of:
      message = `Number must be a multiple of ${issue.multipleOf}`;
      break;
    case ZodIssueCode.not_finite:
      message = "Number must be finite";
      break;
    default:
      message = _ctx.defaultError;
      util.assertNever(issue);
  }
  return { message };
}, "errorMap");
var en_default = errorMap;

// node_modules/zod/v3/errors.js
var overrideErrorMap = en_default;
function setErrorMap(map2) {
  overrideErrorMap = map2;
}
__name(setErrorMap, "setErrorMap");
function getErrorMap() {
  return overrideErrorMap;
}
__name(getErrorMap, "getErrorMap");

// node_modules/zod/v3/helpers/parseUtil.js
var makeIssue = /* @__PURE__ */ __name((params) => {
  const { data, path, errorMaps, issueData } = params;
  const fullPath = [...path, ...issueData.path || []];
  const fullIssue = {
    ...issueData,
    path: fullPath
  };
  if (issueData.message !== void 0) {
    return {
      ...issueData,
      path: fullPath,
      message: issueData.message
    };
  }
  let errorMessage = "";
  const maps = errorMaps.filter((m) => !!m).slice().reverse();
  for (const map2 of maps) {
    errorMessage = map2(fullIssue, { data, defaultError: errorMessage }).message;
  }
  return {
    ...issueData,
    path: fullPath,
    message: errorMessage
  };
}, "makeIssue");
var EMPTY_PATH = [];
function addIssueToContext(ctx, issueData) {
  const overrideMap = getErrorMap();
  const issue = makeIssue({
    issueData,
    data: ctx.data,
    path: ctx.path,
    errorMaps: [
      ctx.common.contextualErrorMap,
      // contextual error map is first priority
      ctx.schemaErrorMap,
      // then schema-bound map if available
      overrideMap,
      // then global override map
      overrideMap === en_default ? void 0 : en_default
      // then global default map
    ].filter((x) => !!x)
  });
  ctx.common.issues.push(issue);
}
__name(addIssueToContext, "addIssueToContext");
var ParseStatus = class {
  constructor() {
    this.value = "valid";
  }
  dirty() {
    if (this.value === "valid")
      this.value = "dirty";
  }
  abort() {
    if (this.value !== "aborted")
      this.value = "aborted";
  }
  static mergeArray(status, results) {
    const arrayValue = [];
    for (const s of results) {
      if (s.status === "aborted")
        return INVALID;
      if (s.status === "dirty")
        status.dirty();
      arrayValue.push(s.value);
    }
    return { status: status.value, value: arrayValue };
  }
  static async mergeObjectAsync(status, pairs) {
    const syncPairs = [];
    for (const pair of pairs) {
      const key = await pair.key;
      const value = await pair.value;
      syncPairs.push({
        key,
        value
      });
    }
    return ParseStatus.mergeObjectSync(status, syncPairs);
  }
  static mergeObjectSync(status, pairs) {
    const finalObject = {};
    for (const pair of pairs) {
      const { key, value } = pair;
      if (key.status === "aborted")
        return INVALID;
      if (value.status === "aborted")
        return INVALID;
      if (key.status === "dirty")
        status.dirty();
      if (value.status === "dirty")
        status.dirty();
      if (key.value !== "__proto__" && (typeof value.value !== "undefined" || pair.alwaysSet)) {
        finalObject[key.value] = value.value;
      }
    }
    return { status: status.value, value: finalObject };
  }
};
__name(ParseStatus, "ParseStatus");
var INVALID = Object.freeze({
  status: "aborted"
});
var DIRTY = /* @__PURE__ */ __name((value) => ({ status: "dirty", value }), "DIRTY");
var OK = /* @__PURE__ */ __name((value) => ({ status: "valid", value }), "OK");
var isAborted = /* @__PURE__ */ __name((x) => x.status === "aborted", "isAborted");
var isDirty = /* @__PURE__ */ __name((x) => x.status === "dirty", "isDirty");
var isValid = /* @__PURE__ */ __name((x) => x.status === "valid", "isValid");
var isAsync = /* @__PURE__ */ __name((x) => typeof Promise !== "undefined" && x instanceof Promise, "isAsync");

// node_modules/zod/v3/helpers/errorUtil.js
var errorUtil;
(function(errorUtil2) {
  errorUtil2.errToObj = (message) => typeof message === "string" ? { message } : message || {};
  errorUtil2.toString = (message) => typeof message === "string" ? message : message?.message;
})(errorUtil || (errorUtil = {}));

// node_modules/zod/v3/types.js
var ParseInputLazyPath = class {
  constructor(parent, value, path, key) {
    this._cachedPath = [];
    this.parent = parent;
    this.data = value;
    this._path = path;
    this._key = key;
  }
  get path() {
    if (!this._cachedPath.length) {
      if (Array.isArray(this._key)) {
        this._cachedPath.push(...this._path, ...this._key);
      } else {
        this._cachedPath.push(...this._path, this._key);
      }
    }
    return this._cachedPath;
  }
};
__name(ParseInputLazyPath, "ParseInputLazyPath");
var handleResult = /* @__PURE__ */ __name((ctx, result) => {
  if (isValid(result)) {
    return { success: true, data: result.value };
  } else {
    if (!ctx.common.issues.length) {
      throw new Error("Validation failed but no issues detected.");
    }
    return {
      success: false,
      get error() {
        if (this._error)
          return this._error;
        const error4 = new ZodError(ctx.common.issues);
        this._error = error4;
        return this._error;
      }
    };
  }
}, "handleResult");
function processCreateParams(params) {
  if (!params)
    return {};
  const { errorMap: errorMap2, invalid_type_error, required_error, description } = params;
  if (errorMap2 && (invalid_type_error || required_error)) {
    throw new Error(`Can't use "invalid_type_error" or "required_error" in conjunction with custom error map.`);
  }
  if (errorMap2)
    return { errorMap: errorMap2, description };
  const customMap = /* @__PURE__ */ __name((iss, ctx) => {
    const { message } = params;
    if (iss.code === "invalid_enum_value") {
      return { message: message ?? ctx.defaultError };
    }
    if (typeof ctx.data === "undefined") {
      return { message: message ?? required_error ?? ctx.defaultError };
    }
    if (iss.code !== "invalid_type")
      return { message: ctx.defaultError };
    return { message: message ?? invalid_type_error ?? ctx.defaultError };
  }, "customMap");
  return { errorMap: customMap, description };
}
__name(processCreateParams, "processCreateParams");
var ZodType = class {
  get description() {
    return this._def.description;
  }
  _getType(input) {
    return getParsedType(input.data);
  }
  _getOrReturnCtx(input, ctx) {
    return ctx || {
      common: input.parent.common,
      data: input.data,
      parsedType: getParsedType(input.data),
      schemaErrorMap: this._def.errorMap,
      path: input.path,
      parent: input.parent
    };
  }
  _processInputParams(input) {
    return {
      status: new ParseStatus(),
      ctx: {
        common: input.parent.common,
        data: input.data,
        parsedType: getParsedType(input.data),
        schemaErrorMap: this._def.errorMap,
        path: input.path,
        parent: input.parent
      }
    };
  }
  _parseSync(input) {
    const result = this._parse(input);
    if (isAsync(result)) {
      throw new Error("Synchronous parse encountered promise.");
    }
    return result;
  }
  _parseAsync(input) {
    const result = this._parse(input);
    return Promise.resolve(result);
  }
  parse(data, params) {
    const result = this.safeParse(data, params);
    if (result.success)
      return result.data;
    throw result.error;
  }
  safeParse(data, params) {
    const ctx = {
      common: {
        issues: [],
        async: params?.async ?? false,
        contextualErrorMap: params?.errorMap
      },
      path: params?.path || [],
      schemaErrorMap: this._def.errorMap,
      parent: null,
      data,
      parsedType: getParsedType(data)
    };
    const result = this._parseSync({ data, path: ctx.path, parent: ctx });
    return handleResult(ctx, result);
  }
  "~validate"(data) {
    const ctx = {
      common: {
        issues: [],
        async: !!this["~standard"].async
      },
      path: [],
      schemaErrorMap: this._def.errorMap,
      parent: null,
      data,
      parsedType: getParsedType(data)
    };
    if (!this["~standard"].async) {
      try {
        const result = this._parseSync({ data, path: [], parent: ctx });
        return isValid(result) ? {
          value: result.value
        } : {
          issues: ctx.common.issues
        };
      } catch (err) {
        if (err?.message?.toLowerCase()?.includes("encountered")) {
          this["~standard"].async = true;
        }
        ctx.common = {
          issues: [],
          async: true
        };
      }
    }
    return this._parseAsync({ data, path: [], parent: ctx }).then((result) => isValid(result) ? {
      value: result.value
    } : {
      issues: ctx.common.issues
    });
  }
  async parseAsync(data, params) {
    const result = await this.safeParseAsync(data, params);
    if (result.success)
      return result.data;
    throw result.error;
  }
  async safeParseAsync(data, params) {
    const ctx = {
      common: {
        issues: [],
        contextualErrorMap: params?.errorMap,
        async: true
      },
      path: params?.path || [],
      schemaErrorMap: this._def.errorMap,
      parent: null,
      data,
      parsedType: getParsedType(data)
    };
    const maybeAsyncResult = this._parse({ data, path: ctx.path, parent: ctx });
    const result = await (isAsync(maybeAsyncResult) ? maybeAsyncResult : Promise.resolve(maybeAsyncResult));
    return handleResult(ctx, result);
  }
  refine(check, message) {
    const getIssueProperties = /* @__PURE__ */ __name((val) => {
      if (typeof message === "string" || typeof message === "undefined") {
        return { message };
      } else if (typeof message === "function") {
        return message(val);
      } else {
        return message;
      }
    }, "getIssueProperties");
    return this._refinement((val, ctx) => {
      const result = check(val);
      const setError = /* @__PURE__ */ __name(() => ctx.addIssue({
        code: ZodIssueCode.custom,
        ...getIssueProperties(val)
      }), "setError");
      if (typeof Promise !== "undefined" && result instanceof Promise) {
        return result.then((data) => {
          if (!data) {
            setError();
            return false;
          } else {
            return true;
          }
        });
      }
      if (!result) {
        setError();
        return false;
      } else {
        return true;
      }
    });
  }
  refinement(check, refinementData) {
    return this._refinement((val, ctx) => {
      if (!check(val)) {
        ctx.addIssue(typeof refinementData === "function" ? refinementData(val, ctx) : refinementData);
        return false;
      } else {
        return true;
      }
    });
  }
  _refinement(refinement) {
    return new ZodEffects({
      schema: this,
      typeName: ZodFirstPartyTypeKind.ZodEffects,
      effect: { type: "refinement", refinement }
    });
  }
  superRefine(refinement) {
    return this._refinement(refinement);
  }
  constructor(def) {
    this.spa = this.safeParseAsync;
    this._def = def;
    this.parse = this.parse.bind(this);
    this.safeParse = this.safeParse.bind(this);
    this.parseAsync = this.parseAsync.bind(this);
    this.safeParseAsync = this.safeParseAsync.bind(this);
    this.spa = this.spa.bind(this);
    this.refine = this.refine.bind(this);
    this.refinement = this.refinement.bind(this);
    this.superRefine = this.superRefine.bind(this);
    this.optional = this.optional.bind(this);
    this.nullable = this.nullable.bind(this);
    this.nullish = this.nullish.bind(this);
    this.array = this.array.bind(this);
    this.promise = this.promise.bind(this);
    this.or = this.or.bind(this);
    this.and = this.and.bind(this);
    this.transform = this.transform.bind(this);
    this.brand = this.brand.bind(this);
    this.default = this.default.bind(this);
    this.catch = this.catch.bind(this);
    this.describe = this.describe.bind(this);
    this.pipe = this.pipe.bind(this);
    this.readonly = this.readonly.bind(this);
    this.isNullable = this.isNullable.bind(this);
    this.isOptional = this.isOptional.bind(this);
    this["~standard"] = {
      version: 1,
      vendor: "zod",
      validate: (data) => this["~validate"](data)
    };
  }
  optional() {
    return ZodOptional.create(this, this._def);
  }
  nullable() {
    return ZodNullable.create(this, this._def);
  }
  nullish() {
    return this.nullable().optional();
  }
  array() {
    return ZodArray.create(this);
  }
  promise() {
    return ZodPromise.create(this, this._def);
  }
  or(option) {
    return ZodUnion.create([this, option], this._def);
  }
  and(incoming) {
    return ZodIntersection.create(this, incoming, this._def);
  }
  transform(transform) {
    return new ZodEffects({
      ...processCreateParams(this._def),
      schema: this,
      typeName: ZodFirstPartyTypeKind.ZodEffects,
      effect: { type: "transform", transform }
    });
  }
  default(def) {
    const defaultValueFunc = typeof def === "function" ? def : () => def;
    return new ZodDefault({
      ...processCreateParams(this._def),
      innerType: this,
      defaultValue: defaultValueFunc,
      typeName: ZodFirstPartyTypeKind.ZodDefault
    });
  }
  brand() {
    return new ZodBranded({
      typeName: ZodFirstPartyTypeKind.ZodBranded,
      type: this,
      ...processCreateParams(this._def)
    });
  }
  catch(def) {
    const catchValueFunc = typeof def === "function" ? def : () => def;
    return new ZodCatch({
      ...processCreateParams(this._def),
      innerType: this,
      catchValue: catchValueFunc,
      typeName: ZodFirstPartyTypeKind.ZodCatch
    });
  }
  describe(description) {
    const This = this.constructor;
    return new This({
      ...this._def,
      description
    });
  }
  pipe(target) {
    return ZodPipeline.create(this, target);
  }
  readonly() {
    return ZodReadonly.create(this);
  }
  isOptional() {
    return this.safeParse(void 0).success;
  }
  isNullable() {
    return this.safeParse(null).success;
  }
};
__name(ZodType, "ZodType");
var cuidRegex = /^c[^\s-]{8,}$/i;
var cuid2Regex = /^[0-9a-z]+$/;
var ulidRegex = /^[0-9A-HJKMNP-TV-Z]{26}$/i;
var uuidRegex = /^[0-9a-fA-F]{8}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{12}$/i;
var nanoidRegex = /^[a-z0-9_-]{21}$/i;
var jwtRegex = /^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]*$/;
var durationRegex = /^[-+]?P(?!$)(?:(?:[-+]?\d+Y)|(?:[-+]?\d+[.,]\d+Y$))?(?:(?:[-+]?\d+M)|(?:[-+]?\d+[.,]\d+M$))?(?:(?:[-+]?\d+W)|(?:[-+]?\d+[.,]\d+W$))?(?:(?:[-+]?\d+D)|(?:[-+]?\d+[.,]\d+D$))?(?:T(?=[\d+-])(?:(?:[-+]?\d+H)|(?:[-+]?\d+[.,]\d+H$))?(?:(?:[-+]?\d+M)|(?:[-+]?\d+[.,]\d+M$))?(?:[-+]?\d+(?:[.,]\d+)?S)?)??$/;
var emailRegex = /^(?!\.)(?!.*\.\.)([A-Z0-9_'+\-\.]*)[A-Z0-9_+-]@([A-Z0-9][A-Z0-9\-]*\.)+[A-Z]{2,}$/i;
var _emojiRegex = `^(\\p{Extended_Pictographic}|\\p{Emoji_Component})+$`;
var emojiRegex;
var ipv4Regex = /^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])$/;
var ipv4CidrRegex = /^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\/(3[0-2]|[12]?[0-9])$/;
var ipv6Regex = /^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$/;
var ipv6CidrRegex = /^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))\/(12[0-8]|1[01][0-9]|[1-9]?[0-9])$/;
var base64Regex = /^([0-9a-zA-Z+/]{4})*(([0-9a-zA-Z+/]{2}==)|([0-9a-zA-Z+/]{3}=))?$/;
var base64urlRegex = /^([0-9a-zA-Z-_]{4})*(([0-9a-zA-Z-_]{2}(==)?)|([0-9a-zA-Z-_]{3}(=)?))?$/;
var dateRegexSource = `((\\d\\d[2468][048]|\\d\\d[13579][26]|\\d\\d0[48]|[02468][048]00|[13579][26]00)-02-29|\\d{4}-((0[13578]|1[02])-(0[1-9]|[12]\\d|3[01])|(0[469]|11)-(0[1-9]|[12]\\d|30)|(02)-(0[1-9]|1\\d|2[0-8])))`;
var dateRegex = new RegExp(`^${dateRegexSource}$`);
function timeRegexSource(args) {
  let secondsRegexSource = `[0-5]\\d`;
  if (args.precision) {
    secondsRegexSource = `${secondsRegexSource}\\.\\d{${args.precision}}`;
  } else if (args.precision == null) {
    secondsRegexSource = `${secondsRegexSource}(\\.\\d+)?`;
  }
  const secondsQuantifier = args.precision ? "+" : "?";
  return `([01]\\d|2[0-3]):[0-5]\\d(:${secondsRegexSource})${secondsQuantifier}`;
}
__name(timeRegexSource, "timeRegexSource");
function timeRegex(args) {
  return new RegExp(`^${timeRegexSource(args)}$`);
}
__name(timeRegex, "timeRegex");
function datetimeRegex(args) {
  let regex = `${dateRegexSource}T${timeRegexSource(args)}`;
  const opts = [];
  opts.push(args.local ? `Z?` : `Z`);
  if (args.offset)
    opts.push(`([+-]\\d{2}:?\\d{2})`);
  regex = `${regex}(${opts.join("|")})`;
  return new RegExp(`^${regex}$`);
}
__name(datetimeRegex, "datetimeRegex");
function isValidIP(ip, version2) {
  if ((version2 === "v4" || !version2) && ipv4Regex.test(ip)) {
    return true;
  }
  if ((version2 === "v6" || !version2) && ipv6Regex.test(ip)) {
    return true;
  }
  return false;
}
__name(isValidIP, "isValidIP");
function isValidJWT(jwt, alg) {
  if (!jwtRegex.test(jwt))
    return false;
  try {
    const [header] = jwt.split(".");
    if (!header)
      return false;
    const base64 = header.replace(/-/g, "+").replace(/_/g, "/").padEnd(header.length + (4 - header.length % 4) % 4, "=");
    const decoded = JSON.parse(atob(base64));
    if (typeof decoded !== "object" || decoded === null)
      return false;
    if ("typ" in decoded && decoded?.typ !== "JWT")
      return false;
    if (!decoded.alg)
      return false;
    if (alg && decoded.alg !== alg)
      return false;
    return true;
  } catch {
    return false;
  }
}
__name(isValidJWT, "isValidJWT");
function isValidCidr(ip, version2) {
  if ((version2 === "v4" || !version2) && ipv4CidrRegex.test(ip)) {
    return true;
  }
  if ((version2 === "v6" || !version2) && ipv6CidrRegex.test(ip)) {
    return true;
  }
  return false;
}
__name(isValidCidr, "isValidCidr");
var ZodString = class extends ZodType {
  _parse(input) {
    if (this._def.coerce) {
      input.data = String(input.data);
    }
    const parsedType = this._getType(input);
    if (parsedType !== ZodParsedType.string) {
      const ctx2 = this._getOrReturnCtx(input);
      addIssueToContext(ctx2, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.string,
        received: ctx2.parsedType
      });
      return INVALID;
    }
    const status = new ParseStatus();
    let ctx = void 0;
    for (const check of this._def.checks) {
      if (check.kind === "min") {
        if (input.data.length < check.value) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.too_small,
            minimum: check.value,
            type: "string",
            inclusive: true,
            exact: false,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "max") {
        if (input.data.length > check.value) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.too_big,
            maximum: check.value,
            type: "string",
            inclusive: true,
            exact: false,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "length") {
        const tooBig = input.data.length > check.value;
        const tooSmall = input.data.length < check.value;
        if (tooBig || tooSmall) {
          ctx = this._getOrReturnCtx(input, ctx);
          if (tooBig) {
            addIssueToContext(ctx, {
              code: ZodIssueCode.too_big,
              maximum: check.value,
              type: "string",
              inclusive: true,
              exact: true,
              message: check.message
            });
          } else if (tooSmall) {
            addIssueToContext(ctx, {
              code: ZodIssueCode.too_small,
              minimum: check.value,
              type: "string",
              inclusive: true,
              exact: true,
              message: check.message
            });
          }
          status.dirty();
        }
      } else if (check.kind === "email") {
        if (!emailRegex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "email",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "emoji") {
        if (!emojiRegex) {
          emojiRegex = new RegExp(_emojiRegex, "u");
        }
        if (!emojiRegex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "emoji",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "uuid") {
        if (!uuidRegex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "uuid",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "nanoid") {
        if (!nanoidRegex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "nanoid",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "cuid") {
        if (!cuidRegex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "cuid",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "cuid2") {
        if (!cuid2Regex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "cuid2",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "ulid") {
        if (!ulidRegex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "ulid",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "url") {
        try {
          new URL(input.data);
        } catch {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "url",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "regex") {
        check.regex.lastIndex = 0;
        const testResult = check.regex.test(input.data);
        if (!testResult) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "regex",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "trim") {
        input.data = input.data.trim();
      } else if (check.kind === "includes") {
        if (!input.data.includes(check.value, check.position)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.invalid_string,
            validation: { includes: check.value, position: check.position },
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "toLowerCase") {
        input.data = input.data.toLowerCase();
      } else if (check.kind === "toUpperCase") {
        input.data = input.data.toUpperCase();
      } else if (check.kind === "startsWith") {
        if (!input.data.startsWith(check.value)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.invalid_string,
            validation: { startsWith: check.value },
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "endsWith") {
        if (!input.data.endsWith(check.value)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.invalid_string,
            validation: { endsWith: check.value },
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "datetime") {
        const regex = datetimeRegex(check);
        if (!regex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.invalid_string,
            validation: "datetime",
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "date") {
        const regex = dateRegex;
        if (!regex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.invalid_string,
            validation: "date",
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "time") {
        const regex = timeRegex(check);
        if (!regex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.invalid_string,
            validation: "time",
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "duration") {
        if (!durationRegex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "duration",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "ip") {
        if (!isValidIP(input.data, check.version)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "ip",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "jwt") {
        if (!isValidJWT(input.data, check.alg)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "jwt",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "cidr") {
        if (!isValidCidr(input.data, check.version)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "cidr",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "base64") {
        if (!base64Regex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "base64",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "base64url") {
        if (!base64urlRegex.test(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            validation: "base64url",
            code: ZodIssueCode.invalid_string,
            message: check.message
          });
          status.dirty();
        }
      } else {
        util.assertNever(check);
      }
    }
    return { status: status.value, value: input.data };
  }
  _regex(regex, validation, message) {
    return this.refinement((data) => regex.test(data), {
      validation,
      code: ZodIssueCode.invalid_string,
      ...errorUtil.errToObj(message)
    });
  }
  _addCheck(check) {
    return new ZodString({
      ...this._def,
      checks: [...this._def.checks, check]
    });
  }
  email(message) {
    return this._addCheck({ kind: "email", ...errorUtil.errToObj(message) });
  }
  url(message) {
    return this._addCheck({ kind: "url", ...errorUtil.errToObj(message) });
  }
  emoji(message) {
    return this._addCheck({ kind: "emoji", ...errorUtil.errToObj(message) });
  }
  uuid(message) {
    return this._addCheck({ kind: "uuid", ...errorUtil.errToObj(message) });
  }
  nanoid(message) {
    return this._addCheck({ kind: "nanoid", ...errorUtil.errToObj(message) });
  }
  cuid(message) {
    return this._addCheck({ kind: "cuid", ...errorUtil.errToObj(message) });
  }
  cuid2(message) {
    return this._addCheck({ kind: "cuid2", ...errorUtil.errToObj(message) });
  }
  ulid(message) {
    return this._addCheck({ kind: "ulid", ...errorUtil.errToObj(message) });
  }
  base64(message) {
    return this._addCheck({ kind: "base64", ...errorUtil.errToObj(message) });
  }
  base64url(message) {
    return this._addCheck({
      kind: "base64url",
      ...errorUtil.errToObj(message)
    });
  }
  jwt(options) {
    return this._addCheck({ kind: "jwt", ...errorUtil.errToObj(options) });
  }
  ip(options) {
    return this._addCheck({ kind: "ip", ...errorUtil.errToObj(options) });
  }
  cidr(options) {
    return this._addCheck({ kind: "cidr", ...errorUtil.errToObj(options) });
  }
  datetime(options) {
    if (typeof options === "string") {
      return this._addCheck({
        kind: "datetime",
        precision: null,
        offset: false,
        local: false,
        message: options
      });
    }
    return this._addCheck({
      kind: "datetime",
      precision: typeof options?.precision === "undefined" ? null : options?.precision,
      offset: options?.offset ?? false,
      local: options?.local ?? false,
      ...errorUtil.errToObj(options?.message)
    });
  }
  date(message) {
    return this._addCheck({ kind: "date", message });
  }
  time(options) {
    if (typeof options === "string") {
      return this._addCheck({
        kind: "time",
        precision: null,
        message: options
      });
    }
    return this._addCheck({
      kind: "time",
      precision: typeof options?.precision === "undefined" ? null : options?.precision,
      ...errorUtil.errToObj(options?.message)
    });
  }
  duration(message) {
    return this._addCheck({ kind: "duration", ...errorUtil.errToObj(message) });
  }
  regex(regex, message) {
    return this._addCheck({
      kind: "regex",
      regex,
      ...errorUtil.errToObj(message)
    });
  }
  includes(value, options) {
    return this._addCheck({
      kind: "includes",
      value,
      position: options?.position,
      ...errorUtil.errToObj(options?.message)
    });
  }
  startsWith(value, message) {
    return this._addCheck({
      kind: "startsWith",
      value,
      ...errorUtil.errToObj(message)
    });
  }
  endsWith(value, message) {
    return this._addCheck({
      kind: "endsWith",
      value,
      ...errorUtil.errToObj(message)
    });
  }
  min(minLength, message) {
    return this._addCheck({
      kind: "min",
      value: minLength,
      ...errorUtil.errToObj(message)
    });
  }
  max(maxLength, message) {
    return this._addCheck({
      kind: "max",
      value: maxLength,
      ...errorUtil.errToObj(message)
    });
  }
  length(len, message) {
    return this._addCheck({
      kind: "length",
      value: len,
      ...errorUtil.errToObj(message)
    });
  }
  /**
   * Equivalent to `.min(1)`
   */
  nonempty(message) {
    return this.min(1, errorUtil.errToObj(message));
  }
  trim() {
    return new ZodString({
      ...this._def,
      checks: [...this._def.checks, { kind: "trim" }]
    });
  }
  toLowerCase() {
    return new ZodString({
      ...this._def,
      checks: [...this._def.checks, { kind: "toLowerCase" }]
    });
  }
  toUpperCase() {
    return new ZodString({
      ...this._def,
      checks: [...this._def.checks, { kind: "toUpperCase" }]
    });
  }
  get isDatetime() {
    return !!this._def.checks.find((ch) => ch.kind === "datetime");
  }
  get isDate() {
    return !!this._def.checks.find((ch) => ch.kind === "date");
  }
  get isTime() {
    return !!this._def.checks.find((ch) => ch.kind === "time");
  }
  get isDuration() {
    return !!this._def.checks.find((ch) => ch.kind === "duration");
  }
  get isEmail() {
    return !!this._def.checks.find((ch) => ch.kind === "email");
  }
  get isURL() {
    return !!this._def.checks.find((ch) => ch.kind === "url");
  }
  get isEmoji() {
    return !!this._def.checks.find((ch) => ch.kind === "emoji");
  }
  get isUUID() {
    return !!this._def.checks.find((ch) => ch.kind === "uuid");
  }
  get isNANOID() {
    return !!this._def.checks.find((ch) => ch.kind === "nanoid");
  }
  get isCUID() {
    return !!this._def.checks.find((ch) => ch.kind === "cuid");
  }
  get isCUID2() {
    return !!this._def.checks.find((ch) => ch.kind === "cuid2");
  }
  get isULID() {
    return !!this._def.checks.find((ch) => ch.kind === "ulid");
  }
  get isIP() {
    return !!this._def.checks.find((ch) => ch.kind === "ip");
  }
  get isCIDR() {
    return !!this._def.checks.find((ch) => ch.kind === "cidr");
  }
  get isBase64() {
    return !!this._def.checks.find((ch) => ch.kind === "base64");
  }
  get isBase64url() {
    return !!this._def.checks.find((ch) => ch.kind === "base64url");
  }
  get minLength() {
    let min = null;
    for (const ch of this._def.checks) {
      if (ch.kind === "min") {
        if (min === null || ch.value > min)
          min = ch.value;
      }
    }
    return min;
  }
  get maxLength() {
    let max = null;
    for (const ch of this._def.checks) {
      if (ch.kind === "max") {
        if (max === null || ch.value < max)
          max = ch.value;
      }
    }
    return max;
  }
};
__name(ZodString, "ZodString");
ZodString.create = (params) => {
  return new ZodString({
    checks: [],
    typeName: ZodFirstPartyTypeKind.ZodString,
    coerce: params?.coerce ?? false,
    ...processCreateParams(params)
  });
};
function floatSafeRemainder(val, step) {
  const valDecCount = (val.toString().split(".")[1] || "").length;
  const stepDecCount = (step.toString().split(".")[1] || "").length;
  const decCount = valDecCount > stepDecCount ? valDecCount : stepDecCount;
  const valInt = Number.parseInt(val.toFixed(decCount).replace(".", ""));
  const stepInt = Number.parseInt(step.toFixed(decCount).replace(".", ""));
  return valInt % stepInt / 10 ** decCount;
}
__name(floatSafeRemainder, "floatSafeRemainder");
var ZodNumber = class extends ZodType {
  constructor() {
    super(...arguments);
    this.min = this.gte;
    this.max = this.lte;
    this.step = this.multipleOf;
  }
  _parse(input) {
    if (this._def.coerce) {
      input.data = Number(input.data);
    }
    const parsedType = this._getType(input);
    if (parsedType !== ZodParsedType.number) {
      const ctx2 = this._getOrReturnCtx(input);
      addIssueToContext(ctx2, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.number,
        received: ctx2.parsedType
      });
      return INVALID;
    }
    let ctx = void 0;
    const status = new ParseStatus();
    for (const check of this._def.checks) {
      if (check.kind === "int") {
        if (!util.isInteger(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.invalid_type,
            expected: "integer",
            received: "float",
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "min") {
        const tooSmall = check.inclusive ? input.data < check.value : input.data <= check.value;
        if (tooSmall) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.too_small,
            minimum: check.value,
            type: "number",
            inclusive: check.inclusive,
            exact: false,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "max") {
        const tooBig = check.inclusive ? input.data > check.value : input.data >= check.value;
        if (tooBig) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.too_big,
            maximum: check.value,
            type: "number",
            inclusive: check.inclusive,
            exact: false,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "multipleOf") {
        if (floatSafeRemainder(input.data, check.value) !== 0) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.not_multiple_of,
            multipleOf: check.value,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "finite") {
        if (!Number.isFinite(input.data)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.not_finite,
            message: check.message
          });
          status.dirty();
        }
      } else {
        util.assertNever(check);
      }
    }
    return { status: status.value, value: input.data };
  }
  gte(value, message) {
    return this.setLimit("min", value, true, errorUtil.toString(message));
  }
  gt(value, message) {
    return this.setLimit("min", value, false, errorUtil.toString(message));
  }
  lte(value, message) {
    return this.setLimit("max", value, true, errorUtil.toString(message));
  }
  lt(value, message) {
    return this.setLimit("max", value, false, errorUtil.toString(message));
  }
  setLimit(kind, value, inclusive, message) {
    return new ZodNumber({
      ...this._def,
      checks: [
        ...this._def.checks,
        {
          kind,
          value,
          inclusive,
          message: errorUtil.toString(message)
        }
      ]
    });
  }
  _addCheck(check) {
    return new ZodNumber({
      ...this._def,
      checks: [...this._def.checks, check]
    });
  }
  int(message) {
    return this._addCheck({
      kind: "int",
      message: errorUtil.toString(message)
    });
  }
  positive(message) {
    return this._addCheck({
      kind: "min",
      value: 0,
      inclusive: false,
      message: errorUtil.toString(message)
    });
  }
  negative(message) {
    return this._addCheck({
      kind: "max",
      value: 0,
      inclusive: false,
      message: errorUtil.toString(message)
    });
  }
  nonpositive(message) {
    return this._addCheck({
      kind: "max",
      value: 0,
      inclusive: true,
      message: errorUtil.toString(message)
    });
  }
  nonnegative(message) {
    return this._addCheck({
      kind: "min",
      value: 0,
      inclusive: true,
      message: errorUtil.toString(message)
    });
  }
  multipleOf(value, message) {
    return this._addCheck({
      kind: "multipleOf",
      value,
      message: errorUtil.toString(message)
    });
  }
  finite(message) {
    return this._addCheck({
      kind: "finite",
      message: errorUtil.toString(message)
    });
  }
  safe(message) {
    return this._addCheck({
      kind: "min",
      inclusive: true,
      value: Number.MIN_SAFE_INTEGER,
      message: errorUtil.toString(message)
    })._addCheck({
      kind: "max",
      inclusive: true,
      value: Number.MAX_SAFE_INTEGER,
      message: errorUtil.toString(message)
    });
  }
  get minValue() {
    let min = null;
    for (const ch of this._def.checks) {
      if (ch.kind === "min") {
        if (min === null || ch.value > min)
          min = ch.value;
      }
    }
    return min;
  }
  get maxValue() {
    let max = null;
    for (const ch of this._def.checks) {
      if (ch.kind === "max") {
        if (max === null || ch.value < max)
          max = ch.value;
      }
    }
    return max;
  }
  get isInt() {
    return !!this._def.checks.find((ch) => ch.kind === "int" || ch.kind === "multipleOf" && util.isInteger(ch.value));
  }
  get isFinite() {
    let max = null;
    let min = null;
    for (const ch of this._def.checks) {
      if (ch.kind === "finite" || ch.kind === "int" || ch.kind === "multipleOf") {
        return true;
      } else if (ch.kind === "min") {
        if (min === null || ch.value > min)
          min = ch.value;
      } else if (ch.kind === "max") {
        if (max === null || ch.value < max)
          max = ch.value;
      }
    }
    return Number.isFinite(min) && Number.isFinite(max);
  }
};
__name(ZodNumber, "ZodNumber");
ZodNumber.create = (params) => {
  return new ZodNumber({
    checks: [],
    typeName: ZodFirstPartyTypeKind.ZodNumber,
    coerce: params?.coerce || false,
    ...processCreateParams(params)
  });
};
var ZodBigInt = class extends ZodType {
  constructor() {
    super(...arguments);
    this.min = this.gte;
    this.max = this.lte;
  }
  _parse(input) {
    if (this._def.coerce) {
      try {
        input.data = BigInt(input.data);
      } catch {
        return this._getInvalidInput(input);
      }
    }
    const parsedType = this._getType(input);
    if (parsedType !== ZodParsedType.bigint) {
      return this._getInvalidInput(input);
    }
    let ctx = void 0;
    const status = new ParseStatus();
    for (const check of this._def.checks) {
      if (check.kind === "min") {
        const tooSmall = check.inclusive ? input.data < check.value : input.data <= check.value;
        if (tooSmall) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.too_small,
            type: "bigint",
            minimum: check.value,
            inclusive: check.inclusive,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "max") {
        const tooBig = check.inclusive ? input.data > check.value : input.data >= check.value;
        if (tooBig) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.too_big,
            type: "bigint",
            maximum: check.value,
            inclusive: check.inclusive,
            message: check.message
          });
          status.dirty();
        }
      } else if (check.kind === "multipleOf") {
        if (input.data % check.value !== BigInt(0)) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.not_multiple_of,
            multipleOf: check.value,
            message: check.message
          });
          status.dirty();
        }
      } else {
        util.assertNever(check);
      }
    }
    return { status: status.value, value: input.data };
  }
  _getInvalidInput(input) {
    const ctx = this._getOrReturnCtx(input);
    addIssueToContext(ctx, {
      code: ZodIssueCode.invalid_type,
      expected: ZodParsedType.bigint,
      received: ctx.parsedType
    });
    return INVALID;
  }
  gte(value, message) {
    return this.setLimit("min", value, true, errorUtil.toString(message));
  }
  gt(value, message) {
    return this.setLimit("min", value, false, errorUtil.toString(message));
  }
  lte(value, message) {
    return this.setLimit("max", value, true, errorUtil.toString(message));
  }
  lt(value, message) {
    return this.setLimit("max", value, false, errorUtil.toString(message));
  }
  setLimit(kind, value, inclusive, message) {
    return new ZodBigInt({
      ...this._def,
      checks: [
        ...this._def.checks,
        {
          kind,
          value,
          inclusive,
          message: errorUtil.toString(message)
        }
      ]
    });
  }
  _addCheck(check) {
    return new ZodBigInt({
      ...this._def,
      checks: [...this._def.checks, check]
    });
  }
  positive(message) {
    return this._addCheck({
      kind: "min",
      value: BigInt(0),
      inclusive: false,
      message: errorUtil.toString(message)
    });
  }
  negative(message) {
    return this._addCheck({
      kind: "max",
      value: BigInt(0),
      inclusive: false,
      message: errorUtil.toString(message)
    });
  }
  nonpositive(message) {
    return this._addCheck({
      kind: "max",
      value: BigInt(0),
      inclusive: true,
      message: errorUtil.toString(message)
    });
  }
  nonnegative(message) {
    return this._addCheck({
      kind: "min",
      value: BigInt(0),
      inclusive: true,
      message: errorUtil.toString(message)
    });
  }
  multipleOf(value, message) {
    return this._addCheck({
      kind: "multipleOf",
      value,
      message: errorUtil.toString(message)
    });
  }
  get minValue() {
    let min = null;
    for (const ch of this._def.checks) {
      if (ch.kind === "min") {
        if (min === null || ch.value > min)
          min = ch.value;
      }
    }
    return min;
  }
  get maxValue() {
    let max = null;
    for (const ch of this._def.checks) {
      if (ch.kind === "max") {
        if (max === null || ch.value < max)
          max = ch.value;
      }
    }
    return max;
  }
};
__name(ZodBigInt, "ZodBigInt");
ZodBigInt.create = (params) => {
  return new ZodBigInt({
    checks: [],
    typeName: ZodFirstPartyTypeKind.ZodBigInt,
    coerce: params?.coerce ?? false,
    ...processCreateParams(params)
  });
};
var ZodBoolean = class extends ZodType {
  _parse(input) {
    if (this._def.coerce) {
      input.data = Boolean(input.data);
    }
    const parsedType = this._getType(input);
    if (parsedType !== ZodParsedType.boolean) {
      const ctx = this._getOrReturnCtx(input);
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.boolean,
        received: ctx.parsedType
      });
      return INVALID;
    }
    return OK(input.data);
  }
};
__name(ZodBoolean, "ZodBoolean");
ZodBoolean.create = (params) => {
  return new ZodBoolean({
    typeName: ZodFirstPartyTypeKind.ZodBoolean,
    coerce: params?.coerce || false,
    ...processCreateParams(params)
  });
};
var ZodDate = class extends ZodType {
  _parse(input) {
    if (this._def.coerce) {
      input.data = new Date(input.data);
    }
    const parsedType = this._getType(input);
    if (parsedType !== ZodParsedType.date) {
      const ctx2 = this._getOrReturnCtx(input);
      addIssueToContext(ctx2, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.date,
        received: ctx2.parsedType
      });
      return INVALID;
    }
    if (Number.isNaN(input.data.getTime())) {
      const ctx2 = this._getOrReturnCtx(input);
      addIssueToContext(ctx2, {
        code: ZodIssueCode.invalid_date
      });
      return INVALID;
    }
    const status = new ParseStatus();
    let ctx = void 0;
    for (const check of this._def.checks) {
      if (check.kind === "min") {
        if (input.data.getTime() < check.value) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.too_small,
            message: check.message,
            inclusive: true,
            exact: false,
            minimum: check.value,
            type: "date"
          });
          status.dirty();
        }
      } else if (check.kind === "max") {
        if (input.data.getTime() > check.value) {
          ctx = this._getOrReturnCtx(input, ctx);
          addIssueToContext(ctx, {
            code: ZodIssueCode.too_big,
            message: check.message,
            inclusive: true,
            exact: false,
            maximum: check.value,
            type: "date"
          });
          status.dirty();
        }
      } else {
        util.assertNever(check);
      }
    }
    return {
      status: status.value,
      value: new Date(input.data.getTime())
    };
  }
  _addCheck(check) {
    return new ZodDate({
      ...this._def,
      checks: [...this._def.checks, check]
    });
  }
  min(minDate, message) {
    return this._addCheck({
      kind: "min",
      value: minDate.getTime(),
      message: errorUtil.toString(message)
    });
  }
  max(maxDate, message) {
    return this._addCheck({
      kind: "max",
      value: maxDate.getTime(),
      message: errorUtil.toString(message)
    });
  }
  get minDate() {
    let min = null;
    for (const ch of this._def.checks) {
      if (ch.kind === "min") {
        if (min === null || ch.value > min)
          min = ch.value;
      }
    }
    return min != null ? new Date(min) : null;
  }
  get maxDate() {
    let max = null;
    for (const ch of this._def.checks) {
      if (ch.kind === "max") {
        if (max === null || ch.value < max)
          max = ch.value;
      }
    }
    return max != null ? new Date(max) : null;
  }
};
__name(ZodDate, "ZodDate");
ZodDate.create = (params) => {
  return new ZodDate({
    checks: [],
    coerce: params?.coerce || false,
    typeName: ZodFirstPartyTypeKind.ZodDate,
    ...processCreateParams(params)
  });
};
var ZodSymbol = class extends ZodType {
  _parse(input) {
    const parsedType = this._getType(input);
    if (parsedType !== ZodParsedType.symbol) {
      const ctx = this._getOrReturnCtx(input);
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.symbol,
        received: ctx.parsedType
      });
      return INVALID;
    }
    return OK(input.data);
  }
};
__name(ZodSymbol, "ZodSymbol");
ZodSymbol.create = (params) => {
  return new ZodSymbol({
    typeName: ZodFirstPartyTypeKind.ZodSymbol,
    ...processCreateParams(params)
  });
};
var ZodUndefined = class extends ZodType {
  _parse(input) {
    const parsedType = this._getType(input);
    if (parsedType !== ZodParsedType.undefined) {
      const ctx = this._getOrReturnCtx(input);
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.undefined,
        received: ctx.parsedType
      });
      return INVALID;
    }
    return OK(input.data);
  }
};
__name(ZodUndefined, "ZodUndefined");
ZodUndefined.create = (params) => {
  return new ZodUndefined({
    typeName: ZodFirstPartyTypeKind.ZodUndefined,
    ...processCreateParams(params)
  });
};
var ZodNull = class extends ZodType {
  _parse(input) {
    const parsedType = this._getType(input);
    if (parsedType !== ZodParsedType.null) {
      const ctx = this._getOrReturnCtx(input);
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.null,
        received: ctx.parsedType
      });
      return INVALID;
    }
    return OK(input.data);
  }
};
__name(ZodNull, "ZodNull");
ZodNull.create = (params) => {
  return new ZodNull({
    typeName: ZodFirstPartyTypeKind.ZodNull,
    ...processCreateParams(params)
  });
};
var ZodAny = class extends ZodType {
  constructor() {
    super(...arguments);
    this._any = true;
  }
  _parse(input) {
    return OK(input.data);
  }
};
__name(ZodAny, "ZodAny");
ZodAny.create = (params) => {
  return new ZodAny({
    typeName: ZodFirstPartyTypeKind.ZodAny,
    ...processCreateParams(params)
  });
};
var ZodUnknown = class extends ZodType {
  constructor() {
    super(...arguments);
    this._unknown = true;
  }
  _parse(input) {
    return OK(input.data);
  }
};
__name(ZodUnknown, "ZodUnknown");
ZodUnknown.create = (params) => {
  return new ZodUnknown({
    typeName: ZodFirstPartyTypeKind.ZodUnknown,
    ...processCreateParams(params)
  });
};
var ZodNever = class extends ZodType {
  _parse(input) {
    const ctx = this._getOrReturnCtx(input);
    addIssueToContext(ctx, {
      code: ZodIssueCode.invalid_type,
      expected: ZodParsedType.never,
      received: ctx.parsedType
    });
    return INVALID;
  }
};
__name(ZodNever, "ZodNever");
ZodNever.create = (params) => {
  return new ZodNever({
    typeName: ZodFirstPartyTypeKind.ZodNever,
    ...processCreateParams(params)
  });
};
var ZodVoid = class extends ZodType {
  _parse(input) {
    const parsedType = this._getType(input);
    if (parsedType !== ZodParsedType.undefined) {
      const ctx = this._getOrReturnCtx(input);
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.void,
        received: ctx.parsedType
      });
      return INVALID;
    }
    return OK(input.data);
  }
};
__name(ZodVoid, "ZodVoid");
ZodVoid.create = (params) => {
  return new ZodVoid({
    typeName: ZodFirstPartyTypeKind.ZodVoid,
    ...processCreateParams(params)
  });
};
var ZodArray = class extends ZodType {
  _parse(input) {
    const { ctx, status } = this._processInputParams(input);
    const def = this._def;
    if (ctx.parsedType !== ZodParsedType.array) {
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.array,
        received: ctx.parsedType
      });
      return INVALID;
    }
    if (def.exactLength !== null) {
      const tooBig = ctx.data.length > def.exactLength.value;
      const tooSmall = ctx.data.length < def.exactLength.value;
      if (tooBig || tooSmall) {
        addIssueToContext(ctx, {
          code: tooBig ? ZodIssueCode.too_big : ZodIssueCode.too_small,
          minimum: tooSmall ? def.exactLength.value : void 0,
          maximum: tooBig ? def.exactLength.value : void 0,
          type: "array",
          inclusive: true,
          exact: true,
          message: def.exactLength.message
        });
        status.dirty();
      }
    }
    if (def.minLength !== null) {
      if (ctx.data.length < def.minLength.value) {
        addIssueToContext(ctx, {
          code: ZodIssueCode.too_small,
          minimum: def.minLength.value,
          type: "array",
          inclusive: true,
          exact: false,
          message: def.minLength.message
        });
        status.dirty();
      }
    }
    if (def.maxLength !== null) {
      if (ctx.data.length > def.maxLength.value) {
        addIssueToContext(ctx, {
          code: ZodIssueCode.too_big,
          maximum: def.maxLength.value,
          type: "array",
          inclusive: true,
          exact: false,
          message: def.maxLength.message
        });
        status.dirty();
      }
    }
    if (ctx.common.async) {
      return Promise.all([...ctx.data].map((item, i) => {
        return def.type._parseAsync(new ParseInputLazyPath(ctx, item, ctx.path, i));
      })).then((result2) => {
        return ParseStatus.mergeArray(status, result2);
      });
    }
    const result = [...ctx.data].map((item, i) => {
      return def.type._parseSync(new ParseInputLazyPath(ctx, item, ctx.path, i));
    });
    return ParseStatus.mergeArray(status, result);
  }
  get element() {
    return this._def.type;
  }
  min(minLength, message) {
    return new ZodArray({
      ...this._def,
      minLength: { value: minLength, message: errorUtil.toString(message) }
    });
  }
  max(maxLength, message) {
    return new ZodArray({
      ...this._def,
      maxLength: { value: maxLength, message: errorUtil.toString(message) }
    });
  }
  length(len, message) {
    return new ZodArray({
      ...this._def,
      exactLength: { value: len, message: errorUtil.toString(message) }
    });
  }
  nonempty(message) {
    return this.min(1, message);
  }
};
__name(ZodArray, "ZodArray");
ZodArray.create = (schema, params) => {
  return new ZodArray({
    type: schema,
    minLength: null,
    maxLength: null,
    exactLength: null,
    typeName: ZodFirstPartyTypeKind.ZodArray,
    ...processCreateParams(params)
  });
};
function deepPartialify(schema) {
  if (schema instanceof ZodObject) {
    const newShape = {};
    for (const key in schema.shape) {
      const fieldSchema = schema.shape[key];
      newShape[key] = ZodOptional.create(deepPartialify(fieldSchema));
    }
    return new ZodObject({
      ...schema._def,
      shape: () => newShape
    });
  } else if (schema instanceof ZodArray) {
    return new ZodArray({
      ...schema._def,
      type: deepPartialify(schema.element)
    });
  } else if (schema instanceof ZodOptional) {
    return ZodOptional.create(deepPartialify(schema.unwrap()));
  } else if (schema instanceof ZodNullable) {
    return ZodNullable.create(deepPartialify(schema.unwrap()));
  } else if (schema instanceof ZodTuple) {
    return ZodTuple.create(schema.items.map((item) => deepPartialify(item)));
  } else {
    return schema;
  }
}
__name(deepPartialify, "deepPartialify");
var ZodObject = class extends ZodType {
  constructor() {
    super(...arguments);
    this._cached = null;
    this.nonstrict = this.passthrough;
    this.augment = this.extend;
  }
  _getCached() {
    if (this._cached !== null)
      return this._cached;
    const shape = this._def.shape();
    const keys = util.objectKeys(shape);
    this._cached = { shape, keys };
    return this._cached;
  }
  _parse(input) {
    const parsedType = this._getType(input);
    if (parsedType !== ZodParsedType.object) {
      const ctx2 = this._getOrReturnCtx(input);
      addIssueToContext(ctx2, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.object,
        received: ctx2.parsedType
      });
      return INVALID;
    }
    const { status, ctx } = this._processInputParams(input);
    const { shape, keys: shapeKeys } = this._getCached();
    const extraKeys = [];
    if (!(this._def.catchall instanceof ZodNever && this._def.unknownKeys === "strip")) {
      for (const key in ctx.data) {
        if (!shapeKeys.includes(key)) {
          extraKeys.push(key);
        }
      }
    }
    const pairs = [];
    for (const key of shapeKeys) {
      const keyValidator = shape[key];
      const value = ctx.data[key];
      pairs.push({
        key: { status: "valid", value: key },
        value: keyValidator._parse(new ParseInputLazyPath(ctx, value, ctx.path, key)),
        alwaysSet: key in ctx.data
      });
    }
    if (this._def.catchall instanceof ZodNever) {
      const unknownKeys = this._def.unknownKeys;
      if (unknownKeys === "passthrough") {
        for (const key of extraKeys) {
          pairs.push({
            key: { status: "valid", value: key },
            value: { status: "valid", value: ctx.data[key] }
          });
        }
      } else if (unknownKeys === "strict") {
        if (extraKeys.length > 0) {
          addIssueToContext(ctx, {
            code: ZodIssueCode.unrecognized_keys,
            keys: extraKeys
          });
          status.dirty();
        }
      } else if (unknownKeys === "strip") {
      } else {
        throw new Error(`Internal ZodObject error: invalid unknownKeys value.`);
      }
    } else {
      const catchall = this._def.catchall;
      for (const key of extraKeys) {
        const value = ctx.data[key];
        pairs.push({
          key: { status: "valid", value: key },
          value: catchall._parse(
            new ParseInputLazyPath(ctx, value, ctx.path, key)
            //, ctx.child(key), value, getParsedType(value)
          ),
          alwaysSet: key in ctx.data
        });
      }
    }
    if (ctx.common.async) {
      return Promise.resolve().then(async () => {
        const syncPairs = [];
        for (const pair of pairs) {
          const key = await pair.key;
          const value = await pair.value;
          syncPairs.push({
            key,
            value,
            alwaysSet: pair.alwaysSet
          });
        }
        return syncPairs;
      }).then((syncPairs) => {
        return ParseStatus.mergeObjectSync(status, syncPairs);
      });
    } else {
      return ParseStatus.mergeObjectSync(status, pairs);
    }
  }
  get shape() {
    return this._def.shape();
  }
  strict(message) {
    errorUtil.errToObj;
    return new ZodObject({
      ...this._def,
      unknownKeys: "strict",
      ...message !== void 0 ? {
        errorMap: (issue, ctx) => {
          const defaultError = this._def.errorMap?.(issue, ctx).message ?? ctx.defaultError;
          if (issue.code === "unrecognized_keys")
            return {
              message: errorUtil.errToObj(message).message ?? defaultError
            };
          return {
            message: defaultError
          };
        }
      } : {}
    });
  }
  strip() {
    return new ZodObject({
      ...this._def,
      unknownKeys: "strip"
    });
  }
  passthrough() {
    return new ZodObject({
      ...this._def,
      unknownKeys: "passthrough"
    });
  }
  // const AugmentFactory =
  //   <Def extends ZodObjectDef>(def: Def) =>
  //   <Augmentation extends ZodRawShape>(
  //     augmentation: Augmentation
  //   ): ZodObject<
  //     extendShape<ReturnType<Def["shape"]>, Augmentation>,
  //     Def["unknownKeys"],
  //     Def["catchall"]
  //   > => {
  //     return new ZodObject({
  //       ...def,
  //       shape: () => ({
  //         ...def.shape(),
  //         ...augmentation,
  //       }),
  //     }) as any;
  //   };
  extend(augmentation) {
    return new ZodObject({
      ...this._def,
      shape: () => ({
        ...this._def.shape(),
        ...augmentation
      })
    });
  }
  /**
   * Prior to zod@1.0.12 there was a bug in the
   * inferred type of merged objects. Please
   * upgrade if you are experiencing issues.
   */
  merge(merging) {
    const merged = new ZodObject({
      unknownKeys: merging._def.unknownKeys,
      catchall: merging._def.catchall,
      shape: () => ({
        ...this._def.shape(),
        ...merging._def.shape()
      }),
      typeName: ZodFirstPartyTypeKind.ZodObject
    });
    return merged;
  }
  // merge<
  //   Incoming extends AnyZodObject,
  //   Augmentation extends Incoming["shape"],
  //   NewOutput extends {
  //     [k in keyof Augmentation | keyof Output]: k extends keyof Augmentation
  //       ? Augmentation[k]["_output"]
  //       : k extends keyof Output
  //       ? Output[k]
  //       : never;
  //   },
  //   NewInput extends {
  //     [k in keyof Augmentation | keyof Input]: k extends keyof Augmentation
  //       ? Augmentation[k]["_input"]
  //       : k extends keyof Input
  //       ? Input[k]
  //       : never;
  //   }
  // >(
  //   merging: Incoming
  // ): ZodObject<
  //   extendShape<T, ReturnType<Incoming["_def"]["shape"]>>,
  //   Incoming["_def"]["unknownKeys"],
  //   Incoming["_def"]["catchall"],
  //   NewOutput,
  //   NewInput
  // > {
  //   const merged: any = new ZodObject({
  //     unknownKeys: merging._def.unknownKeys,
  //     catchall: merging._def.catchall,
  //     shape: () =>
  //       objectUtil.mergeShapes(this._def.shape(), merging._def.shape()),
  //     typeName: ZodFirstPartyTypeKind.ZodObject,
  //   }) as any;
  //   return merged;
  // }
  setKey(key, schema) {
    return this.augment({ [key]: schema });
  }
  // merge<Incoming extends AnyZodObject>(
  //   merging: Incoming
  // ): //ZodObject<T & Incoming["_shape"], UnknownKeys, Catchall> = (merging) => {
  // ZodObject<
  //   extendShape<T, ReturnType<Incoming["_def"]["shape"]>>,
  //   Incoming["_def"]["unknownKeys"],
  //   Incoming["_def"]["catchall"]
  // > {
  //   // const mergedShape = objectUtil.mergeShapes(
  //   //   this._def.shape(),
  //   //   merging._def.shape()
  //   // );
  //   const merged: any = new ZodObject({
  //     unknownKeys: merging._def.unknownKeys,
  //     catchall: merging._def.catchall,
  //     shape: () =>
  //       objectUtil.mergeShapes(this._def.shape(), merging._def.shape()),
  //     typeName: ZodFirstPartyTypeKind.ZodObject,
  //   }) as any;
  //   return merged;
  // }
  catchall(index) {
    return new ZodObject({
      ...this._def,
      catchall: index
    });
  }
  pick(mask) {
    const shape = {};
    for (const key of util.objectKeys(mask)) {
      if (mask[key] && this.shape[key]) {
        shape[key] = this.shape[key];
      }
    }
    return new ZodObject({
      ...this._def,
      shape: () => shape
    });
  }
  omit(mask) {
    const shape = {};
    for (const key of util.objectKeys(this.shape)) {
      if (!mask[key]) {
        shape[key] = this.shape[key];
      }
    }
    return new ZodObject({
      ...this._def,
      shape: () => shape
    });
  }
  /**
   * @deprecated
   */
  deepPartial() {
    return deepPartialify(this);
  }
  partial(mask) {
    const newShape = {};
    for (const key of util.objectKeys(this.shape)) {
      const fieldSchema = this.shape[key];
      if (mask && !mask[key]) {
        newShape[key] = fieldSchema;
      } else {
        newShape[key] = fieldSchema.optional();
      }
    }
    return new ZodObject({
      ...this._def,
      shape: () => newShape
    });
  }
  required(mask) {
    const newShape = {};
    for (const key of util.objectKeys(this.shape)) {
      if (mask && !mask[key]) {
        newShape[key] = this.shape[key];
      } else {
        const fieldSchema = this.shape[key];
        let newField = fieldSchema;
        while (newField instanceof ZodOptional) {
          newField = newField._def.innerType;
        }
        newShape[key] = newField;
      }
    }
    return new ZodObject({
      ...this._def,
      shape: () => newShape
    });
  }
  keyof() {
    return createZodEnum(util.objectKeys(this.shape));
  }
};
__name(ZodObject, "ZodObject");
ZodObject.create = (shape, params) => {
  return new ZodObject({
    shape: () => shape,
    unknownKeys: "strip",
    catchall: ZodNever.create(),
    typeName: ZodFirstPartyTypeKind.ZodObject,
    ...processCreateParams(params)
  });
};
ZodObject.strictCreate = (shape, params) => {
  return new ZodObject({
    shape: () => shape,
    unknownKeys: "strict",
    catchall: ZodNever.create(),
    typeName: ZodFirstPartyTypeKind.ZodObject,
    ...processCreateParams(params)
  });
};
ZodObject.lazycreate = (shape, params) => {
  return new ZodObject({
    shape,
    unknownKeys: "strip",
    catchall: ZodNever.create(),
    typeName: ZodFirstPartyTypeKind.ZodObject,
    ...processCreateParams(params)
  });
};
var ZodUnion = class extends ZodType {
  _parse(input) {
    const { ctx } = this._processInputParams(input);
    const options = this._def.options;
    function handleResults(results) {
      for (const result of results) {
        if (result.result.status === "valid") {
          return result.result;
        }
      }
      for (const result of results) {
        if (result.result.status === "dirty") {
          ctx.common.issues.push(...result.ctx.common.issues);
          return result.result;
        }
      }
      const unionErrors = results.map((result) => new ZodError(result.ctx.common.issues));
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_union,
        unionErrors
      });
      return INVALID;
    }
    __name(handleResults, "handleResults");
    if (ctx.common.async) {
      return Promise.all(options.map(async (option) => {
        const childCtx = {
          ...ctx,
          common: {
            ...ctx.common,
            issues: []
          },
          parent: null
        };
        return {
          result: await option._parseAsync({
            data: ctx.data,
            path: ctx.path,
            parent: childCtx
          }),
          ctx: childCtx
        };
      })).then(handleResults);
    } else {
      let dirty = void 0;
      const issues = [];
      for (const option of options) {
        const childCtx = {
          ...ctx,
          common: {
            ...ctx.common,
            issues: []
          },
          parent: null
        };
        const result = option._parseSync({
          data: ctx.data,
          path: ctx.path,
          parent: childCtx
        });
        if (result.status === "valid") {
          return result;
        } else if (result.status === "dirty" && !dirty) {
          dirty = { result, ctx: childCtx };
        }
        if (childCtx.common.issues.length) {
          issues.push(childCtx.common.issues);
        }
      }
      if (dirty) {
        ctx.common.issues.push(...dirty.ctx.common.issues);
        return dirty.result;
      }
      const unionErrors = issues.map((issues2) => new ZodError(issues2));
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_union,
        unionErrors
      });
      return INVALID;
    }
  }
  get options() {
    return this._def.options;
  }
};
__name(ZodUnion, "ZodUnion");
ZodUnion.create = (types, params) => {
  return new ZodUnion({
    options: types,
    typeName: ZodFirstPartyTypeKind.ZodUnion,
    ...processCreateParams(params)
  });
};
var getDiscriminator = /* @__PURE__ */ __name((type) => {
  if (type instanceof ZodLazy) {
    return getDiscriminator(type.schema);
  } else if (type instanceof ZodEffects) {
    return getDiscriminator(type.innerType());
  } else if (type instanceof ZodLiteral) {
    return [type.value];
  } else if (type instanceof ZodEnum) {
    return type.options;
  } else if (type instanceof ZodNativeEnum) {
    return util.objectValues(type.enum);
  } else if (type instanceof ZodDefault) {
    return getDiscriminator(type._def.innerType);
  } else if (type instanceof ZodUndefined) {
    return [void 0];
  } else if (type instanceof ZodNull) {
    return [null];
  } else if (type instanceof ZodOptional) {
    return [void 0, ...getDiscriminator(type.unwrap())];
  } else if (type instanceof ZodNullable) {
    return [null, ...getDiscriminator(type.unwrap())];
  } else if (type instanceof ZodBranded) {
    return getDiscriminator(type.unwrap());
  } else if (type instanceof ZodReadonly) {
    return getDiscriminator(type.unwrap());
  } else if (type instanceof ZodCatch) {
    return getDiscriminator(type._def.innerType);
  } else {
    return [];
  }
}, "getDiscriminator");
var ZodDiscriminatedUnion = class extends ZodType {
  _parse(input) {
    const { ctx } = this._processInputParams(input);
    if (ctx.parsedType !== ZodParsedType.object) {
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.object,
        received: ctx.parsedType
      });
      return INVALID;
    }
    const discriminator = this.discriminator;
    const discriminatorValue = ctx.data[discriminator];
    const option = this.optionsMap.get(discriminatorValue);
    if (!option) {
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_union_discriminator,
        options: Array.from(this.optionsMap.keys()),
        path: [discriminator]
      });
      return INVALID;
    }
    if (ctx.common.async) {
      return option._parseAsync({
        data: ctx.data,
        path: ctx.path,
        parent: ctx
      });
    } else {
      return option._parseSync({
        data: ctx.data,
        path: ctx.path,
        parent: ctx
      });
    }
  }
  get discriminator() {
    return this._def.discriminator;
  }
  get options() {
    return this._def.options;
  }
  get optionsMap() {
    return this._def.optionsMap;
  }
  /**
   * The constructor of the discriminated union schema. Its behaviour is very similar to that of the normal z.union() constructor.
   * However, it only allows a union of objects, all of which need to share a discriminator property. This property must
   * have a different value for each object in the union.
   * @param discriminator the name of the discriminator property
   * @param types an array of object schemas
   * @param params
   */
  static create(discriminator, options, params) {
    const optionsMap = /* @__PURE__ */ new Map();
    for (const type of options) {
      const discriminatorValues = getDiscriminator(type.shape[discriminator]);
      if (!discriminatorValues.length) {
        throw new Error(`A discriminator value for key \`${discriminator}\` could not be extracted from all schema options`);
      }
      for (const value of discriminatorValues) {
        if (optionsMap.has(value)) {
          throw new Error(`Discriminator property ${String(discriminator)} has duplicate value ${String(value)}`);
        }
        optionsMap.set(value, type);
      }
    }
    return new ZodDiscriminatedUnion({
      typeName: ZodFirstPartyTypeKind.ZodDiscriminatedUnion,
      discriminator,
      options,
      optionsMap,
      ...processCreateParams(params)
    });
  }
};
__name(ZodDiscriminatedUnion, "ZodDiscriminatedUnion");
function mergeValues(a, b) {
  const aType = getParsedType(a);
  const bType = getParsedType(b);
  if (a === b) {
    return { valid: true, data: a };
  } else if (aType === ZodParsedType.object && bType === ZodParsedType.object) {
    const bKeys = util.objectKeys(b);
    const sharedKeys = util.objectKeys(a).filter((key) => bKeys.indexOf(key) !== -1);
    const newObj = { ...a, ...b };
    for (const key of sharedKeys) {
      const sharedValue = mergeValues(a[key], b[key]);
      if (!sharedValue.valid) {
        return { valid: false };
      }
      newObj[key] = sharedValue.data;
    }
    return { valid: true, data: newObj };
  } else if (aType === ZodParsedType.array && bType === ZodParsedType.array) {
    if (a.length !== b.length) {
      return { valid: false };
    }
    const newArray = [];
    for (let index = 0; index < a.length; index++) {
      const itemA = a[index];
      const itemB = b[index];
      const sharedValue = mergeValues(itemA, itemB);
      if (!sharedValue.valid) {
        return { valid: false };
      }
      newArray.push(sharedValue.data);
    }
    return { valid: true, data: newArray };
  } else if (aType === ZodParsedType.date && bType === ZodParsedType.date && +a === +b) {
    return { valid: true, data: a };
  } else {
    return { valid: false };
  }
}
__name(mergeValues, "mergeValues");
var ZodIntersection = class extends ZodType {
  _parse(input) {
    const { status, ctx } = this._processInputParams(input);
    const handleParsed = /* @__PURE__ */ __name((parsedLeft, parsedRight) => {
      if (isAborted(parsedLeft) || isAborted(parsedRight)) {
        return INVALID;
      }
      const merged = mergeValues(parsedLeft.value, parsedRight.value);
      if (!merged.valid) {
        addIssueToContext(ctx, {
          code: ZodIssueCode.invalid_intersection_types
        });
        return INVALID;
      }
      if (isDirty(parsedLeft) || isDirty(parsedRight)) {
        status.dirty();
      }
      return { status: status.value, value: merged.data };
    }, "handleParsed");
    if (ctx.common.async) {
      return Promise.all([
        this._def.left._parseAsync({
          data: ctx.data,
          path: ctx.path,
          parent: ctx
        }),
        this._def.right._parseAsync({
          data: ctx.data,
          path: ctx.path,
          parent: ctx
        })
      ]).then(([left, right]) => handleParsed(left, right));
    } else {
      return handleParsed(this._def.left._parseSync({
        data: ctx.data,
        path: ctx.path,
        parent: ctx
      }), this._def.right._parseSync({
        data: ctx.data,
        path: ctx.path,
        parent: ctx
      }));
    }
  }
};
__name(ZodIntersection, "ZodIntersection");
ZodIntersection.create = (left, right, params) => {
  return new ZodIntersection({
    left,
    right,
    typeName: ZodFirstPartyTypeKind.ZodIntersection,
    ...processCreateParams(params)
  });
};
var ZodTuple = class extends ZodType {
  _parse(input) {
    const { status, ctx } = this._processInputParams(input);
    if (ctx.parsedType !== ZodParsedType.array) {
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.array,
        received: ctx.parsedType
      });
      return INVALID;
    }
    if (ctx.data.length < this._def.items.length) {
      addIssueToContext(ctx, {
        code: ZodIssueCode.too_small,
        minimum: this._def.items.length,
        inclusive: true,
        exact: false,
        type: "array"
      });
      return INVALID;
    }
    const rest = this._def.rest;
    if (!rest && ctx.data.length > this._def.items.length) {
      addIssueToContext(ctx, {
        code: ZodIssueCode.too_big,
        maximum: this._def.items.length,
        inclusive: true,
        exact: false,
        type: "array"
      });
      status.dirty();
    }
    const items = [...ctx.data].map((item, itemIndex) => {
      const schema = this._def.items[itemIndex] || this._def.rest;
      if (!schema)
        return null;
      return schema._parse(new ParseInputLazyPath(ctx, item, ctx.path, itemIndex));
    }).filter((x) => !!x);
    if (ctx.common.async) {
      return Promise.all(items).then((results) => {
        return ParseStatus.mergeArray(status, results);
      });
    } else {
      return ParseStatus.mergeArray(status, items);
    }
  }
  get items() {
    return this._def.items;
  }
  rest(rest) {
    return new ZodTuple({
      ...this._def,
      rest
    });
  }
};
__name(ZodTuple, "ZodTuple");
ZodTuple.create = (schemas, params) => {
  if (!Array.isArray(schemas)) {
    throw new Error("You must pass an array of schemas to z.tuple([ ... ])");
  }
  return new ZodTuple({
    items: schemas,
    typeName: ZodFirstPartyTypeKind.ZodTuple,
    rest: null,
    ...processCreateParams(params)
  });
};
var ZodRecord = class extends ZodType {
  get keySchema() {
    return this._def.keyType;
  }
  get valueSchema() {
    return this._def.valueType;
  }
  _parse(input) {
    const { status, ctx } = this._processInputParams(input);
    if (ctx.parsedType !== ZodParsedType.object) {
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.object,
        received: ctx.parsedType
      });
      return INVALID;
    }
    const pairs = [];
    const keyType = this._def.keyType;
    const valueType = this._def.valueType;
    for (const key in ctx.data) {
      pairs.push({
        key: keyType._parse(new ParseInputLazyPath(ctx, key, ctx.path, key)),
        value: valueType._parse(new ParseInputLazyPath(ctx, ctx.data[key], ctx.path, key)),
        alwaysSet: key in ctx.data
      });
    }
    if (ctx.common.async) {
      return ParseStatus.mergeObjectAsync(status, pairs);
    } else {
      return ParseStatus.mergeObjectSync(status, pairs);
    }
  }
  get element() {
    return this._def.valueType;
  }
  static create(first, second, third) {
    if (second instanceof ZodType) {
      return new ZodRecord({
        keyType: first,
        valueType: second,
        typeName: ZodFirstPartyTypeKind.ZodRecord,
        ...processCreateParams(third)
      });
    }
    return new ZodRecord({
      keyType: ZodString.create(),
      valueType: first,
      typeName: ZodFirstPartyTypeKind.ZodRecord,
      ...processCreateParams(second)
    });
  }
};
__name(ZodRecord, "ZodRecord");
var ZodMap = class extends ZodType {
  get keySchema() {
    return this._def.keyType;
  }
  get valueSchema() {
    return this._def.valueType;
  }
  _parse(input) {
    const { status, ctx } = this._processInputParams(input);
    if (ctx.parsedType !== ZodParsedType.map) {
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.map,
        received: ctx.parsedType
      });
      return INVALID;
    }
    const keyType = this._def.keyType;
    const valueType = this._def.valueType;
    const pairs = [...ctx.data.entries()].map(([key, value], index) => {
      return {
        key: keyType._parse(new ParseInputLazyPath(ctx, key, ctx.path, [index, "key"])),
        value: valueType._parse(new ParseInputLazyPath(ctx, value, ctx.path, [index, "value"]))
      };
    });
    if (ctx.common.async) {
      const finalMap = /* @__PURE__ */ new Map();
      return Promise.resolve().then(async () => {
        for (const pair of pairs) {
          const key = await pair.key;
          const value = await pair.value;
          if (key.status === "aborted" || value.status === "aborted") {
            return INVALID;
          }
          if (key.status === "dirty" || value.status === "dirty") {
            status.dirty();
          }
          finalMap.set(key.value, value.value);
        }
        return { status: status.value, value: finalMap };
      });
    } else {
      const finalMap = /* @__PURE__ */ new Map();
      for (const pair of pairs) {
        const key = pair.key;
        const value = pair.value;
        if (key.status === "aborted" || value.status === "aborted") {
          return INVALID;
        }
        if (key.status === "dirty" || value.status === "dirty") {
          status.dirty();
        }
        finalMap.set(key.value, value.value);
      }
      return { status: status.value, value: finalMap };
    }
  }
};
__name(ZodMap, "ZodMap");
ZodMap.create = (keyType, valueType, params) => {
  return new ZodMap({
    valueType,
    keyType,
    typeName: ZodFirstPartyTypeKind.ZodMap,
    ...processCreateParams(params)
  });
};
var ZodSet = class extends ZodType {
  _parse(input) {
    const { status, ctx } = this._processInputParams(input);
    if (ctx.parsedType !== ZodParsedType.set) {
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.set,
        received: ctx.parsedType
      });
      return INVALID;
    }
    const def = this._def;
    if (def.minSize !== null) {
      if (ctx.data.size < def.minSize.value) {
        addIssueToContext(ctx, {
          code: ZodIssueCode.too_small,
          minimum: def.minSize.value,
          type: "set",
          inclusive: true,
          exact: false,
          message: def.minSize.message
        });
        status.dirty();
      }
    }
    if (def.maxSize !== null) {
      if (ctx.data.size > def.maxSize.value) {
        addIssueToContext(ctx, {
          code: ZodIssueCode.too_big,
          maximum: def.maxSize.value,
          type: "set",
          inclusive: true,
          exact: false,
          message: def.maxSize.message
        });
        status.dirty();
      }
    }
    const valueType = this._def.valueType;
    function finalizeSet(elements2) {
      const parsedSet = /* @__PURE__ */ new Set();
      for (const element of elements2) {
        if (element.status === "aborted")
          return INVALID;
        if (element.status === "dirty")
          status.dirty();
        parsedSet.add(element.value);
      }
      return { status: status.value, value: parsedSet };
    }
    __name(finalizeSet, "finalizeSet");
    const elements = [...ctx.data.values()].map((item, i) => valueType._parse(new ParseInputLazyPath(ctx, item, ctx.path, i)));
    if (ctx.common.async) {
      return Promise.all(elements).then((elements2) => finalizeSet(elements2));
    } else {
      return finalizeSet(elements);
    }
  }
  min(minSize, message) {
    return new ZodSet({
      ...this._def,
      minSize: { value: minSize, message: errorUtil.toString(message) }
    });
  }
  max(maxSize, message) {
    return new ZodSet({
      ...this._def,
      maxSize: { value: maxSize, message: errorUtil.toString(message) }
    });
  }
  size(size, message) {
    return this.min(size, message).max(size, message);
  }
  nonempty(message) {
    return this.min(1, message);
  }
};
__name(ZodSet, "ZodSet");
ZodSet.create = (valueType, params) => {
  return new ZodSet({
    valueType,
    minSize: null,
    maxSize: null,
    typeName: ZodFirstPartyTypeKind.ZodSet,
    ...processCreateParams(params)
  });
};
var ZodFunction = class extends ZodType {
  constructor() {
    super(...arguments);
    this.validate = this.implement;
  }
  _parse(input) {
    const { ctx } = this._processInputParams(input);
    if (ctx.parsedType !== ZodParsedType.function) {
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.function,
        received: ctx.parsedType
      });
      return INVALID;
    }
    function makeArgsIssue(args, error4) {
      return makeIssue({
        data: args,
        path: ctx.path,
        errorMaps: [ctx.common.contextualErrorMap, ctx.schemaErrorMap, getErrorMap(), en_default].filter((x) => !!x),
        issueData: {
          code: ZodIssueCode.invalid_arguments,
          argumentsError: error4
        }
      });
    }
    __name(makeArgsIssue, "makeArgsIssue");
    function makeReturnsIssue(returns, error4) {
      return makeIssue({
        data: returns,
        path: ctx.path,
        errorMaps: [ctx.common.contextualErrorMap, ctx.schemaErrorMap, getErrorMap(), en_default].filter((x) => !!x),
        issueData: {
          code: ZodIssueCode.invalid_return_type,
          returnTypeError: error4
        }
      });
    }
    __name(makeReturnsIssue, "makeReturnsIssue");
    const params = { errorMap: ctx.common.contextualErrorMap };
    const fn = ctx.data;
    if (this._def.returns instanceof ZodPromise) {
      const me = this;
      return OK(async function(...args) {
        const error4 = new ZodError([]);
        const parsedArgs = await me._def.args.parseAsync(args, params).catch((e) => {
          error4.addIssue(makeArgsIssue(args, e));
          throw error4;
        });
        const result = await Reflect.apply(fn, this, parsedArgs);
        const parsedReturns = await me._def.returns._def.type.parseAsync(result, params).catch((e) => {
          error4.addIssue(makeReturnsIssue(result, e));
          throw error4;
        });
        return parsedReturns;
      });
    } else {
      const me = this;
      return OK(function(...args) {
        const parsedArgs = me._def.args.safeParse(args, params);
        if (!parsedArgs.success) {
          throw new ZodError([makeArgsIssue(args, parsedArgs.error)]);
        }
        const result = Reflect.apply(fn, this, parsedArgs.data);
        const parsedReturns = me._def.returns.safeParse(result, params);
        if (!parsedReturns.success) {
          throw new ZodError([makeReturnsIssue(result, parsedReturns.error)]);
        }
        return parsedReturns.data;
      });
    }
  }
  parameters() {
    return this._def.args;
  }
  returnType() {
    return this._def.returns;
  }
  args(...items) {
    return new ZodFunction({
      ...this._def,
      args: ZodTuple.create(items).rest(ZodUnknown.create())
    });
  }
  returns(returnType) {
    return new ZodFunction({
      ...this._def,
      returns: returnType
    });
  }
  implement(func) {
    const validatedFunc = this.parse(func);
    return validatedFunc;
  }
  strictImplement(func) {
    const validatedFunc = this.parse(func);
    return validatedFunc;
  }
  static create(args, returns, params) {
    return new ZodFunction({
      args: args ? args : ZodTuple.create([]).rest(ZodUnknown.create()),
      returns: returns || ZodUnknown.create(),
      typeName: ZodFirstPartyTypeKind.ZodFunction,
      ...processCreateParams(params)
    });
  }
};
__name(ZodFunction, "ZodFunction");
var ZodLazy = class extends ZodType {
  get schema() {
    return this._def.getter();
  }
  _parse(input) {
    const { ctx } = this._processInputParams(input);
    const lazySchema = this._def.getter();
    return lazySchema._parse({ data: ctx.data, path: ctx.path, parent: ctx });
  }
};
__name(ZodLazy, "ZodLazy");
ZodLazy.create = (getter, params) => {
  return new ZodLazy({
    getter,
    typeName: ZodFirstPartyTypeKind.ZodLazy,
    ...processCreateParams(params)
  });
};
var ZodLiteral = class extends ZodType {
  _parse(input) {
    if (input.data !== this._def.value) {
      const ctx = this._getOrReturnCtx(input);
      addIssueToContext(ctx, {
        received: ctx.data,
        code: ZodIssueCode.invalid_literal,
        expected: this._def.value
      });
      return INVALID;
    }
    return { status: "valid", value: input.data };
  }
  get value() {
    return this._def.value;
  }
};
__name(ZodLiteral, "ZodLiteral");
ZodLiteral.create = (value, params) => {
  return new ZodLiteral({
    value,
    typeName: ZodFirstPartyTypeKind.ZodLiteral,
    ...processCreateParams(params)
  });
};
function createZodEnum(values, params) {
  return new ZodEnum({
    values,
    typeName: ZodFirstPartyTypeKind.ZodEnum,
    ...processCreateParams(params)
  });
}
__name(createZodEnum, "createZodEnum");
var ZodEnum = class extends ZodType {
  _parse(input) {
    if (typeof input.data !== "string") {
      const ctx = this._getOrReturnCtx(input);
      const expectedValues = this._def.values;
      addIssueToContext(ctx, {
        expected: util.joinValues(expectedValues),
        received: ctx.parsedType,
        code: ZodIssueCode.invalid_type
      });
      return INVALID;
    }
    if (!this._cache) {
      this._cache = new Set(this._def.values);
    }
    if (!this._cache.has(input.data)) {
      const ctx = this._getOrReturnCtx(input);
      const expectedValues = this._def.values;
      addIssueToContext(ctx, {
        received: ctx.data,
        code: ZodIssueCode.invalid_enum_value,
        options: expectedValues
      });
      return INVALID;
    }
    return OK(input.data);
  }
  get options() {
    return this._def.values;
  }
  get enum() {
    const enumValues = {};
    for (const val of this._def.values) {
      enumValues[val] = val;
    }
    return enumValues;
  }
  get Values() {
    const enumValues = {};
    for (const val of this._def.values) {
      enumValues[val] = val;
    }
    return enumValues;
  }
  get Enum() {
    const enumValues = {};
    for (const val of this._def.values) {
      enumValues[val] = val;
    }
    return enumValues;
  }
  extract(values, newDef = this._def) {
    return ZodEnum.create(values, {
      ...this._def,
      ...newDef
    });
  }
  exclude(values, newDef = this._def) {
    return ZodEnum.create(this.options.filter((opt) => !values.includes(opt)), {
      ...this._def,
      ...newDef
    });
  }
};
__name(ZodEnum, "ZodEnum");
ZodEnum.create = createZodEnum;
var ZodNativeEnum = class extends ZodType {
  _parse(input) {
    const nativeEnumValues = util.getValidEnumValues(this._def.values);
    const ctx = this._getOrReturnCtx(input);
    if (ctx.parsedType !== ZodParsedType.string && ctx.parsedType !== ZodParsedType.number) {
      const expectedValues = util.objectValues(nativeEnumValues);
      addIssueToContext(ctx, {
        expected: util.joinValues(expectedValues),
        received: ctx.parsedType,
        code: ZodIssueCode.invalid_type
      });
      return INVALID;
    }
    if (!this._cache) {
      this._cache = new Set(util.getValidEnumValues(this._def.values));
    }
    if (!this._cache.has(input.data)) {
      const expectedValues = util.objectValues(nativeEnumValues);
      addIssueToContext(ctx, {
        received: ctx.data,
        code: ZodIssueCode.invalid_enum_value,
        options: expectedValues
      });
      return INVALID;
    }
    return OK(input.data);
  }
  get enum() {
    return this._def.values;
  }
};
__name(ZodNativeEnum, "ZodNativeEnum");
ZodNativeEnum.create = (values, params) => {
  return new ZodNativeEnum({
    values,
    typeName: ZodFirstPartyTypeKind.ZodNativeEnum,
    ...processCreateParams(params)
  });
};
var ZodPromise = class extends ZodType {
  unwrap() {
    return this._def.type;
  }
  _parse(input) {
    const { ctx } = this._processInputParams(input);
    if (ctx.parsedType !== ZodParsedType.promise && ctx.common.async === false) {
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.promise,
        received: ctx.parsedType
      });
      return INVALID;
    }
    const promisified = ctx.parsedType === ZodParsedType.promise ? ctx.data : Promise.resolve(ctx.data);
    return OK(promisified.then((data) => {
      return this._def.type.parseAsync(data, {
        path: ctx.path,
        errorMap: ctx.common.contextualErrorMap
      });
    }));
  }
};
__name(ZodPromise, "ZodPromise");
ZodPromise.create = (schema, params) => {
  return new ZodPromise({
    type: schema,
    typeName: ZodFirstPartyTypeKind.ZodPromise,
    ...processCreateParams(params)
  });
};
var ZodEffects = class extends ZodType {
  innerType() {
    return this._def.schema;
  }
  sourceType() {
    return this._def.schema._def.typeName === ZodFirstPartyTypeKind.ZodEffects ? this._def.schema.sourceType() : this._def.schema;
  }
  _parse(input) {
    const { status, ctx } = this._processInputParams(input);
    const effect = this._def.effect || null;
    const checkCtx = {
      addIssue: (arg) => {
        addIssueToContext(ctx, arg);
        if (arg.fatal) {
          status.abort();
        } else {
          status.dirty();
        }
      },
      get path() {
        return ctx.path;
      }
    };
    checkCtx.addIssue = checkCtx.addIssue.bind(checkCtx);
    if (effect.type === "preprocess") {
      const processed = effect.transform(ctx.data, checkCtx);
      if (ctx.common.async) {
        return Promise.resolve(processed).then(async (processed2) => {
          if (status.value === "aborted")
            return INVALID;
          const result = await this._def.schema._parseAsync({
            data: processed2,
            path: ctx.path,
            parent: ctx
          });
          if (result.status === "aborted")
            return INVALID;
          if (result.status === "dirty")
            return DIRTY(result.value);
          if (status.value === "dirty")
            return DIRTY(result.value);
          return result;
        });
      } else {
        if (status.value === "aborted")
          return INVALID;
        const result = this._def.schema._parseSync({
          data: processed,
          path: ctx.path,
          parent: ctx
        });
        if (result.status === "aborted")
          return INVALID;
        if (result.status === "dirty")
          return DIRTY(result.value);
        if (status.value === "dirty")
          return DIRTY(result.value);
        return result;
      }
    }
    if (effect.type === "refinement") {
      const executeRefinement = /* @__PURE__ */ __name((acc) => {
        const result = effect.refinement(acc, checkCtx);
        if (ctx.common.async) {
          return Promise.resolve(result);
        }
        if (result instanceof Promise) {
          throw new Error("Async refinement encountered during synchronous parse operation. Use .parseAsync instead.");
        }
        return acc;
      }, "executeRefinement");
      if (ctx.common.async === false) {
        const inner = this._def.schema._parseSync({
          data: ctx.data,
          path: ctx.path,
          parent: ctx
        });
        if (inner.status === "aborted")
          return INVALID;
        if (inner.status === "dirty")
          status.dirty();
        executeRefinement(inner.value);
        return { status: status.value, value: inner.value };
      } else {
        return this._def.schema._parseAsync({ data: ctx.data, path: ctx.path, parent: ctx }).then((inner) => {
          if (inner.status === "aborted")
            return INVALID;
          if (inner.status === "dirty")
            status.dirty();
          return executeRefinement(inner.value).then(() => {
            return { status: status.value, value: inner.value };
          });
        });
      }
    }
    if (effect.type === "transform") {
      if (ctx.common.async === false) {
        const base2 = this._def.schema._parseSync({
          data: ctx.data,
          path: ctx.path,
          parent: ctx
        });
        if (!isValid(base2))
          return INVALID;
        const result = effect.transform(base2.value, checkCtx);
        if (result instanceof Promise) {
          throw new Error(`Asynchronous transform encountered during synchronous parse operation. Use .parseAsync instead.`);
        }
        return { status: status.value, value: result };
      } else {
        return this._def.schema._parseAsync({ data: ctx.data, path: ctx.path, parent: ctx }).then((base2) => {
          if (!isValid(base2))
            return INVALID;
          return Promise.resolve(effect.transform(base2.value, checkCtx)).then((result) => ({
            status: status.value,
            value: result
          }));
        });
      }
    }
    util.assertNever(effect);
  }
};
__name(ZodEffects, "ZodEffects");
ZodEffects.create = (schema, effect, params) => {
  return new ZodEffects({
    schema,
    typeName: ZodFirstPartyTypeKind.ZodEffects,
    effect,
    ...processCreateParams(params)
  });
};
ZodEffects.createWithPreprocess = (preprocess, schema, params) => {
  return new ZodEffects({
    schema,
    effect: { type: "preprocess", transform: preprocess },
    typeName: ZodFirstPartyTypeKind.ZodEffects,
    ...processCreateParams(params)
  });
};
var ZodOptional = class extends ZodType {
  _parse(input) {
    const parsedType = this._getType(input);
    if (parsedType === ZodParsedType.undefined) {
      return OK(void 0);
    }
    return this._def.innerType._parse(input);
  }
  unwrap() {
    return this._def.innerType;
  }
};
__name(ZodOptional, "ZodOptional");
ZodOptional.create = (type, params) => {
  return new ZodOptional({
    innerType: type,
    typeName: ZodFirstPartyTypeKind.ZodOptional,
    ...processCreateParams(params)
  });
};
var ZodNullable = class extends ZodType {
  _parse(input) {
    const parsedType = this._getType(input);
    if (parsedType === ZodParsedType.null) {
      return OK(null);
    }
    return this._def.innerType._parse(input);
  }
  unwrap() {
    return this._def.innerType;
  }
};
__name(ZodNullable, "ZodNullable");
ZodNullable.create = (type, params) => {
  return new ZodNullable({
    innerType: type,
    typeName: ZodFirstPartyTypeKind.ZodNullable,
    ...processCreateParams(params)
  });
};
var ZodDefault = class extends ZodType {
  _parse(input) {
    const { ctx } = this._processInputParams(input);
    let data = ctx.data;
    if (ctx.parsedType === ZodParsedType.undefined) {
      data = this._def.defaultValue();
    }
    return this._def.innerType._parse({
      data,
      path: ctx.path,
      parent: ctx
    });
  }
  removeDefault() {
    return this._def.innerType;
  }
};
__name(ZodDefault, "ZodDefault");
ZodDefault.create = (type, params) => {
  return new ZodDefault({
    innerType: type,
    typeName: ZodFirstPartyTypeKind.ZodDefault,
    defaultValue: typeof params.default === "function" ? params.default : () => params.default,
    ...processCreateParams(params)
  });
};
var ZodCatch = class extends ZodType {
  _parse(input) {
    const { ctx } = this._processInputParams(input);
    const newCtx = {
      ...ctx,
      common: {
        ...ctx.common,
        issues: []
      }
    };
    const result = this._def.innerType._parse({
      data: newCtx.data,
      path: newCtx.path,
      parent: {
        ...newCtx
      }
    });
    if (isAsync(result)) {
      return result.then((result2) => {
        return {
          status: "valid",
          value: result2.status === "valid" ? result2.value : this._def.catchValue({
            get error() {
              return new ZodError(newCtx.common.issues);
            },
            input: newCtx.data
          })
        };
      });
    } else {
      return {
        status: "valid",
        value: result.status === "valid" ? result.value : this._def.catchValue({
          get error() {
            return new ZodError(newCtx.common.issues);
          },
          input: newCtx.data
        })
      };
    }
  }
  removeCatch() {
    return this._def.innerType;
  }
};
__name(ZodCatch, "ZodCatch");
ZodCatch.create = (type, params) => {
  return new ZodCatch({
    innerType: type,
    typeName: ZodFirstPartyTypeKind.ZodCatch,
    catchValue: typeof params.catch === "function" ? params.catch : () => params.catch,
    ...processCreateParams(params)
  });
};
var ZodNaN = class extends ZodType {
  _parse(input) {
    const parsedType = this._getType(input);
    if (parsedType !== ZodParsedType.nan) {
      const ctx = this._getOrReturnCtx(input);
      addIssueToContext(ctx, {
        code: ZodIssueCode.invalid_type,
        expected: ZodParsedType.nan,
        received: ctx.parsedType
      });
      return INVALID;
    }
    return { status: "valid", value: input.data };
  }
};
__name(ZodNaN, "ZodNaN");
ZodNaN.create = (params) => {
  return new ZodNaN({
    typeName: ZodFirstPartyTypeKind.ZodNaN,
    ...processCreateParams(params)
  });
};
var BRAND = Symbol("zod_brand");
var ZodBranded = class extends ZodType {
  _parse(input) {
    const { ctx } = this._processInputParams(input);
    const data = ctx.data;
    return this._def.type._parse({
      data,
      path: ctx.path,
      parent: ctx
    });
  }
  unwrap() {
    return this._def.type;
  }
};
__name(ZodBranded, "ZodBranded");
var ZodPipeline = class extends ZodType {
  _parse(input) {
    const { status, ctx } = this._processInputParams(input);
    if (ctx.common.async) {
      const handleAsync = /* @__PURE__ */ __name(async () => {
        const inResult = await this._def.in._parseAsync({
          data: ctx.data,
          path: ctx.path,
          parent: ctx
        });
        if (inResult.status === "aborted")
          return INVALID;
        if (inResult.status === "dirty") {
          status.dirty();
          return DIRTY(inResult.value);
        } else {
          return this._def.out._parseAsync({
            data: inResult.value,
            path: ctx.path,
            parent: ctx
          });
        }
      }, "handleAsync");
      return handleAsync();
    } else {
      const inResult = this._def.in._parseSync({
        data: ctx.data,
        path: ctx.path,
        parent: ctx
      });
      if (inResult.status === "aborted")
        return INVALID;
      if (inResult.status === "dirty") {
        status.dirty();
        return {
          status: "dirty",
          value: inResult.value
        };
      } else {
        return this._def.out._parseSync({
          data: inResult.value,
          path: ctx.path,
          parent: ctx
        });
      }
    }
  }
  static create(a, b) {
    return new ZodPipeline({
      in: a,
      out: b,
      typeName: ZodFirstPartyTypeKind.ZodPipeline
    });
  }
};
__name(ZodPipeline, "ZodPipeline");
var ZodReadonly = class extends ZodType {
  _parse(input) {
    const result = this._def.innerType._parse(input);
    const freeze = /* @__PURE__ */ __name((data) => {
      if (isValid(data)) {
        data.value = Object.freeze(data.value);
      }
      return data;
    }, "freeze");
    return isAsync(result) ? result.then((data) => freeze(data)) : freeze(result);
  }
  unwrap() {
    return this._def.innerType;
  }
};
__name(ZodReadonly, "ZodReadonly");
ZodReadonly.create = (type, params) => {
  return new ZodReadonly({
    innerType: type,
    typeName: ZodFirstPartyTypeKind.ZodReadonly,
    ...processCreateParams(params)
  });
};
function cleanParams(params, data) {
  const p = typeof params === "function" ? params(data) : typeof params === "string" ? { message: params } : params;
  const p2 = typeof p === "string" ? { message: p } : p;
  return p2;
}
__name(cleanParams, "cleanParams");
function custom(check, _params = {}, fatal) {
  if (check)
    return ZodAny.create().superRefine((data, ctx) => {
      const r = check(data);
      if (r instanceof Promise) {
        return r.then((r2) => {
          if (!r2) {
            const params = cleanParams(_params, data);
            const _fatal = params.fatal ?? fatal ?? true;
            ctx.addIssue({ code: "custom", ...params, fatal: _fatal });
          }
        });
      }
      if (!r) {
        const params = cleanParams(_params, data);
        const _fatal = params.fatal ?? fatal ?? true;
        ctx.addIssue({ code: "custom", ...params, fatal: _fatal });
      }
      return;
    });
  return ZodAny.create();
}
__name(custom, "custom");
var late = {
  object: ZodObject.lazycreate
};
var ZodFirstPartyTypeKind;
(function(ZodFirstPartyTypeKind2) {
  ZodFirstPartyTypeKind2["ZodString"] = "ZodString";
  ZodFirstPartyTypeKind2["ZodNumber"] = "ZodNumber";
  ZodFirstPartyTypeKind2["ZodNaN"] = "ZodNaN";
  ZodFirstPartyTypeKind2["ZodBigInt"] = "ZodBigInt";
  ZodFirstPartyTypeKind2["ZodBoolean"] = "ZodBoolean";
  ZodFirstPartyTypeKind2["ZodDate"] = "ZodDate";
  ZodFirstPartyTypeKind2["ZodSymbol"] = "ZodSymbol";
  ZodFirstPartyTypeKind2["ZodUndefined"] = "ZodUndefined";
  ZodFirstPartyTypeKind2["ZodNull"] = "ZodNull";
  ZodFirstPartyTypeKind2["ZodAny"] = "ZodAny";
  ZodFirstPartyTypeKind2["ZodUnknown"] = "ZodUnknown";
  ZodFirstPartyTypeKind2["ZodNever"] = "ZodNever";
  ZodFirstPartyTypeKind2["ZodVoid"] = "ZodVoid";
  ZodFirstPartyTypeKind2["ZodArray"] = "ZodArray";
  ZodFirstPartyTypeKind2["ZodObject"] = "ZodObject";
  ZodFirstPartyTypeKind2["ZodUnion"] = "ZodUnion";
  ZodFirstPartyTypeKind2["ZodDiscriminatedUnion"] = "ZodDiscriminatedUnion";
  ZodFirstPartyTypeKind2["ZodIntersection"] = "ZodIntersection";
  ZodFirstPartyTypeKind2["ZodTuple"] = "ZodTuple";
  ZodFirstPartyTypeKind2["ZodRecord"] = "ZodRecord";
  ZodFirstPartyTypeKind2["ZodMap"] = "ZodMap";
  ZodFirstPartyTypeKind2["ZodSet"] = "ZodSet";
  ZodFirstPartyTypeKind2["ZodFunction"] = "ZodFunction";
  ZodFirstPartyTypeKind2["ZodLazy"] = "ZodLazy";
  ZodFirstPartyTypeKind2["ZodLiteral"] = "ZodLiteral";
  ZodFirstPartyTypeKind2["ZodEnum"] = "ZodEnum";
  ZodFirstPartyTypeKind2["ZodEffects"] = "ZodEffects";
  ZodFirstPartyTypeKind2["ZodNativeEnum"] = "ZodNativeEnum";
  ZodFirstPartyTypeKind2["ZodOptional"] = "ZodOptional";
  ZodFirstPartyTypeKind2["ZodNullable"] = "ZodNullable";
  ZodFirstPartyTypeKind2["ZodDefault"] = "ZodDefault";
  ZodFirstPartyTypeKind2["ZodCatch"] = "ZodCatch";
  ZodFirstPartyTypeKind2["ZodPromise"] = "ZodPromise";
  ZodFirstPartyTypeKind2["ZodBranded"] = "ZodBranded";
  ZodFirstPartyTypeKind2["ZodPipeline"] = "ZodPipeline";
  ZodFirstPartyTypeKind2["ZodReadonly"] = "ZodReadonly";
})(ZodFirstPartyTypeKind || (ZodFirstPartyTypeKind = {}));
var instanceOfType = /* @__PURE__ */ __name((cls, params = {
  message: `Input not instance of ${cls.name}`
}) => custom((data) => data instanceof cls, params), "instanceOfType");
var stringType = ZodString.create;
var numberType = ZodNumber.create;
var nanType = ZodNaN.create;
var bigIntType = ZodBigInt.create;
var booleanType = ZodBoolean.create;
var dateType = ZodDate.create;
var symbolType = ZodSymbol.create;
var undefinedType = ZodUndefined.create;
var nullType = ZodNull.create;
var anyType = ZodAny.create;
var unknownType = ZodUnknown.create;
var neverType = ZodNever.create;
var voidType = ZodVoid.create;
var arrayType = ZodArray.create;
var objectType = ZodObject.create;
var strictObjectType = ZodObject.strictCreate;
var unionType = ZodUnion.create;
var discriminatedUnionType = ZodDiscriminatedUnion.create;
var intersectionType = ZodIntersection.create;
var tupleType = ZodTuple.create;
var recordType = ZodRecord.create;
var mapType = ZodMap.create;
var setType = ZodSet.create;
var functionType = ZodFunction.create;
var lazyType = ZodLazy.create;
var literalType = ZodLiteral.create;
var enumType = ZodEnum.create;
var nativeEnumType = ZodNativeEnum.create;
var promiseType = ZodPromise.create;
var effectsType = ZodEffects.create;
var optionalType = ZodOptional.create;
var nullableType = ZodNullable.create;
var preprocessType = ZodEffects.createWithPreprocess;
var pipelineType = ZodPipeline.create;
var ostring = /* @__PURE__ */ __name(() => stringType().optional(), "ostring");
var onumber = /* @__PURE__ */ __name(() => numberType().optional(), "onumber");
var oboolean = /* @__PURE__ */ __name(() => booleanType().optional(), "oboolean");
var coerce = {
  string: (arg) => ZodString.create({ ...arg, coerce: true }),
  number: (arg) => ZodNumber.create({ ...arg, coerce: true }),
  boolean: (arg) => ZodBoolean.create({
    ...arg,
    coerce: true
  }),
  bigint: (arg) => ZodBigInt.create({ ...arg, coerce: true }),
  date: (arg) => ZodDate.create({ ...arg, coerce: true })
};
var NEVER = INVALID;

// node_modules/teenybase/dist/worker/util/error.js
var ProcessError = class extends HTTPException {
  message;
  input;
  get data() {
    return {
      error: this.cause?.message ? this.cause.message : this.cause,
      ...this.input
    };
  }
  constructor(message, code = 400, input, cause) {
    super(code, { message, cause });
    this.message = message;
    this.input = input;
  }
};
__name(ProcessError, "ProcessError");
var D1Error = class extends Error {
  message;
  errorMessage;
  cause;
  input;
  get data() {
    return {
      error: this.errorMessage,
      // cause: (this.cause as any)?.message ? (this.cause as any).message : this.cause,
      input: this.input,
      ...this._data
    };
  }
  _data;
  set data(d) {
    this._data = d;
  }
  constructor(message, errorMessage, cause, input) {
    super(message);
    this.message = message;
    this.errorMessage = errorMessage;
    this.cause = cause;
    this.input = input;
  }
};
__name(D1Error, "D1Error");
var HTTPError = class extends HTTPException {
  isHTTPException = true;
};
__name(HTTPError, "HTTPError");

// node_modules/teenybase/dist/worker/util/honoErrorHandler.js
function ddbErrorHandler($db, err, respondWithErrors, respondWithQueryLog) {
  const isHTTP = err instanceof HTTPError || err instanceof HTTPException;
  const isD1Error = err instanceof D1Error;
  const isZodError = err instanceof ZodError;
  const status = isHTTP ? err.status || 500 : isD1Error || isZodError ? 400 : 500;
  console.error(`Request Error: ${status}`);
  console.error(err, err.status, `http: ${isHTTP}`);
  return {
    code: status,
    message: isZodError ? "Validation Error" : isHTTP || respondWithErrors || isD1Error ? err.message : "Internal server error",
    data: {
      ...isZodError ? err.format() : null,
      ...respondWithErrors ? err.data : {}
    },
    issues: respondWithErrors && isZodError ? err.issues : void 0,
    queries: respondWithQueryLog ? $db?.queryLog : void 0
  };
}
__name(ddbErrorHandler, "ddbErrorHandler");
function honoErrorHandler(err, c) {
  if ((err instanceof HTTPError || err instanceof HTTPException) && err.res) {
    return err.res;
  }
  const res = ddbErrorHandler(c.get("$db"), err, c.env?.RESPOND_WITH_ERRORS, c.env?.RESPOND_WITH_QUERY_LOG);
  return c.json(res, {
    status: res.code,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Max-Age": "600"
    }
  });
}
__name(honoErrorHandler, "honoErrorHandler");

// node_modules/hono/dist/utils/color.js
function getColorEnabled() {
  const { process, Deno } = globalThis;
  const isNoColor = typeof Deno?.noColor === "boolean" ? Deno.noColor : process !== void 0 ? "NO_COLOR" in process?.env : false;
  return !isNoColor;
}
__name(getColorEnabled, "getColorEnabled");

// node_modules/hono/dist/middleware/logger/index.js
var humanize = /* @__PURE__ */ __name((times) => {
  const [delimiter2, separator] = [",", "."];
  const orderTimes = times.map((v) => v.replace(/(\d)(?=(\d\d\d)+(?!\d))/g, "$1" + delimiter2));
  return orderTimes.join(separator);
}, "humanize");
var time3 = /* @__PURE__ */ __name((start) => {
  const delta = Date.now() - start;
  return humanize([delta < 1e3 ? delta + "ms" : Math.round(delta / 1e3) + "s"]);
}, "time");
var colorStatus = /* @__PURE__ */ __name((status) => {
  const colorEnabled = getColorEnabled();
  if (colorEnabled) {
    switch (status / 100 | 0) {
      case 5:
        return `\x1B[31m${status}\x1B[0m`;
      case 4:
        return `\x1B[33m${status}\x1B[0m`;
      case 3:
        return `\x1B[36m${status}\x1B[0m`;
      case 2:
        return `\x1B[32m${status}\x1B[0m`;
    }
  }
  return `${status}`;
}, "colorStatus");
function log3(fn, prefix, method, path, status = 0, elapsed) {
  const out = prefix === "<--" ? `${prefix} ${method} ${path}` : `${prefix} ${method} ${path} ${colorStatus(status)} ${elapsed}`;
  fn(out);
}
__name(log3, "log");
var logger = /* @__PURE__ */ __name((fn = console.log) => {
  return /* @__PURE__ */ __name(async function logger2(c, next) {
    const { method } = c.req;
    const path = getPath(c.req.raw);
    log3(fn, "<--", method, path);
    const start = Date.now();
    await next();
    log3(fn, "-->", method, path, c.res.status, time3(start));
  }, "logger2");
}, "logger");

// node_modules/teenybase/dist/worker/honoApp.js
function teenyHono(createDb, app2, options = { logger: true, cors: true }, onRequest, beforeRoute) {
  app2 = app2 ?? new Hono2();
  app2.onError(honoErrorHandler);
  options.logger && app2.use(logger());
  options.cors && app2.use("*", async (c, next) => {
    const corsMiddlewareHandler = cors({
      origin: "*",
      allowHeaders: ["*"],
      allowMethods: ["POST", "GET", "OPTIONS", "PUT", "DELETE", "PATCH"],
      exposeHeaders: ["*"],
      maxAge: 600,
      credentials: true
    });
    return corsMiddlewareHandler(c, next);
  });
  app2.use("*", async (c, next) => {
    c.set("$db", await createDb(c));
    if (onRequest) {
      const res = await onRequest(c);
      if (res)
        return res;
    }
    return next();
  });
  app2.use("/api/*", async (c, next) => {
    if (beforeRoute) {
      const res2 = await beforeRoute(c);
      if (res2)
        return res2;
    }
    const base2 = c.req.routePath.replace("/api/*", "");
    const path = c.req.path.replace(base2, "");
    let res = await c.get("$db").route(path);
    if (!res)
      res = await next();
    return res;
  });
  return app2;
}
__name(teenyHono, "teenyHono");

// node_modules/teenybase/dist/worker/tableExtension.js
var TableExtension = class {
  data;
  table;
  jc;
  get name() {
    return this.data.name;
  }
  constructor(data, table3, jc) {
    this.data = data;
    this.table = table3;
    this.jc = jc;
  }
  routes = [];
};
__name(TableExtension, "TableExtension");

// node_modules/jsep/dist/jsep.js
var Hooks = class {
  /**
   * @callback HookCallback
   * @this {*|Jsep} this
   * @param {Jsep} env
   * @returns: void
   */
  /**
   * Adds the given callback to the list of callbacks for the given hook.
   *
   * The callback will be invoked when the hook it is registered for is run.
   *
   * One callback function can be registered to multiple hooks and the same hook multiple times.
   *
   * @param {string|object} name The name of the hook, or an object of callbacks keyed by name
   * @param {HookCallback|boolean} callback The callback function which is given environment variables.
   * @param {?boolean} [first=false] Will add the hook to the top of the list (defaults to the bottom)
   * @public
   */
  add(name, callback, first) {
    if (typeof arguments[0] != "string") {
      for (let name2 in arguments[0]) {
        this.add(name2, arguments[0][name2], arguments[1]);
      }
    } else {
      (Array.isArray(name) ? name : [name]).forEach(function(name2) {
        this[name2] = this[name2] || [];
        if (callback) {
          this[name2][first ? "unshift" : "push"](callback);
        }
      }, this);
    }
  }
  /**
   * Runs a hook invoking all registered callbacks with the given environment variables.
   *
   * Callbacks will be invoked synchronously and in the order in which they were registered.
   *
   * @param {string} name The name of the hook.
   * @param {Object<string, any>} env The environment variables of the hook passed to all callbacks registered.
   * @public
   */
  run(name, env2) {
    this[name] = this[name] || [];
    this[name].forEach(function(callback) {
      callback.call(env2 && env2.context ? env2.context : env2, env2);
    });
  }
};
__name(Hooks, "Hooks");
var Plugins = class {
  constructor(jsep2) {
    this.jsep = jsep2;
    this.registered = {};
  }
  /**
   * @callback PluginSetup
   * @this {Jsep} jsep
   * @returns: void
   */
  /**
   * Adds the given plugin(s) to the registry
   *
   * @param {object} plugins
   * @param {string} plugins.name The name of the plugin
   * @param {PluginSetup} plugins.init The init function
   * @public
   */
  register(...plugins) {
    plugins.forEach((plugin) => {
      if (typeof plugin !== "object" || !plugin.name || !plugin.init) {
        throw new Error("Invalid JSEP plugin format");
      }
      if (this.registered[plugin.name]) {
        return;
      }
      plugin.init(this.jsep);
      this.registered[plugin.name] = plugin;
    });
  }
};
__name(Plugins, "Plugins");
var Jsep = class {
  /**
   * @returns {string}
   */
  static get version() {
    return "1.4.0";
  }
  /**
   * @returns {string}
   */
  static toString() {
    return "JavaScript Expression Parser (JSEP) v" + Jsep.version;
  }
  // ==================== CONFIG ================================
  /**
   * @method addUnaryOp
   * @param {string} op_name The name of the unary op to add
   * @returns {Jsep}
   */
  static addUnaryOp(op_name) {
    Jsep.max_unop_len = Math.max(op_name.length, Jsep.max_unop_len);
    Jsep.unary_ops[op_name] = 1;
    return Jsep;
  }
  /**
   * @method jsep.addBinaryOp
   * @param {string} op_name The name of the binary op to add
   * @param {number} precedence The precedence of the binary op (can be a float). Higher number = higher precedence
   * @param {boolean} [isRightAssociative=false] whether operator is right-associative
   * @returns {Jsep}
   */
  static addBinaryOp(op_name, precedence, isRightAssociative) {
    Jsep.max_binop_len = Math.max(op_name.length, Jsep.max_binop_len);
    Jsep.binary_ops[op_name] = precedence;
    if (isRightAssociative) {
      Jsep.right_associative.add(op_name);
    } else {
      Jsep.right_associative.delete(op_name);
    }
    return Jsep;
  }
  /**
   * @method addIdentifierChar
   * @param {string} char The additional character to treat as a valid part of an identifier
   * @returns {Jsep}
   */
  static addIdentifierChar(char) {
    Jsep.additional_identifier_chars.add(char);
    return Jsep;
  }
  /**
   * @method addLiteral
   * @param {string} literal_name The name of the literal to add
   * @param {*} literal_value The value of the literal
   * @returns {Jsep}
   */
  static addLiteral(literal_name, literal_value) {
    Jsep.literals[literal_name] = literal_value;
    return Jsep;
  }
  /**
   * @method removeUnaryOp
   * @param {string} op_name The name of the unary op to remove
   * @returns {Jsep}
   */
  static removeUnaryOp(op_name) {
    delete Jsep.unary_ops[op_name];
    if (op_name.length === Jsep.max_unop_len) {
      Jsep.max_unop_len = Jsep.getMaxKeyLen(Jsep.unary_ops);
    }
    return Jsep;
  }
  /**
   * @method removeAllUnaryOps
   * @returns {Jsep}
   */
  static removeAllUnaryOps() {
    Jsep.unary_ops = {};
    Jsep.max_unop_len = 0;
    return Jsep;
  }
  /**
   * @method removeIdentifierChar
   * @param {string} char The additional character to stop treating as a valid part of an identifier
   * @returns {Jsep}
   */
  static removeIdentifierChar(char) {
    Jsep.additional_identifier_chars.delete(char);
    return Jsep;
  }
  /**
   * @method removeBinaryOp
   * @param {string} op_name The name of the binary op to remove
   * @returns {Jsep}
   */
  static removeBinaryOp(op_name) {
    delete Jsep.binary_ops[op_name];
    if (op_name.length === Jsep.max_binop_len) {
      Jsep.max_binop_len = Jsep.getMaxKeyLen(Jsep.binary_ops);
    }
    Jsep.right_associative.delete(op_name);
    return Jsep;
  }
  /**
   * @method removeAllBinaryOps
   * @returns {Jsep}
   */
  static removeAllBinaryOps() {
    Jsep.binary_ops = {};
    Jsep.max_binop_len = 0;
    return Jsep;
  }
  /**
   * @method removeLiteral
   * @param {string} literal_name The name of the literal to remove
   * @returns {Jsep}
   */
  static removeLiteral(literal_name) {
    delete Jsep.literals[literal_name];
    return Jsep;
  }
  /**
   * @method removeAllLiterals
   * @returns {Jsep}
   */
  static removeAllLiterals() {
    Jsep.literals = {};
    return Jsep;
  }
  // ==================== END CONFIG ============================
  /**
   * @returns {string}
   */
  get char() {
    return this.expr.charAt(this.index);
  }
  /**
   * @returns {number}
   */
  get code() {
    return this.expr.charCodeAt(this.index);
  }
  /**
   * @param {string} expr a string with the passed in express
   * @returns Jsep
   */
  constructor(expr) {
    this.expr = expr;
    this.index = 0;
  }
  /**
   * static top-level parser
   * @returns {jsep.Expression}
   */
  static parse(expr) {
    return new Jsep(expr).parse();
  }
  /**
   * Get the longest key length of any object
   * @param {object} obj
   * @returns {number}
   */
  static getMaxKeyLen(obj) {
    return Math.max(0, ...Object.keys(obj).map((k) => k.length));
  }
  /**
   * `ch` is a character code in the next three functions
   * @param {number} ch
   * @returns {boolean}
   */
  static isDecimalDigit(ch) {
    return ch >= 48 && ch <= 57;
  }
  /**
   * Returns the precedence of a binary operator or `0` if it isn't a binary operator. Can be float.
   * @param {string} op_val
   * @returns {number}
   */
  static binaryPrecedence(op_val) {
    return Jsep.binary_ops[op_val] || 0;
  }
  /**
   * Looks for start of identifier
   * @param {number} ch
   * @returns {boolean}
   */
  static isIdentifierStart(ch) {
    return ch >= 65 && ch <= 90 || // A...Z
    ch >= 97 && ch <= 122 || // a...z
    ch >= 128 && !Jsep.binary_ops[String.fromCharCode(ch)] || // any non-ASCII that is not an operator
    Jsep.additional_identifier_chars.has(String.fromCharCode(ch));
  }
  /**
   * @param {number} ch
   * @returns {boolean}
   */
  static isIdentifierPart(ch) {
    return Jsep.isIdentifierStart(ch) || Jsep.isDecimalDigit(ch);
  }
  /**
   * throw error at index of the expression
   * @param {string} message
   * @throws
   */
  throwError(message) {
    const error4 = new Error(message + " at character " + this.index);
    error4.index = this.index;
    error4.description = message;
    throw error4;
  }
  /**
   * Run a given hook
   * @param {string} name
   * @param {jsep.Expression|false} [node]
   * @returns {?jsep.Expression}
   */
  runHook(name, node) {
    if (Jsep.hooks[name]) {
      const env2 = { context: this, node };
      Jsep.hooks.run(name, env2);
      return env2.node;
    }
    return node;
  }
  /**
   * Runs a given hook until one returns a node
   * @param {string} name
   * @returns {?jsep.Expression}
   */
  searchHook(name) {
    if (Jsep.hooks[name]) {
      const env2 = { context: this };
      Jsep.hooks[name].find(function(callback) {
        callback.call(env2.context, env2);
        return env2.node;
      });
      return env2.node;
    }
  }
  /**
   * Push `index` up to the next non-space character
   */
  gobbleSpaces() {
    let ch = this.code;
    while (ch === Jsep.SPACE_CODE || ch === Jsep.TAB_CODE || ch === Jsep.LF_CODE || ch === Jsep.CR_CODE) {
      ch = this.expr.charCodeAt(++this.index);
    }
    this.runHook("gobble-spaces");
  }
  /**
   * Top-level method to parse all expressions and returns compound or single node
   * @returns {jsep.Expression}
   */
  parse() {
    this.runHook("before-all");
    const nodes = this.gobbleExpressions();
    const node = nodes.length === 1 ? nodes[0] : {
      type: Jsep.COMPOUND,
      body: nodes
    };
    return this.runHook("after-all", node);
  }
  /**
   * top-level parser (but can be reused within as well)
   * @param {number} [untilICode]
   * @returns {jsep.Expression[]}
   */
  gobbleExpressions(untilICode) {
    let nodes = [], ch_i, node;
    while (this.index < this.expr.length) {
      ch_i = this.code;
      if (ch_i === Jsep.SEMCOL_CODE || ch_i === Jsep.COMMA_CODE) {
        this.index++;
      } else {
        if (node = this.gobbleExpression()) {
          nodes.push(node);
        } else if (this.index < this.expr.length) {
          if (ch_i === untilICode) {
            break;
          }
          this.throwError('Unexpected "' + this.char + '"');
        }
      }
    }
    return nodes;
  }
  /**
   * The main parsing function.
   * @returns {?jsep.Expression}
   */
  gobbleExpression() {
    const node = this.searchHook("gobble-expression") || this.gobbleBinaryExpression();
    this.gobbleSpaces();
    return this.runHook("after-expression", node);
  }
  /**
   * Search for the operation portion of the string (e.g. `+`, `===`)
   * Start by taking the longest possible binary operations (3 characters: `===`, `!==`, `>>>`)
   * and move down from 3 to 2 to 1 character until a matching binary operation is found
   * then, return that binary operation
   * @returns {string|boolean}
   */
  gobbleBinaryOp() {
    this.gobbleSpaces();
    let to_check = this.expr.substr(this.index, Jsep.max_binop_len);
    let tc_len = to_check.length;
    while (tc_len > 0) {
      if (Jsep.binary_ops.hasOwnProperty(to_check) && (!Jsep.isIdentifierStart(this.code) || this.index + to_check.length < this.expr.length && !Jsep.isIdentifierPart(this.expr.charCodeAt(this.index + to_check.length)))) {
        this.index += tc_len;
        return to_check;
      }
      to_check = to_check.substr(0, --tc_len);
    }
    return false;
  }
  /**
   * This function is responsible for gobbling an individual expression,
   * e.g. `1`, `1+2`, `a+(b*2)-Math.sqrt(2)`
   * @returns {?jsep.BinaryExpression}
   */
  gobbleBinaryExpression() {
    let node, biop, prec, stack, biop_info, left, right, i, cur_biop;
    left = this.gobbleToken();
    if (!left) {
      return left;
    }
    biop = this.gobbleBinaryOp();
    if (!biop) {
      return left;
    }
    biop_info = { value: biop, prec: Jsep.binaryPrecedence(biop), right_a: Jsep.right_associative.has(biop) };
    right = this.gobbleToken();
    if (!right) {
      this.throwError("Expected expression after " + biop);
    }
    stack = [left, biop_info, right];
    while (biop = this.gobbleBinaryOp()) {
      prec = Jsep.binaryPrecedence(biop);
      if (prec === 0) {
        this.index -= biop.length;
        break;
      }
      biop_info = { value: biop, prec, right_a: Jsep.right_associative.has(biop) };
      cur_biop = biop;
      const comparePrev = /* @__PURE__ */ __name((prev) => biop_info.right_a && prev.right_a ? prec > prev.prec : prec <= prev.prec, "comparePrev");
      while (stack.length > 2 && comparePrev(stack[stack.length - 2])) {
        right = stack.pop();
        biop = stack.pop().value;
        left = stack.pop();
        node = {
          type: Jsep.BINARY_EXP,
          operator: biop,
          left,
          right
        };
        stack.push(node);
      }
      node = this.gobbleToken();
      if (!node) {
        this.throwError("Expected expression after " + cur_biop);
      }
      stack.push(biop_info, node);
    }
    i = stack.length - 1;
    node = stack[i];
    while (i > 1) {
      node = {
        type: Jsep.BINARY_EXP,
        operator: stack[i - 1].value,
        left: stack[i - 2],
        right: node
      };
      i -= 2;
    }
    return node;
  }
  /**
   * An individual part of a binary expression:
   * e.g. `foo.bar(baz)`, `1`, `"abc"`, `(a % 2)` (because it's in parenthesis)
   * @returns {boolean|jsep.Expression}
   */
  gobbleToken() {
    let ch, to_check, tc_len, node;
    this.gobbleSpaces();
    node = this.searchHook("gobble-token");
    if (node) {
      return this.runHook("after-token", node);
    }
    ch = this.code;
    if (Jsep.isDecimalDigit(ch) || ch === Jsep.PERIOD_CODE) {
      return this.gobbleNumericLiteral();
    }
    if (ch === Jsep.SQUOTE_CODE || ch === Jsep.DQUOTE_CODE) {
      node = this.gobbleStringLiteral();
    } else if (ch === Jsep.OBRACK_CODE) {
      node = this.gobbleArray();
    } else {
      to_check = this.expr.substr(this.index, Jsep.max_unop_len);
      tc_len = to_check.length;
      while (tc_len > 0) {
        if (Jsep.unary_ops.hasOwnProperty(to_check) && (!Jsep.isIdentifierStart(this.code) || this.index + to_check.length < this.expr.length && !Jsep.isIdentifierPart(this.expr.charCodeAt(this.index + to_check.length)))) {
          this.index += tc_len;
          const argument = this.gobbleToken();
          if (!argument) {
            this.throwError("missing unaryOp argument");
          }
          return this.runHook("after-token", {
            type: Jsep.UNARY_EXP,
            operator: to_check,
            argument,
            prefix: true
          });
        }
        to_check = to_check.substr(0, --tc_len);
      }
      if (Jsep.isIdentifierStart(ch)) {
        node = this.gobbleIdentifier();
        if (Jsep.literals.hasOwnProperty(node.name)) {
          node = {
            type: Jsep.LITERAL,
            value: Jsep.literals[node.name],
            raw: node.name
          };
        } else if (node.name === Jsep.this_str) {
          node = { type: Jsep.THIS_EXP };
        }
      } else if (ch === Jsep.OPAREN_CODE) {
        node = this.gobbleGroup();
      }
    }
    if (!node) {
      return this.runHook("after-token", false);
    }
    node = this.gobbleTokenProperty(node);
    return this.runHook("after-token", node);
  }
  /**
   * Gobble properties of of identifiers/strings/arrays/groups.
   * e.g. `foo`, `bar.baz`, `foo['bar'].baz`
   * It also gobbles function calls:
   * e.g. `Math.acos(obj.angle)`
   * @param {jsep.Expression} node
   * @returns {jsep.Expression}
   */
  gobbleTokenProperty(node) {
    this.gobbleSpaces();
    let ch = this.code;
    while (ch === Jsep.PERIOD_CODE || ch === Jsep.OBRACK_CODE || ch === Jsep.OPAREN_CODE || ch === Jsep.QUMARK_CODE) {
      let optional;
      if (ch === Jsep.QUMARK_CODE) {
        if (this.expr.charCodeAt(this.index + 1) !== Jsep.PERIOD_CODE) {
          break;
        }
        optional = true;
        this.index += 2;
        this.gobbleSpaces();
        ch = this.code;
      }
      this.index++;
      if (ch === Jsep.OBRACK_CODE) {
        node = {
          type: Jsep.MEMBER_EXP,
          computed: true,
          object: node,
          property: this.gobbleExpression()
        };
        if (!node.property) {
          this.throwError('Unexpected "' + this.char + '"');
        }
        this.gobbleSpaces();
        ch = this.code;
        if (ch !== Jsep.CBRACK_CODE) {
          this.throwError("Unclosed [");
        }
        this.index++;
      } else if (ch === Jsep.OPAREN_CODE) {
        node = {
          type: Jsep.CALL_EXP,
          "arguments": this.gobbleArguments(Jsep.CPAREN_CODE),
          callee: node
        };
      } else if (ch === Jsep.PERIOD_CODE || optional) {
        if (optional) {
          this.index--;
        }
        this.gobbleSpaces();
        node = {
          type: Jsep.MEMBER_EXP,
          computed: false,
          object: node,
          property: this.gobbleIdentifier()
        };
      }
      if (optional) {
        node.optional = true;
      }
      this.gobbleSpaces();
      ch = this.code;
    }
    return node;
  }
  /**
   * Parse simple numeric literals: `12`, `3.4`, `.5`. Do this by using a string to
   * keep track of everything in the numeric literal and then calling `parseFloat` on that string
   * @returns {jsep.Literal}
   */
  gobbleNumericLiteral() {
    let number = "", ch, chCode;
    while (Jsep.isDecimalDigit(this.code)) {
      number += this.expr.charAt(this.index++);
    }
    if (this.code === Jsep.PERIOD_CODE) {
      number += this.expr.charAt(this.index++);
      while (Jsep.isDecimalDigit(this.code)) {
        number += this.expr.charAt(this.index++);
      }
    }
    ch = this.char;
    if (ch === "e" || ch === "E") {
      number += this.expr.charAt(this.index++);
      ch = this.char;
      if (ch === "+" || ch === "-") {
        number += this.expr.charAt(this.index++);
      }
      while (Jsep.isDecimalDigit(this.code)) {
        number += this.expr.charAt(this.index++);
      }
      if (!Jsep.isDecimalDigit(this.expr.charCodeAt(this.index - 1))) {
        this.throwError("Expected exponent (" + number + this.char + ")");
      }
    }
    chCode = this.code;
    if (Jsep.isIdentifierStart(chCode)) {
      this.throwError("Variable names cannot start with a number (" + number + this.char + ")");
    } else if (chCode === Jsep.PERIOD_CODE || number.length === 1 && number.charCodeAt(0) === Jsep.PERIOD_CODE) {
      this.throwError("Unexpected period");
    }
    return {
      type: Jsep.LITERAL,
      value: parseFloat(number),
      raw: number
    };
  }
  /**
   * Parses a string literal, staring with single or double quotes with basic support for escape codes
   * e.g. `"hello world"`, `'this is\nJSEP'`
   * @returns {jsep.Literal}
   */
  gobbleStringLiteral() {
    let str = "";
    const startIndex = this.index;
    const quote = this.expr.charAt(this.index++);
    let closed = false;
    while (this.index < this.expr.length) {
      let ch = this.expr.charAt(this.index++);
      if (ch === quote) {
        closed = true;
        break;
      } else if (ch === "\\") {
        ch = this.expr.charAt(this.index++);
        switch (ch) {
          case "n":
            str += "\n";
            break;
          case "r":
            str += "\r";
            break;
          case "t":
            str += "	";
            break;
          case "b":
            str += "\b";
            break;
          case "f":
            str += "\f";
            break;
          case "v":
            str += "\v";
            break;
          default:
            str += ch;
        }
      } else {
        str += ch;
      }
    }
    if (!closed) {
      this.throwError('Unclosed quote after "' + str + '"');
    }
    return {
      type: Jsep.LITERAL,
      value: str,
      raw: this.expr.substring(startIndex, this.index)
    };
  }
  /**
   * Gobbles only identifiers
   * e.g.: `foo`, `_value`, `$x1`
   * Also, this function checks if that identifier is a literal:
   * (e.g. `true`, `false`, `null`) or `this`
   * @returns {jsep.Identifier}
   */
  gobbleIdentifier() {
    let ch = this.code, start = this.index;
    if (Jsep.isIdentifierStart(ch)) {
      this.index++;
    } else {
      this.throwError("Unexpected " + this.char);
    }
    while (this.index < this.expr.length) {
      ch = this.code;
      if (Jsep.isIdentifierPart(ch)) {
        this.index++;
      } else {
        break;
      }
    }
    return {
      type: Jsep.IDENTIFIER,
      name: this.expr.slice(start, this.index)
    };
  }
  /**
   * Gobbles a list of arguments within the context of a function call
   * or array literal. This function also assumes that the opening character
   * `(` or `[` has already been gobbled, and gobbles expressions and commas
   * until the terminator character `)` or `]` is encountered.
   * e.g. `foo(bar, baz)`, `my_func()`, or `[bar, baz]`
   * @param {number} termination
   * @returns {jsep.Expression[]}
   */
  gobbleArguments(termination) {
    const args = [];
    let closed = false;
    let separator_count = 0;
    while (this.index < this.expr.length) {
      this.gobbleSpaces();
      let ch_i = this.code;
      if (ch_i === termination) {
        closed = true;
        this.index++;
        if (termination === Jsep.CPAREN_CODE && separator_count && separator_count >= args.length) {
          this.throwError("Unexpected token " + String.fromCharCode(termination));
        }
        break;
      } else if (ch_i === Jsep.COMMA_CODE) {
        this.index++;
        separator_count++;
        if (separator_count !== args.length) {
          if (termination === Jsep.CPAREN_CODE) {
            this.throwError("Unexpected token ,");
          } else if (termination === Jsep.CBRACK_CODE) {
            for (let arg = args.length; arg < separator_count; arg++) {
              args.push(null);
            }
          }
        }
      } else if (args.length !== separator_count && separator_count !== 0) {
        this.throwError("Expected comma");
      } else {
        const node = this.gobbleExpression();
        if (!node || node.type === Jsep.COMPOUND) {
          this.throwError("Expected comma");
        }
        args.push(node);
      }
    }
    if (!closed) {
      this.throwError("Expected " + String.fromCharCode(termination));
    }
    return args;
  }
  /**
   * Responsible for parsing a group of things within parentheses `()`
   * that have no identifier in front (so not a function call)
   * This function assumes that it needs to gobble the opening parenthesis
   * and then tries to gobble everything within that parenthesis, assuming
   * that the next thing it should see is the close parenthesis. If not,
   * then the expression probably doesn't have a `)`
   * @returns {boolean|jsep.Expression}
   */
  gobbleGroup() {
    this.index++;
    let nodes = this.gobbleExpressions(Jsep.CPAREN_CODE);
    if (this.code === Jsep.CPAREN_CODE) {
      this.index++;
      if (nodes.length === 1) {
        return nodes[0];
      } else if (!nodes.length) {
        return false;
      } else {
        return {
          type: Jsep.SEQUENCE_EXP,
          expressions: nodes
        };
      }
    } else {
      this.throwError("Unclosed (");
    }
  }
  /**
   * Responsible for parsing Array literals `[1, 2, 3]`
   * This function assumes that it needs to gobble the opening bracket
   * and then tries to gobble the expressions as arguments.
   * @returns {jsep.ArrayExpression}
   */
  gobbleArray() {
    this.index++;
    return {
      type: Jsep.ARRAY_EXP,
      elements: this.gobbleArguments(Jsep.CBRACK_CODE)
    };
  }
};
__name(Jsep, "Jsep");
var hooks = new Hooks();
Object.assign(Jsep, {
  hooks,
  plugins: new Plugins(Jsep),
  // Node Types
  // ----------
  // This is the full set of types that any JSEP node can be.
  // Store them here to save space when minified
  COMPOUND: "Compound",
  SEQUENCE_EXP: "SequenceExpression",
  IDENTIFIER: "Identifier",
  MEMBER_EXP: "MemberExpression",
  LITERAL: "Literal",
  THIS_EXP: "ThisExpression",
  CALL_EXP: "CallExpression",
  UNARY_EXP: "UnaryExpression",
  BINARY_EXP: "BinaryExpression",
  ARRAY_EXP: "ArrayExpression",
  TAB_CODE: 9,
  LF_CODE: 10,
  CR_CODE: 13,
  SPACE_CODE: 32,
  PERIOD_CODE: 46,
  // '.'
  COMMA_CODE: 44,
  // ','
  SQUOTE_CODE: 39,
  // single quote
  DQUOTE_CODE: 34,
  // double quotes
  OPAREN_CODE: 40,
  // (
  CPAREN_CODE: 41,
  // )
  OBRACK_CODE: 91,
  // [
  CBRACK_CODE: 93,
  // ]
  QUMARK_CODE: 63,
  // ?
  SEMCOL_CODE: 59,
  // ;
  COLON_CODE: 58,
  // :
  // Operations
  // ----------
  // Use a quickly-accessible map to store all of the unary operators
  // Values are set to `1` (it really doesn't matter)
  unary_ops: {
    "-": 1,
    "!": 1,
    "~": 1,
    "+": 1
  },
  // Also use a map for the binary operations but set their values to their
  // binary precedence for quick reference (higher number = higher precedence)
  // see [Order of operations](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Operator_Precedence)
  binary_ops: {
    "||": 1,
    "??": 1,
    "&&": 2,
    "|": 3,
    "^": 4,
    "&": 5,
    "==": 6,
    "!=": 6,
    "===": 6,
    "!==": 6,
    "<": 7,
    ">": 7,
    "<=": 7,
    ">=": 7,
    "<<": 8,
    ">>": 8,
    ">>>": 8,
    "+": 9,
    "-": 9,
    "*": 10,
    "/": 10,
    "%": 10,
    "**": 11
  },
  // sets specific binary_ops as right-associative
  right_associative: /* @__PURE__ */ new Set(["**"]),
  // Additional valid identifier chars, apart from a-z, A-Z and 0-9 (except on the starting char)
  additional_identifier_chars: /* @__PURE__ */ new Set(["$", "_"]),
  // Literals
  // ----------
  // Store the values to return for the various literals we may encounter
  literals: {
    "true": true,
    "false": false,
    "null": null
  },
  // Except for `this`, which is special. This could be changed to something like `'self'` as well
  this_str: "this"
});
Jsep.max_unop_len = Jsep.getMaxKeyLen(Jsep.unary_ops);
Jsep.max_binop_len = Jsep.getMaxKeyLen(Jsep.binary_ops);
var jsep = /* @__PURE__ */ __name((expr) => new Jsep(expr).parse(), "jsep");
var stdClassProps = Object.getOwnPropertyNames(/* @__PURE__ */ __name(class Test {
}, "Test"));
Object.getOwnPropertyNames(Jsep).filter((prop) => !stdClassProps.includes(prop) && jsep[prop] === void 0).forEach((m) => {
  jsep[m] = Jsep[m];
});
jsep.Jsep = Jsep;
var CONDITIONAL_EXP = "ConditionalExpression";
var ternary = {
  name: "ternary",
  init(jsep2) {
    jsep2.hooks.add("after-expression", /* @__PURE__ */ __name(function gobbleTernary(env2) {
      if (env2.node && this.code === jsep2.QUMARK_CODE) {
        this.index++;
        const test = env2.node;
        const consequent = this.gobbleExpression();
        if (!consequent) {
          this.throwError("Expected expression");
        }
        this.gobbleSpaces();
        if (this.code === jsep2.COLON_CODE) {
          this.index++;
          const alternate = this.gobbleExpression();
          if (!alternate) {
            this.throwError("Expected expression");
          }
          env2.node = {
            type: CONDITIONAL_EXP,
            test,
            consequent,
            alternate
          };
          if (test.operator && jsep2.binary_ops[test.operator] <= 0.9) {
            let newTest = test;
            while (newTest.right.operator && jsep2.binary_ops[newTest.right.operator] <= 0.9) {
              newTest = newTest.right;
            }
            env2.node.test = newTest.right;
            newTest.right = env2.node;
            env2.node = test;
          }
        } else {
          this.throwError("Expected :");
        }
      }
    }, "gobbleTernary"));
  }
};
jsep.plugins.register(ternary);

// node_modules/teenybase/dist/sql/build/query.js
function logSQLQuery(query) {
  if (typeof query.q !== "string")
    query.q = JSON.stringify(query.l || query.q);
  const params = query.p ? Object.entries(query.p) : null;
  let q = query.q.trim();
  if (params?.length) {
    for (const [k, val] of params) {
      let v = val;
      if (v !== null && (typeof v === "object" || Array.isArray(v))) {
        v = JSON.stringify(v);
      }
      q = q.replaceAll("{:" + k + "}", JSON.stringify(v));
    }
  }
  return q;
}
__name(logSQLQuery, "logSQLQuery");
var literalMapping = {
  0: "0",
  1: "1",
  true: "1",
  TRUE: "1",
  false: "0",
  FALSE: "0",
  null: "NULL",
  NULL: "NULL"
};
function literalToQuery(l, wrap = true) {
  let l1 = l.l;
  const isLiteral = l1 !== void 0;
  const q = l.q;
  if (!isLiteral && typeof l !== "string") {
    if (typeof q !== "string")
      throw new Error("Invalid query " + JSON.stringify(l));
    return {
      // q: (!q || (q[0] === '(' && q[q.length - 1] === ')')) ? q : `(${q})`, // Note - this is wrong, since it could be like `(a) OR (b)` which should also be escaped.
      q: !q || !wrap ? q : `(${q})`,
      // tag - brackets
      p: l.p,
      dependencies: l.dependencies,
      _readOnly: l._readOnly
    };
  }
  l1 = isLiteral && typeof l === "object" ? l1 : l;
  let lm = typeof l1 !== "object" ? literalMapping[l1] : void 0;
  if (lm !== void 0)
    return { q: lm, _readOnly: true };
  if (l1 === null || l1 === void 0)
    return { q: "NULL", _readOnly: true };
  const rnd = "f" + Math.random().toString(36).substring(7);
  return {
    q: "{:" + rnd + "}",
    p: { [rnd]: l1 },
    // todo is object check required? right now it's done in sqlQueryToD1Query
    _readOnly: true
  };
}
__name(literalToQuery, "literalToQuery");

// node_modules/teenybase/dist/security/random.js
function randomString(len) {
  const vals = crypto.getRandomValues(new Uint8Array(Math.ceil(len / 2)));
  return Array.from(vals).map((b) => b.toString(16).padStart(2, "0")).join("").substring(0, len);
}
__name(randomString, "randomString");
function uuidV4(b64 = false, nice = true) {
  const ho = /* @__PURE__ */ __name((n, p) => n.toString(16).padStart(p, "0"), "ho");
  const data = crypto.getRandomValues(new Uint8Array(16));
  data[6] = data[6] & 15 | 64;
  data[8] = data[8] & 63 | 128;
  if (b64) {
    if (nice)
      data[0] = data[0] & 127;
    return btoa(String.fromCharCode(...data)).replace(/\+/g, "-").replace(/\//g, "_").substring(0, 22);
  }
  const view = new DataView(data.buffer);
  return `${ho(view.getUint32(0), 8)}-${ho(view.getUint16(4), 4)}-${ho(view.getUint16(6), 4)}-${ho(view.getUint16(8), 4)}-${ho(view.getUint32(10), 8)}${ho(view.getUint16(14), 4)}`;
}
__name(uuidV4, "uuidV4");
function generateUid() {
  return uuidV4(true, true);
}
__name(generateUid, "generateUid");

// node_modules/teenybase/dist/sql/schema/tableQueries.js
function fts5TableName(name) {
  return `fts5_${name}_idx`;
}
__name(fts5TableName, "fts5TableName");

// node_modules/teenybase/dist/types/config/isTableFieldUnique.js
function isTableFieldUnique(f, t) {
  return f.unique || f.primary || !!t.indexes?.find((i) => {
    if (!i.unique)
      return false;
    const fields = Array.isArray(i.fields) ? i.fields : [i.fields];
    return !!fields.find((f1) => f1.split(" ")[0] === f.name);
  });
}
__name(isTableFieldUnique, "isTableFieldUnique");

// node_modules/teenybase/dist/types/zod/sqlSchemas.js
var sqlExprSchema = external_exports.string().max(1e3).regex(/^[a-zA-Z0-9_=\s():.*~%'"><!+\-&|@,\/\\${}]*$/, "Invalid expression");
var sqlExprSchemaRecord = external_exports.record(sqlExprSchema);
var sqlValSchema = external_exports.string().or(external_exports.number()).or(external_exports.boolean()).or(external_exports.null());
var sqlValSchemaFile = external_exports.boolean().or(external_exports.string().or(external_exports.number()).or(external_exports.null()).or(external_exports.instanceof(File)));
var sqlValSchemaRecord = external_exports.record(sqlValSchema);
var sqlValSchema2 = sqlValSchema.or(sqlValSchemaRecord);
var sqlValSchemaFile2 = external_exports.record(sqlValSchemaFile);
var sqlValSchemaFile3 = sqlValSchemaFile2.or(external_exports.array(sqlValSchemaFile2));
var sqlColListSchema = external_exports.string().regex(/^[a-zA-Z0-9_,\s]*$/).or(external_exports.literal("*"));
var sqlColListSchemaOrder = external_exports.string().regex(/^[a-zA-Z0-9_,\s+-]*$/);
var sqlColListSchema2 = external_exports.array(sqlColListSchema).or(sqlColListSchema);
var sqlColListSchemaOrder2 = external_exports.array(sqlColListSchemaOrder).or(sqlColListSchemaOrder);
var tableColumnNameSchema = external_exports.string().min(1).max(255).regex(/^[a-zA-Z_][a-zA-Z0-9_]*$/, "Table/Column name must start with a letter or underscore and can only contain letters, numbers and underscores");
var zSQLQuery = external_exports.object({
  q: external_exports.string(),
  p: external_exports.record(sqlValSchema2).optional()
});
var zSQLLiteral = external_exports.object({
  l: sqlValSchema2,
  key: external_exports.string().optional()
});
var zSQLQueryOrLiteral = zSQLQuery.or(zSQLLiteral);
var zOnConflict = external_exports.enum(["ABORT", "FAIL", "IGNORE", "REPLACE", "ROLLBACK"]);
var selectSchema = external_exports.object({
  where: sqlExprSchema.optional(),
  limit: external_exports.coerce.number().optional(),
  offset: external_exports.coerce.number().optional(),
  order: sqlColListSchemaOrder2.optional(),
  group: sqlColListSchema2.optional(),
  select: sqlExprSchema.or(external_exports.array(sqlExprSchema)).optional(),
  // todo rename to fields in api v2
  distinct: external_exports.coerce.boolean().optional()
  // join: joinObjSchema2.array().optional(),
  // having: z.string().regex(/^[a-zA-Z0-9_=\s\(\)\.\*]*$/).optional(),
  // selectOption: z.string().optional(),
});
var updateSchema = external_exports.object({
  or: zOnConflict.optional(),
  set: external_exports.record(sqlExprSchema).optional(),
  setValues: external_exports.record(sqlValSchema).optional(),
  where: sqlExprSchema,
  returning: external_exports.array(sqlExprSchema).or(sqlExprSchema).optional()
});
var insertSchema = external_exports.object({
  or: zOnConflict.optional(),
  values: sqlValSchemaRecord.or(external_exports.array(sqlValSchemaRecord)).optional(),
  expr: sqlExprSchemaRecord.or(external_exports.array(sqlExprSchemaRecord)).optional(),
  returning: external_exports.array(sqlExprSchema).or(sqlExprSchema).optional()
});
var deleteSchema = external_exports.object({
  where: sqlExprSchema,
  returning: external_exports.array(sqlExprSchema).or(sqlExprSchema).optional()
});
var tableDeleteSchema = deleteSchema;
var tableInsertSchema = insertSchema.omit({ values: true }).extend({ values: sqlValSchemaFile3 });
var tableUpdateSchema = updateSchema.omit({ setValues: true }).extend({ setValues: sqlValSchemaFile2.optional() });
var tableSelectSchema = selectSchema;
var tableViewSchema = selectSchema.pick({ select: true, where: true });
var tableEditSchema = external_exports.object({
  setValues: sqlValSchemaFile2,
  or: updateSchema.shape.or.or(external_exports.literal("INSERT")),
  returning: updateSchema.shape.returning
});
var selectStatementSchema = tableSelectSchema.extend({
  type: external_exports.literal("SELECT"),
  table: tableColumnNameSchema
});
var insertStatementSchema = tableInsertSchema.extend({
  type: external_exports.literal("INSERT"),
  table: tableColumnNameSchema
});
var updateStatementSchema = tableUpdateSchema.extend({
  type: external_exports.literal("UPDATE"),
  table: tableColumnNameSchema
});
var deleteStatementSchema = tableDeleteSchema.extend({
  type: external_exports.literal("DELETE"),
  table: tableColumnNameSchema
});
var zSQLIndex = external_exports.object({
  name: tableColumnNameSchema.optional(),
  unique: external_exports.coerce.boolean().optional(),
  // fields: tableColumnNameSchema.or(z.array(tableColumnNameSchema)),
  fields: external_exports.string().or(external_exports.array(external_exports.string())),
  // fields can include collate also
  where: zSQLQuery.optional()
});
var zSQLTrigger = external_exports.object({
  name: tableColumnNameSchema,
  event: external_exports.enum(["INSERT", "DELETE", "UPDATE"]),
  seq: external_exports.enum(["BEFORE", "AFTER", "INSTEAD OF"]).optional(),
  updateOf: tableColumnNameSchema.or(external_exports.array(tableColumnNameSchema)).optional(),
  forEach: external_exports.enum(["ROW"]).optional(),
  body: zSQLQuery.or(external_exports.array(zSQLQuery)),
  when: zSQLQuery.optional()
});
var zTypedSQLQuery = external_exports.record(external_exports.string(), external_exports.any());
var zTypedSQLStatement = selectStatementSchema.or(insertStatementSchema).or(updateStatementSchema).or(deleteStatementSchema);
var zSQLProcedure = external_exports.object({
  name: tableColumnNameSchema,
  rule: external_exports.boolean().default(true),
  params: external_exports.array(tableColumnNameSchema),
  query: external_exports.union([zTypedSQLQuery, external_exports.array(zTypedSQLQuery)]).optional(),
  statement: external_exports.union([zTypedSQLStatement, external_exports.array(zTypedSQLStatement)]).optional()
});

// node_modules/teenybase/dist/sql/parse/jsep.js
var jsepSetup = false;
function setupJsep() {
  if (jsepSetup)
    return;
  jsepSetup = true;
  jsep.removeBinaryOp("||");
  jsep.removeBinaryOp("??");
  jsep.removeBinaryOp("&&");
  jsep.removeBinaryOp("|");
  jsep.removeBinaryOp("&");
  jsep.removeBinaryOp("^");
  jsep.removeBinaryOp(">>");
  jsep.removeBinaryOp("<<");
  jsep.removeBinaryOp(">>>");
  jsep.removeBinaryOp("**");
  jsep.removeUnaryOp("~");
  jsep.removeUnaryOp("+");
  jsep.removeUnaryOp("-");
  jsep.removeUnaryOp("!");
  jsep.addBinaryOp("|", 1);
  jsep.addBinaryOp("&", 2);
  jsep.addUnaryOp(
    "!"
    /*, 4*/
  );
  jsep.addBinaryOp("||", 12);
  jsep.addBinaryOp("~", jsep.binary_ops["=="]);
  jsep.addBinaryOp("!~", jsep.binary_ops["=="]);
  jsep.addBinaryOp("in", 10);
  jsep.addBinaryOp("=", jsep.binary_ops["=="]);
  jsep.addBinaryOp("as", 10);
  jsep.addBinaryOp("=>", 10);
  jsep.addBinaryOp("@@", jsep.binary_ops["=="]);
  jsep.addBinaryOp("->", 11);
  jsep.addBinaryOp("->>", 11);
  jsep.addUnaryOp("+");
  jsep.addUnaryOp("-");
}
__name(setupJsep, "setupJsep");
function honoToJsep(req, auth) {
  const url = new URL(req.url);
  return {
    request: {
      method: req.method.toUpperCase(),
      url: {
        href: req.url,
        protocol: url.protocol,
        host: url.host,
        hostname: url.hostname,
        port: url.port,
        pathname: url.pathname,
        search: url.search,
        hash: url.hash,
        origin: url.origin
      },
      headers: req.header(),
      // todo normalize header names
      query: req.query()
      // auth
      // admin - separate just to be safe
    },
    auth: auth ?? { uid: null, sid: null, verified: false, admin: false, jwt: {}, email: null, role: null, meta: {}, superadmin: false }
  };
}
__name(honoToJsep, "honoToJsep");
var jsepCache = /* @__PURE__ */ new Map();
function jsepParse(q, literals) {
  if (!literals && jsepCache.has(q)) {
    return structuredClone(jsepCache.get(q));
  }
  if (literals)
    for (const key of Object.keys(literals)) {
      if (jsep.literals[key]) {
        console.warn(`Literal ${key} already exists in jsep literals. Overwriting.`);
      }
      jsep.addLiteral(key, literals[key]);
    }
  const tree = jsep(q);
  if (literals)
    for (const key of Object.keys(literals)) {
      jsep.removeLiteral(key);
    }
  if (!literals) {
    jsepCache.set(q, structuredClone(tree));
  }
  return tree;
}
__name(jsepParse, "jsepParse");
function createJsepContext(tableName, tables, globals, allowedTables, extras, autoNullProps = true, autoSimplifyExpr = true) {
  setupJsep();
  const isAdmin = globals.auth?.admin === true;
  const allTables = Object.fromEntries(tables.map((t) => [
    columnify(t.name),
    t.fields.filter((f) => isAdmin || !f.noSelect).map((f) => ({
      name: columnify(f.name),
      sqlType: f.sqlType,
      foreignKey: f.foreignKey ? {
        table: columnify(f.foreignKey.table),
        column: columnify(f.foreignKey.column)
      } : void 0,
      isUnique: isTableFieldUnique(f, t)
    }))
  ]));
  return {
    tableName: columnify(tableName),
    globals,
    allTables,
    allowedTables: Object.fromEntries(allowedTables?.map((t) => [columnify(t), allTables[columnify(t)]]) ?? []),
    extras: extras || {},
    autoNullProps,
    autoSimplifyExpr
  };
}
__name(createJsepContext, "createJsepContext");
var operatorMapping = {
  "==": "IS",
  "!=": "IS NOT",
  "=": "=",
  "~": "LIKE",
  "!~": "NOT LIKE",
  "<": "<",
  "<=": "<=",
  ">": ">",
  ">=": ">=",
  "&": "AND",
  "|": "OR",
  "+": "+",
  "-": "-",
  "*": "*",
  "/": "/",
  "in": "IN",
  "IN": "IN",
  "!": "NOT",
  // '&&': 'AND',
  "||": "||",
  // || is string concatenation in sql, todo should we disable this since concat is also available
  "->": "->",
  "->>": "->>"
  // '%': '%',
  // '^': '^',
  // '<<': '<<',
  // '>>': '>>',
  // '>>>': '>>>',
  // as
  // '=>' : '', // dont uncomment, it must be explicitly parsed if required, see parseColumnList
  // 'as' : '', // dont uncomment
  // 'AS' : '', // dont uncomment
  // fts5
  // '@@': '@@', // dont uncomment, see BinaryOp
};
var functionMapping = {
  "lower": "LOWER",
  "upper": "UPPER",
  "count": "COUNT",
  "substring": "SUBSTRING",
  "length": "LENGTH",
  "unixepoch": "UNIXEPOCH",
  "datetime": "DATETIME",
  "date": "DATE",
  "time": "TIME",
  "concat": "CONCAT",
  "sum": "SUM",
  // 'trim': 'TRIM',
  "replace": "REPLACE",
  // 'regexp_replace': 'REGEXP_REPLACE',
  // 'regexp_match': 'REGEXP_MATCH',
  // 'regexp_split': 'REGEXP_SPLIT',
  // 'regexp_extract': 'REGEXP_EXTRACT',
  // 'regexp_extract_all': 'REGEXP_EXTRACT_ALL',
  // 'regexp_like': 'REGEXP_LIKE',
  // 'json_extract': 'JSON_EXTRACT', // use -> or ->> operator
  // 'json_array_length': 'JSON_ARRAY_LENGTH',
  // 'json_valid': 'JSON_VALID',
  // 'json' : 'JSON',
  "json_set": "JSON_SET",
  "json_insert": "JSON_INSERT",
  // like set but does not overwrite
  "json_replace": "JSON_REPLACE",
  // 'json_each': 'JSON_EACH', see json_contains
  "json_patch": "JSON_PATCH",
  // Merge Patch https://datatracker.ietf.org/doc/html/rfc7396
  "json_contains": (args, c) => {
    if (args.length !== 2)
      throw new Error("json_contains requires 2 arguments");
    return `EXISTS (SELECT 1 FROM json_each(${args[0].q}) WHERE value = ${args[1].q})`;
  }
  // more -  https://developers.cloudflare.com/d1/build-with-d1/query-json/#supported-functions
};
function columnify(s) {
  return `[${tableColumnNameSchema.parse(s)}]`;
}
__name(columnify, "columnify");
function uncolumnify(s) {
  return s.trim().replace(/^\[(.*)\]$/, "$1");
}
__name(uncolumnify, "uncolumnify");
function resolveIdentifier(exp, context2) {
  if (exp.type !== "Identifier") {
    throw new Error("Not supported, expected Identifier, got " + exp.type);
  }
  return ident(exp.name, context2);
}
__name(resolveIdentifier, "resolveIdentifier");
function ident(exp, context2, table3) {
  const column = columnify(exp);
  if (!table3)
    table3 = context2.tableName;
  if (context2._checkColumns !== false && !context2.allowedTables[table3]?.find((f) => f.name === column)) {
    throw new Error("Column not found " + column + " in " + table3);
  }
  return table3 + "." + column;
}
__name(ident, "ident");
var genOps = {
  "=": (l, r) => l === r,
  "IS": (l, r) => l === r,
  // '==': (l: TLi, r: TLi) => l === r,
  "IS NOT": (l, r) => l !== r
};
var numOps = {
  "<": (l, r) => l < r,
  "<=": (l, r) => l <= r,
  ">": (l, r) => l > r,
  ">=": (l, r) => l >= r,
  "+": (l, r) => l + r,
  "-": (l, r) => l - r,
  "*": (l, r) => l * r,
  "/": (l, r) => l / r
};
var boolOps = {
  "AND": (l, r) => l && r,
  "OR": (l, r) => l || r
};
function handleNull(operator, other) {
  if (operator === "AND") {
    return { l: null };
  } else if (operator === "OR") {
    return other;
  } else if (operator === "LIKE") {
    return { l: false };
  } else if (operator === "NOT LIKE") {
    return { l: true };
  } else if (operator === "=" || operator === "+" || operator === "-" || operator === "*" || operator === "/") {
    return { l: null };
  }
  const l = other.l;
  if (l === void 0)
    return null;
  if (operator === "IS") {
    return { l: l === null };
  } else if (operator === "IS NOT") {
    return { l: l !== null };
  }
  return null;
}
__name(handleNull, "handleNull");
function handleBool(lit, operator, other) {
  if (operator === "AND") {
    return lit === false ? { l: false } : other;
  }
  if (operator === "OR") {
    return lit === true ? { l: true } : other;
  }
  return null;
}
__name(handleBool, "handleBool");
function applyLiteralOperator(l, r, operator) {
  const isObj = typeof l === "object";
  const isNum = typeof l === "number";
  const isBool = typeof l === "boolean";
  const isStr = typeof l === "string";
  if (!isObj || l === null && r === null) {
    let op = null;
    if (!op && genOps[operator])
      op = genOps[operator];
    if (!op && isBool && boolOps[operator])
      op = boolOps[operator];
    if (!op && (isNum || isBool) && numOps[operator])
      op = numOps[operator];
    if (op !== null) {
      return { l: op(l, r) };
    }
  } else {
  }
  return null;
}
__name(applyLiteralOperator, "applyLiteralOperator");
function applyBinaryOperator(left, right, operator, simplify) {
  if (operator === "=") {
    if (left.l === null || right.l === null)
      operator = "IS";
  }
  if (simplify) {
    let res = null;
    const leftLit = left.l !== void 0;
    const rightLit = right.l !== void 0;
    if (leftLit && rightLit) {
      let l = left.l;
      let r = right.l;
      if (typeof l === "number" && !isFinite(l))
        l = null;
      if (typeof r === "number" && !isFinite(r))
        r = null;
      if (typeof l === typeof r) {
        res = applyLiteralOperator(l, r, operator);
      } else {
        if (l === null || r === null) {
          const other = l === null ? r : l;
          res = handleNull(operator, { l: other });
        }
        if (!res && (typeof l === "boolean" || typeof r === "boolean")) {
          res = applyLiteralOperator(l, r, operator);
        }
      }
    } else if (leftLit || rightLit) {
      const lit = (leftLit ? left : right).l;
      const other = leftLit ? right : left;
      if (typeof lit === "boolean") {
        res = handleBool(lit, operator, other);
      }
      if (!res && lit === null) {
        res = handleNull(operator, other);
      }
    }
    if (res) {
      return res;
    }
  }
  const left1 = literalToQuery(left);
  const right1 = literalToQuery(right);
  return {
    q: `${left1.q} ${operator} ${right1.q}${operator.includes("LIKE") ? ` ESCAPE '\\'` : ""}`,
    p: { ...left1.p, ...right1.p },
    dependencies: [...left1.dependencies || [], ...right1.dependencies || []],
    _readOnly: left1._readOnly && right1._readOnly
  };
}
__name(applyBinaryOperator, "applyBinaryOperator");
function applyBoolJoinOperator(args, operator, simplify) {
  if (operator !== "AND" && operator !== "OR")
    throw new Error("Invalid operator, only AND and OR are supported");
  if (simplify) {
    let res = null;
    const literals = args.map((a) => a.l !== void 0);
    if (literals.length) {
      const bools = args.filter((a) => typeof a.l === "boolean").map((a) => a.l);
      if (operator === "AND") {
        if (!bools.every((b) => b)) {
          res = { l: false };
        } else {
        }
      } else if (operator === "OR") {
        if (bools.some((b) => b)) {
          res = { l: true };
        } else {
        }
      }
      if (!res) {
        const nulls = args.filter((a) => a.l === null);
        if (operator === "AND" && nulls.length) {
          res = { l: null };
        } else if (operator === "OR" && nulls.length) {
        }
        args = args.filter((a) => a.l !== null && typeof a.l !== "boolean");
      }
    }
    if (res) {
      return res;
    }
  }
  const args1 = args.map((a) => literalToQuery(a));
  return {
    q: args1.map((a) => a.q).join(` ${operator} `),
    p: args1.reduce((acc, a) => ({ ...acc, ...a.p }), {}),
    dependencies: args1.reduce((acc, a) => [...acc, ...a.dependencies || []], [])
  };
}
__name(applyBoolJoinOperator, "applyBoolJoinOperator");
function applyUnaryOperator(arg, operator, simplify) {
  const l = arg.l;
  if (simplify && l !== void 0) {
    let res = null;
    if (operator === "NOT") {
      const type = typeof l;
      if (type === "boolean") {
        res = { l: !l ? 1 : 0 };
      } else if (l === null) {
        res = { l: null };
      } else if (type === "number") {
        res = { l: l === 0 ? 1 : 0 };
      } else if (type === "string") {
        const f = parseFloat(l);
        res = { l: isFinite(f) ? !f ? 1 : 0 : 1 };
      } else {
      }
    }
    if (res) {
      return res;
    }
  }
  const arg1 = literalToQuery(arg);
  return {
    q: `${operator} ${arg1.q}`,
    p: arg1.p,
    dependencies: arg1.dependencies,
    _readOnly: arg1._readOnly
  };
}
__name(applyUnaryOperator, "applyUnaryOperator");
function treeToSql(tree, context2) {
  if (tree.type === "Identifier") {
    const exp = tree;
    const res = { q: resolveIdentifier(exp, context2), _readOnly: true };
    return res;
  }
  if (tree.type === "Literal") {
    const exp = tree;
    return { l: sqlValSchema.parse(exp.value) };
  }
  if (tree.type === "BinaryExpression") {
    const exp = tree;
    let left = void 0;
    let right = void 0;
    let operator = void 0;
    if (exp.operator === "@@") {
      let ftsTableName;
      let ftsColumnName = void 0;
      if (exp.left.type === "Identifier") {
        const idn = exp.left;
        const name = columnify(idn.name);
        if (name === context2.tableName) {
          ftsTableName = columnify(fts5TableName(idn.name));
        } else if (context2.allowedTables[context2.tableName]?.find((f) => f.name === name)) {
          ftsTableName = columnify(fts5TableName(uncolumnify(context2.tableName)));
          ftsColumnName = name;
        } else {
          throw new Error("Not supported - Invalid left side of @@ operator");
        }
      } else if (exp.left.type === "MemberExpression") {
        const mem = exp.left;
        if (mem.object.type !== "Identifier")
          throw new Error("Not supported - Invalid left side of @@ operator, expected tableName.columnName");
        const objName = mem.object.name;
        const tableName = columnify(objName);
        if (tableName !== context2.tableName)
          throw new Error("Not supported - Invalid left side of @@ operator, invalid table");
        if (mem.property.type !== "Identifier")
          throw new Error("Not supported - Invalid left side of @@ operator, expected tableName.columnName");
        const columnName = columnify(mem.property.name);
        if (!context2.allowedTables[tableName]?.find((f) => f.name === columnName))
          throw new Error("Not supported - Invalid left side of @@ operator, table/column not found");
        ftsTableName = columnify(fts5TableName(objName));
        ftsColumnName = columnName;
      } else {
        throw new Error("Not supported - Invalid left side of @@ operator");
      }
      if (!ftsTableName)
        throw new Error("Not supported - FTS table not found");
      if (!ftsColumnName) {
        left = { q: ftsTableName, _readOnly: true };
      } else {
        left = { q: `${ftsTableName}.${ftsColumnName}`, _readOnly: true };
      }
      left.dependencies = [{
        type: "fts",
        table: context2.tableName,
        column: ftsColumnName
      }];
      if (exp.right.type !== "Literal" || typeof exp.right.value !== "string") {
        throw new Error("Not supported - Invalid right side of @@ operator, only string supported at the moment.");
      }
      right = treeToSql(exp.right, context2);
      operator = "MATCH";
    }
    left = left ?? treeToSql(exp.left, context2);
    right = right ?? treeToSql(exp.right, context2);
    operator = operator ?? operatorMapping[exp.operator];
    if (!operator) {
      throw new Error(`Operator ${exp.operator} not supported`);
    }
    return applyBinaryOperator(left, right, operator, context2.autoSimplifyExpr);
  }
  if (tree.type === "UnaryExpression") {
    const exp = tree;
    const arg = treeToSql(exp.argument, context2);
    let operator = operatorMapping[exp.operator];
    if (!operator) {
      throw new Error(`Operator ${exp.operator} not supported`);
    }
    return applyUnaryOperator(arg, operator, context2.autoSimplifyExpr);
  }
  if (tree.type === "MemberExpression") {
    const exp = tree;
    if (exp.computed)
      throw new Error("Not supported - computed");
    if (exp.property.type !== "Identifier")
      throw new Error("Not supported, not an identifier");
    const prop = exp.property;
    let obj;
    if (exp.object.type === "Identifier") {
      const ob = exp.object;
      const global = context2.globals[ob.name];
      if (global) {
        obj = { l: global, key: ob.name };
      } else {
        let table3 = columnify(ob.name);
        const extra = context2.extras[table3];
        if (extra) {
          const v = extra.literals[prop.name];
          if (v)
            return literalToQuery(v);
          if (extra.table)
            table3 = extra.table;
        }
        const column = columnify(prop.name);
        if (context2.allowedTables[table3]?.find((f) => f.name === column) || context2.tableName === table3 && context2._checkColumns === false)
          return { q: `${table3}.${column}`, _readOnly: true };
      }
    }
    if (!obj)
      obj = treeToSql(exp.object, context2);
    if (obj.l === null && context2.autoNullProps)
      obj.l = {};
    if (obj.l === void 0 || obj.l === null) {
      if (exp.object.name)
        throw new Error(`ParseError - object not found "${exp.object.name}"`);
      throw new Error("ParseError - object does not have value " + JSON.stringify(exp.object));
    }
    if (typeof obj.l !== "object")
      throw new Error("ParseError - object is not an object");
    let val = obj.l[prop.name];
    if (val === void 0) {
      if (context2.autoNullProps)
        val = null;
      else
        throw new Error(`ParseError - property does not exist "${prop.name}" in "${obj.key ?? exp.object.name ?? ""}"`);
    }
    return { l: val, key: (obj.key || "?") + "." + prop.name };
  }
  if (tree.type === "CallExpression") {
    const exp = tree;
    if (exp.callee.type !== "Identifier")
      throw new Error("Not supported, function caller not an identifier");
    const callee = exp.callee;
    const func = functionMapping[callee.name.toLowerCase()];
    if (!func)
      throw new Error(`Function ${callee.name} not supported`);
    if (func === "COUNT" && exp.arguments.length === 0) {
      return { q: "COUNT(*)", _readOnly: true };
    }
    const args = exp.arguments.map((arg) => literalToQuery(treeToSql(arg, context2)));
    const q = typeof func === "function" ? func(args, context2) : (
      // this could update args...
      `${func}(${args.map((a) => a.q).join(", ")})`
    );
    return {
      q,
      p: args.reduce((acc, a) => ({ ...acc, ...a.p }), {}),
      dependencies: args.reduce((acc, a) => [...acc, ...a.dependencies || []], []),
      _readOnly: args.every((a) => a._readOnly)
    };
  }
  throw new Error("Not Supported type - " + tree.type);
}
__name(treeToSql, "treeToSql");
function parseColumnList(q, context2, allowExpr = false, allowAs = false, allowExpand = false) {
  let hasStar = false;
  if (Array.isArray(q)) {
    hasStar = !!q.find((f) => f.trim() === "*");
    q = q.filter((f) => f.trim() !== "*").join(", ");
  }
  if (q === "*")
    return ["*"];
  let tree = typeof q === "string" ? jsepParse(q) : q;
  if (tree.type !== "Compound") {
    tree = { type: "Compound", body: [tree] };
  }
  const exp = tree;
  const res = [];
  for (let item of exp.body) {
    if (!allowExpr) {
      if (allowAs)
        throw new Error("parseColumnList: allowAs must be false when allowExpr is false");
      if (allowExpand)
        throw new Error("parseColumnList: allowExpand must be false when allowExpr is false");
      res.push(resolveIdentifier(item, context2));
    } else {
      let asName = void 0;
      if (allowAs && item.type === "BinaryExpression") {
        const exp1 = item;
        if (!(exp1.operator !== "as" && exp1.operator !== "=>")) {
          if (exp1.right.type !== "Identifier")
            throw new Error("Not supported, expected identifier");
          item = exp1.left;
          asName = columnify(exp1.right.name);
        } else {
        }
      }
      if (allowExpand && item.type === "CallExpression" && item.callee.type === "Identifier") {
        const exp2 = item;
        const tableName = context2.tableName;
        const table3 = context2.allowedTables[tableName];
        const callee = exp2.callee;
        const fkTableOrColumnName = columnify(callee.name.toLowerCase());
        let fkTable = context2.allTables[fkTableOrColumnName];
        let fkTableName = fkTableOrColumnName;
        let tColumn;
        if (!fkTable) {
          tColumn = table3.find((f) => f.name === fkTableOrColumnName && f.foreignKey);
          if (tColumn) {
            fkTableName = tColumn.foreignKey.table;
            fkTable = context2.allTables[tColumn.foreignKey.table];
          }
        }
        if (fkTable) {
          if (!tColumn)
            tColumn = table3.find((f) => f.foreignKey?.table === fkTableName);
          if (!tColumn)
            throw new Error("Foreign key not found " + fkTableName);
          const fkColumn = tColumn.foreignKey.column;
          const fkColumnFull = fkTable.find((f) => f.name === fkColumn);
          if (!fkColumnFull)
            throw new Error("Foreign key column not found " + fkTableName + "." + fkColumn);
          let fkSelectColumns;
          if (!exp2.arguments.length) {
            fkSelectColumns = fkTable.map((f) => `${fkTableName}.${f.name}`);
          } else {
            const args = {
              type: "Compound",
              body: exp2.arguments
            };
            const context22 = {
              ...context2,
              tableName: fkTableName,
              allowedTables: { [fkTableName]: context2.allTables[fkTableName] }
            };
            const allowNestedExpands = false;
            const allowExpressions = true;
            fkSelectColumns = parseColumnList(args, context22, allowExpressions, allowExpressions, allowExpressions && allowNestedExpands);
          }
          const q2 = {
            selects: fkSelectColumns,
            from: fkTableName,
            where: { q: `${tableName}.${tColumn.name} = ${fkTableName}.${fkColumn}`, _readOnly: true },
            as: asName || fkTableOrColumnName,
            _readOnly: true
          };
          if (fkColumnFull.isUnique)
            q2.limit = 1;
          res.push(q2);
          continue;
        } else {
        }
      }
      const sql = treeToSql(item, context2);
      if (sql.l)
        throw new Error("Not supported - literal in column list");
      const sql1 = sql;
      if (!sql1.q) {
        throw new Error("Not supported - invalid column");
      }
      if (!asName && (sql1.p && Object.keys(sql1.p).length)) {
        throw new Error("Not supported - Expressions must have an alias(AS or =>)");
      }
      if (!sql1.q || sql1.dependencies && sql1.dependencies.length) {
        throw new Error("Not supported - has dependencies/invalid");
      }
      if (asName && sql1.q[sql1.q.length - 1] === "*")
        throw new Error("Not supported, cannot use * with AS");
      res.push(!asName ? sql1.q : { ...sql1, as: asName });
    }
  }
  return !hasStar ? res : ["*", ...res];
}
__name(parseColumnList, "parseColumnList");
function parseColumnListOrder(q, context2) {
  if (Array.isArray(q))
    q = q.join(", ");
  let tree = jsepParse(q);
  if (tree.type !== "Compound") {
    tree = { type: "Compound", body: [tree] };
  }
  const exp = tree;
  const res = [];
  for (const item of exp.body) {
    if (item.type === "UnaryExpression") {
      const exp1 = item;
      const asc = exp1.operator === "+" ? "ASC" : exp1.operator === "-" ? "DESC" : null;
      if (!asc)
        throw new Error("Not supported, expected + or -, got " + exp1.operator);
      res.push(resolveIdentifier(exp1.argument, context2) + " " + asc);
      continue;
    }
    res.push(resolveIdentifier(item, context2));
  }
  return res;
}
__name(parseColumnListOrder, "parseColumnListOrder");

// node_modules/teenybase/dist/sql/build/select.js
function getSubSelectQueries(query) {
  const subQueries = Array.isArray(query.selects) ? query.selects.filter((s) => typeof s !== "string" && s.from !== void 0 && s.as !== void 0) : [];
  return subQueries;
}
__name(getSubSelectQueries, "getSubSelectQueries");
function buildSelectWhere(queryWhere, simplify) {
  let q;
  if (Array.isArray(queryWhere)) {
    q = applyBoolJoinOperator(queryWhere, "AND", simplify);
  } else if (simplify && queryWhere.l !== void 0) {
    const l = queryWhere.l;
    if (!l || l === "" || l === "false" || l === "0" || l === "null") {
      return null;
    }
    if (l === true || typeof l === "number" || l === "true" || l === "1") {
      return { q: "" };
    }
    throw new Error(`Invalid where clause literal ${l}`);
  } else {
    q = queryWhere;
  }
  return literalToQuery(q, true);
}
__name(buildSelectWhere, "buildSelectWhere");
function joinReturning(returning, p) {
  return returning.map((select) => {
    if (typeof select === "string" || typeof select.q === "string") {
      return typeof select === "string" ? select : select.q + " AS " + select.as;
    } else {
      throw new Error("Invalid returning");
    }
  }).join(", ");
}
__name(joinReturning, "joinReturning");
function buildSelectQuery(query, simplify = true, allowAllWhere = true) {
  const inSubquery = !!query.as;
  const p = { ...query.params };
  let q = "SELECT ";
  if (query.distinct)
    q += "DISTINCT ";
  if (query.selectOption)
    q += query.selectOption + " ";
  if (query.selects?.length) {
    const selects = Array.isArray(query.selects) ? query.selects : [query.selects];
    const subQueryJson = inSubquery && selects.length > 1;
    const subQueryJsonArray = subQueryJson && query.limit !== 1;
    let selectQ = selects.map((select) => {
      const isStr = typeof select === "string";
      if (isStr || typeof select.q === "string") {
        if (!isStr && select.p)
          Object.assign(p, select.p);
        if (subQueryJson) {
          const name = isStr ? select : select.as;
          if (!name)
            throw new Error("Expand/Subquery selects must have an AS property");
          const q2 = isStr ? select : select.q;
          const printableName = uncolumnify(name.split(".").pop());
          const lit = literalToQuery({ l: printableName });
          Object.assign(p, lit.p);
          return lit.q + "," + q2;
        }
        return isStr ? select : select.q + (select.as ? " AS " + select.as : "");
      } else {
        const col = select;
        if (!col.from)
          throw new Error("Subquery must have a FROM property");
        const subQuery = buildSelectQuery(select, simplify, allowAllWhere);
        Object.assign(p, subQuery.p);
        let asName = select.as || select.from;
        if (typeof asName !== "string")
          throw new Error("Subquery must have an AS or a single FROM property");
        return `(${subQuery.q}) AS ${asName}`;
      }
    }).join(", ");
    if (subQueryJson)
      selectQ = `json_object(${selectQ})`;
    if (subQueryJsonArray)
      selectQ = `json_group_array(${selectQ})`;
    q += selectQ;
  } else if (query.from)
    q += typeof query.from === "string" ? query.from + ".*" : query.from.map((f) => f + ".*").join(", ");
  else {
    if (query.distinct || query.selectOption) {
      throw new Error("selects must be provided if distinct or selectOption is set");
    }
    q = "";
  }
  if (query.from) {
    q += " FROM " + (typeof query.from === "string" ? query.from : query.from.join(", "));
  }
  if (query.join?.length) {
    for (const j of query.join) {
      const onClause = literalToQuery(j.on);
      const type = j.type ? j.type.toUpperCase() + " " : "";
      q += ` ${type}JOIN ${j.table} ON ${onClause.q}`;
      Object.assign(p, onClause.p);
    }
  }
  if (query.where) {
    let where = buildSelectWhere(query.where, simplify);
    if (where === null || !where.q && !allowAllWhere)
      return { q: "" };
    q += " WHERE " + (where.q || "1");
    if (where.p)
      Object.assign(p, where.p);
  } else if (!allowAllWhere) {
    return { q: "" };
  } else {
    q += " WHERE 1";
  }
  if (query.groupBy?.length) {
    q += " GROUP BY " + query.groupBy.join(", ");
  }
  if (query.having) {
    const having = literalToQuery(query.having);
    q += " HAVING " + having.q;
    Object.assign(p, having.p);
  }
  if (query.orderBy?.length) {
    q += " ORDER BY " + (typeof query.orderBy === "string" ? query.orderBy : query.orderBy.join(", "));
  }
  if (query.limit !== void 0) {
    let limit = query.limit;
    if (limit < 0 && query.offset) {
      limit = Number.MAX_SAFE_INTEGER;
    }
    if (limit >= 0)
      q += " LIMIT " + limit;
  }
  if (query.offset !== void 0 && query.offset > 0) {
    q += " OFFSET " + query.offset;
  }
  if (!inSubquery)
    q += ";\n";
  return { q, p, _readOnly: query._readOnly };
}
__name(buildSelectQuery, "buildSelectQuery");
function appendWhere(query, sql) {
  if (Array.isArray(query.where))
    query.where.push(sql);
  else
    query.where = query.where ? [query.where, sql] : sql;
  return query;
}
__name(appendWhere, "appendWhere");
function appendOrderBy(query, sql) {
  if (Array.isArray(query.orderBy))
    query.orderBy.push(sql);
  else
    query.orderBy = query.orderBy ? [query.orderBy, sql] : sql;
  return query;
}
__name(appendOrderBy, "appendOrderBy");
function appendJoin(query, join) {
  if (!query.join)
    query.join = [];
  query.join.push(join);
  return query;
}
__name(appendJoin, "appendJoin");

// node_modules/teenybase/dist/sql/build/update.js
var UPDATE_NEW_COL_ID = columnify("new");
function buildUpdateQuery(query, simplify = true, allowAllWhere = true) {
  const p = { ...query.params };
  let q = `UPDATE ${query.table} `;
  if (query.or)
    q += `OR ${query.or} `;
  q += "SET ";
  let where = "";
  if (query.where) {
    const whereQ = buildSelectWhere(query.where, simplify);
    if (whereQ === null || !whereQ.q && !allowAllWhere)
      return { q: "" };
    where = whereQ.q;
    Object.assign(p, whereQ.p);
  } else if (!allowAllWhere) {
    return { q: "" };
  } else {
  }
  const setKeys = Object.keys(query.set);
  for (let i = 0; i < setKeys.length; i++) {
    const key = setKeys[i];
    const set = literalToQuery(query.set[key]);
    if (i > 0)
      q += ", ";
    q += `${columnify(key)} = ${set.q}`;
    Object.assign(p, set.p);
  }
  const returning = query.returning || [];
  if (where) {
    q += " WHERE " + where;
  }
  if (returning.length) {
    q += " RETURNING " + joinReturning(returning, p);
  }
  q += ";\n";
  return { q, p };
}
__name(buildUpdateQuery, "buildUpdateQuery");

// node_modules/teenybase/dist/sql/parse/parse.js
function queryToSqlQuery(query, c) {
  if (typeof query !== "string")
    throw new Error("Query must be a string");
  const tree = jsepParse(
    query
    /*, c.globals*/
  );
  const sqlQuery = treeToSql(tree, c);
  return sqlQuery;
}
__name(queryToSqlQuery, "queryToSqlQuery");
function recordToSqlValues(data) {
  return Object.fromEntries(Object.entries(data).map(([k, v]) => [k, { l: v }]));
}
__name(recordToSqlValues, "recordToSqlValues");
function recordToSqlExpressions(data, c) {
  return Object.fromEntries(Object.entries(data).map(([k, v]) => [k, queryToSqlQuery(v, c)]));
}
__name(recordToSqlExpressions, "recordToSqlExpressions");

// node_modules/teenybase/dist/types/zod/tableExtensionsSchema.js
var tableRulesDataSchema = external_exports.object({
  name: external_exports.literal("rules"),
  listRule: sqlExprSchema.nullable().default(null),
  viewRule: sqlExprSchema.nullable().default(null),
  createRule: sqlExprSchema.nullable().default(null),
  updateRule: sqlExprSchema.nullable().default(null),
  deleteRule: sqlExprSchema.nullable().default(null)
});
var emailTemplateSchema = external_exports.object({
  subject: external_exports.string().optional(),
  variables: external_exports.record(external_exports.any()).optional(),
  tags: external_exports.string().optional(),
  layoutHtml: external_exports.string().optional()
});
var tableAuthDataSchema = external_exports.object({
  name: external_exports.literal("auth"),
  jwtSecret: external_exports.string(),
  jwtTokenDuration: external_exports.number(),
  maxTokenRefresh: external_exports.number(),
  passwordType: external_exports.literal("sha256").default("sha256"),
  passwordConfirmSuffix: external_exports.string().optional(),
  passwordCurrentSuffix: external_exports.string().optional(),
  passwordResetTokenDuration: external_exports.number().optional(),
  emailVerifyTokenDuration: external_exports.number().optional(),
  passwordResetEmailDuration: external_exports.number().optional(),
  emailVerifyEmailDuration: external_exports.number().optional(),
  autoSendVerificationEmail: external_exports.coerce.boolean().optional(),
  emailTemplates: external_exports.object({
    verification: emailTemplateSchema.optional(),
    passwordReset: emailTemplateSchema.optional()
  }).optional()
  // onlyVerified: z.coerce.boolean().optional(),
  // minPasswordLength: z.number().optional(),
  // onlyEmailDomains: z.array(z.string()).nullable().optional(),
  // exceptEmailDomains: z.array(z.string()).nullable().optional(),
  // allowEmailAuth: z.coerce.boolean().optional(),
  // allowUsernameAuth: z.coerce.boolean().optional(),
  // allowOAuth2Auth: z.coerce.boolean().optional(),
  // manageRule: z.string().nullable().optional(),
});

// node_modules/teenybase/dist/worker/extensions/tableRulesExtension.js
var _TableRulesExtension = class extends TableExtension {
  constructor(data, table3, jc) {
    super(tableRulesDataSchema.parse(data), table3, jc);
    if (data.name !== _TableRulesExtension.name)
      throw new HTTPException(500, { message: "Invalid Configuration" });
  }
  _applyWhere(jc, query, rule) {
    if (jc.globals.auth?.admin)
      return;
    const ruleSql = parseRuleQuery(jc, rule);
    appendWhere(query, ruleSql);
  }
  async onInsertParse(query) {
    this._applyWhere({
      ...this.jc,
      tableName: UPDATE_NEW_COL_ID,
      allowedTables: { [UPDATE_NEW_COL_ID]: this.jc.allowedTables[this.jc.tableName] }
    }, query, this.data.createRule);
  }
  async onDeleteParse(query) {
    this._applyWhere(this.jc, query, this.data.deleteRule);
  }
  async onSelectParse(query) {
    this._applyWhere(this.jc, query, this.data.listRule);
  }
  async onViewParse(query) {
    this._applyWhere(this.jc, query, this.data.viewRule);
  }
  async onUpdateParse(query) {
    this._applyWhere(query.contextWithNew || this.jc, query, this.data.updateRule);
  }
};
var TableRulesExtension = _TableRulesExtension;
__publicField(TableRulesExtension, "name", "rules");
function parseRuleQuery(c, rule) {
  if (rule === null || rule === void 0) {
    throw new ProcessError("Forbidden", 403);
  }
  if (rule === "true" || rule === "1")
    return { q: "1" };
  if (typeof rule !== "string")
    throw new ProcessError("Invalid Configuration", 500);
  if (!rule.trim().length)
    throw new ProcessError("Not Found", 404);
  rule = sqlExprSchema.parse(rule);
  try {
    return queryToSqlQuery(rule, c);
  } catch (e) {
    throw new ProcessError("Error parsing rule", 500, { input: rule }, e);
  }
}
__name(parseRuleQuery, "parseRuleQuery");

// node_modules/teenybase/dist/worker/util/passwordProcessors.js
var passwordProcessors = {
  "sha256": {
    hash: async (password, salt) => {
      const passText = new TextEncoder().encode((password + salt).normalize());
      const result = await crypto.subtle.digest("SHA-256", passText);
      const hash = new Uint8Array(result);
      return Array.from(hash).map((b) => b.toString(16).padStart(2, "0")).join("");
    }
  }
};

// node_modules/teenybase/dist/worker/util/punycode.js
var maxInt = 2147483647;
var base = 36;
var tMin = 1;
var tMax = 26;
var skew = 38;
var damp = 700;
var initialBias = 72;
var initialN = 128;
var delimiter = "-";
var regexNonASCII = /[^\x00-\x7F]/;
var regexSeparators = /[\x2E\u3002\uFF0E\uFF61]/g;
var errors = {
  "overflow": "Overflow: input needs wider integers to process",
  "not-basic": "Illegal input >= 0x80 (not a basic code point)",
  "invalid-input": "Invalid input"
};
var baseMinusTMin = base - tMin;
var floor = Math.floor;
var stringFromCharCode = String.fromCharCode;
function error3(type) {
  throw new RangeError(errors[type]);
}
__name(error3, "error");
function map(array, callback) {
  const result = [];
  let length = array.length;
  while (length--) {
    result[length] = callback(array[length]);
  }
  return result;
}
__name(map, "map");
function mapDomain(domain2, callback) {
  const parts = domain2.split("@");
  let result = "";
  if (parts.length > 1) {
    result = parts[0] + "@";
    domain2 = parts[1];
  }
  domain2 = domain2.replace(regexSeparators, ".");
  const labels = domain2.split(".");
  const encoded = map(labels, callback).join(".");
  return result + encoded;
}
__name(mapDomain, "mapDomain");
function ucs2decode(string) {
  const output = [];
  let counter = 0;
  const length = string.length;
  while (counter < length) {
    const value = string.charCodeAt(counter++);
    if (value >= 55296 && value <= 56319 && counter < length) {
      const extra = string.charCodeAt(counter++);
      if ((extra & 64512) == 56320) {
        output.push(((value & 1023) << 10) + (extra & 1023) + 65536);
      } else {
        output.push(value);
        counter--;
      }
    } else {
      output.push(value);
    }
  }
  return output;
}
__name(ucs2decode, "ucs2decode");
var ucs2encode = /* @__PURE__ */ __name((codePoints) => String.fromCodePoint(...codePoints), "ucs2encode");
var digitToBasic = /* @__PURE__ */ __name(function(digit, flag) {
  return digit + 22 + 75 * (digit < 26 ? 1 : 0) - ((flag != 0 ? 1 : 0) << 5);
}, "digitToBasic");
var adapt = /* @__PURE__ */ __name(function(delta, numPoints, firstTime) {
  let k = 0;
  delta = firstTime ? floor(delta / damp) : delta >> 1;
  delta += floor(delta / numPoints);
  for (; delta > baseMinusTMin * tMax >> 1; k += base) {
    delta = floor(delta / baseMinusTMin);
  }
  return floor(k + (baseMinusTMin + 1) * delta / (delta + skew));
}, "adapt");
var encode = /* @__PURE__ */ __name(function(_input) {
  const output = [];
  const input = ucs2decode(_input);
  const inputLength = input.length;
  let n = initialN;
  let delta = 0;
  let bias = initialBias;
  for (const currentValue of input) {
    if (currentValue < 128) {
      output.push(stringFromCharCode(currentValue));
    }
  }
  const basicLength = output.length;
  let handledCPCount = basicLength;
  if (basicLength) {
    output.push(delimiter);
  }
  while (handledCPCount < inputLength) {
    let m = maxInt;
    for (const currentValue of input) {
      if (currentValue >= n && currentValue < m) {
        m = currentValue;
      }
    }
    const handledCPCountPlusOne = handledCPCount + 1;
    if (m - n > floor((maxInt - delta) / handledCPCountPlusOne)) {
      error3("overflow");
    }
    delta += (m - n) * handledCPCountPlusOne;
    n = m;
    for (const currentValue of input) {
      if (currentValue < n && ++delta > maxInt) {
        error3("overflow");
      }
      if (currentValue === n) {
        let q = delta;
        for (let k = base; ; k += base) {
          const t = k <= bias ? tMin : k >= bias + tMax ? tMax : k - bias;
          if (q < t) {
            break;
          }
          const qMinusT = q - t;
          const baseMinusT = base - t;
          output.push(stringFromCharCode(digitToBasic(t + qMinusT % baseMinusT, 0)));
          q = floor(qMinusT / baseMinusT);
        }
        output.push(stringFromCharCode(digitToBasic(q, 0)));
        bias = adapt(delta, handledCPCountPlusOne, handledCPCount === basicLength);
        delta = 0;
        ++handledCPCount;
      }
    }
    ++delta;
    ++n;
  }
  return output.join("");
}, "encode");
var toASCII = /* @__PURE__ */ __name(function(input) {
  return mapDomain(input, function(string) {
    return regexNonASCII.test(string) ? "xn--" + encode(string) : string;
  });
}, "toASCII");
var punycode1 = {
  /**
   * A string representing the current Punycode.js version number.
   * @memberOf punycode1
   * @type String
   */
  "version": "2.3.1",
  /**
   * An object of methods to convert from JavaScript's internal character
   * representation (UCS-2) to Unicode code points, and back.
   * @see <https://mathiasbynens.be/notes/javascript-encoding>
   * @memberOf punycode1
   * @type Object
   */
  "ucs2": {
    "decode": ucs2decode,
    "encode": ucs2encode
  },
  // 'decode': decode,
  "encode": encode,
  "toASCII": toASCII
  // 'toUnicode': toUnicode
};

// node_modules/teenybase/dist/worker/util/normalizeEmail.js
var PLUS_ONLY = /\+.*$/;
var PLUS_AND_DOT = /\.|\+.*$/g;
var providers = {
  "gmail.com": {
    cut: PLUS_AND_DOT
  },
  "googlemail.com": {
    cut: PLUS_AND_DOT,
    alias: "gmail.com"
  },
  "hotmail.com": {
    cut: PLUS_ONLY
  },
  "live.com": {
    cut: PLUS_AND_DOT
  },
  "outlook.com": {
    cut: PLUS_ONLY
  },
  "yahoo.com": {
    cut: PLUS_ONLY
  }
  // '*': { // for all?
  //     cut: PLUS_ONLY
  // }
};
function normalizeEmail(val) {
  val = val.trim().toLowerCase();
  const emailParts = val.split("@");
  if (emailParts.length !== 2 || !emailParts[0] || !emailParts[1]) {
    throw new Error("Invalid email address");
  }
  let [local, domain2] = emailParts;
  domain2 = punycode1.toASCII(domain2);
  const provider = providers[domain2] || providers["*"];
  if (provider) {
    if (provider.cut)
      local = local.replace(provider.cut, "");
    if (provider.alias)
      domain2 = provider.alias;
  }
  return `${local}@${domain2}`;
}
__name(normalizeEmail, "normalizeEmail");

// node_modules/@tsndr/cloudflare-worker-jwt/index.js
function bytesToByteString(bytes) {
  let byteStr = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    byteStr += String.fromCharCode(bytes[i]);
  }
  return byteStr;
}
__name(bytesToByteString, "bytesToByteString");
function byteStringToBytes(byteStr) {
  let bytes = new Uint8Array(byteStr.length);
  for (let i = 0; i < byteStr.length; i++) {
    bytes[i] = byteStr.charCodeAt(i);
  }
  return bytes;
}
__name(byteStringToBytes, "byteStringToBytes");
function arrayBufferToBase64String(arrayBuffer) {
  return btoa(bytesToByteString(new Uint8Array(arrayBuffer)));
}
__name(arrayBufferToBase64String, "arrayBufferToBase64String");
function base64StringToArrayBuffer(b64str) {
  return byteStringToBytes(atob(b64str)).buffer;
}
__name(base64StringToArrayBuffer, "base64StringToArrayBuffer");
function textToArrayBuffer(str) {
  return byteStringToBytes(str);
}
__name(textToArrayBuffer, "textToArrayBuffer");
function arrayBufferToBase64Url(arrayBuffer) {
  return arrayBufferToBase64String(arrayBuffer).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
__name(arrayBufferToBase64Url, "arrayBufferToBase64Url");
function base64UrlToArrayBuffer(b64url) {
  return base64StringToArrayBuffer(b64url.replace(/-/g, "+").replace(/_/g, "/").replace(/\s/g, ""));
}
__name(base64UrlToArrayBuffer, "base64UrlToArrayBuffer");
function textToBase64Url(str) {
  const encoder = new TextEncoder();
  const charCodes = encoder.encode(str);
  const binaryStr = String.fromCharCode(...charCodes);
  return btoa(binaryStr).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
__name(textToBase64Url, "textToBase64Url");
function pemToBinary(pem) {
  return base64StringToArrayBuffer(pem.replace(/-+(BEGIN|END).*/g, "").replace(/\s/g, ""));
}
__name(pemToBinary, "pemToBinary");
async function importTextSecret(key, algorithm2, keyUsages) {
  return await crypto.subtle.importKey("raw", textToArrayBuffer(key), algorithm2, true, keyUsages);
}
__name(importTextSecret, "importTextSecret");
async function importJwk(key, algorithm2, keyUsages) {
  return await crypto.subtle.importKey("jwk", key, algorithm2, true, keyUsages);
}
__name(importJwk, "importJwk");
async function importPublicKey(key, algorithm2, keyUsages) {
  return await crypto.subtle.importKey("spki", pemToBinary(key), algorithm2, true, keyUsages);
}
__name(importPublicKey, "importPublicKey");
async function importPrivateKey(key, algorithm2, keyUsages) {
  return await crypto.subtle.importKey("pkcs8", pemToBinary(key), algorithm2, true, keyUsages);
}
__name(importPrivateKey, "importPrivateKey");
async function importKey(key, algorithm2, keyUsages) {
  if (typeof key === "object")
    return importJwk(key, algorithm2, keyUsages);
  if (typeof key !== "string")
    throw new Error("Unsupported key type!");
  if (key.includes("PUBLIC"))
    return importPublicKey(key, algorithm2, keyUsages);
  if (key.includes("PRIVATE"))
    return importPrivateKey(key, algorithm2, keyUsages);
  return importTextSecret(key, algorithm2, keyUsages);
}
__name(importKey, "importKey");
function decodePayload(raw2) {
  try {
    const bytes = Array.from(atob(raw2), (char) => char.charCodeAt(0));
    const decodedString = new TextDecoder("utf-8").decode(new Uint8Array(bytes));
    return JSON.parse(decodedString);
  } catch {
    return;
  }
}
__name(decodePayload, "decodePayload");
if (typeof crypto === "undefined" || !crypto.subtle)
  throw new Error("SubtleCrypto not supported!");
var algorithms = {
  ES256: { name: "ECDSA", namedCurve: "P-256", hash: { name: "SHA-256" } },
  ES384: { name: "ECDSA", namedCurve: "P-384", hash: { name: "SHA-384" } },
  ES512: { name: "ECDSA", namedCurve: "P-521", hash: { name: "SHA-512" } },
  HS256: { name: "HMAC", hash: { name: "SHA-256" } },
  HS384: { name: "HMAC", hash: { name: "SHA-384" } },
  HS512: { name: "HMAC", hash: { name: "SHA-512" } },
  RS256: { name: "RSASSA-PKCS1-v1_5", hash: { name: "SHA-256" } },
  RS384: { name: "RSASSA-PKCS1-v1_5", hash: { name: "SHA-384" } },
  RS512: { name: "RSASSA-PKCS1-v1_5", hash: { name: "SHA-512" } }
};
async function sign(payload, secret, options = "HS256") {
  if (typeof options === "string")
    options = { algorithm: options };
  options = { algorithm: "HS256", header: { typ: "JWT" }, ...options };
  if (!payload || typeof payload !== "object")
    throw new Error("payload must be an object");
  if (!secret || typeof secret !== "string" && typeof secret !== "object")
    throw new Error("secret must be a string, a JWK object or a CryptoKey object");
  if (typeof options.algorithm !== "string")
    throw new Error("options.algorithm must be a string");
  const algorithm2 = algorithms[options.algorithm];
  if (!algorithm2)
    throw new Error("algorithm not found");
  if (!payload.iat)
    payload.iat = Math.floor(Date.now() / 1e3);
  const partialToken = `${textToBase64Url(JSON.stringify({ ...options.header, alg: options.algorithm }))}.${textToBase64Url(JSON.stringify(payload))}`;
  const key = secret instanceof CryptoKey ? secret : await importKey(secret, algorithm2, ["sign"]);
  const signature = await crypto.subtle.sign(algorithm2, key, textToArrayBuffer(partialToken));
  return `${partialToken}.${arrayBufferToBase64Url(signature)}`;
}
__name(sign, "sign");
async function verify(token, secret, options = "HS256") {
  if (typeof options === "string")
    options = { algorithm: options };
  options = { algorithm: "HS256", clockTolerance: 0, throwError: false, ...options };
  if (typeof token !== "string")
    throw new Error("token must be a string");
  if (typeof secret !== "string" && typeof secret !== "object")
    throw new Error("secret must be a string, a JWK object or a CryptoKey object");
  if (typeof options.algorithm !== "string")
    throw new Error("options.algorithm must be a string");
  const tokenParts = token.split(".");
  if (tokenParts.length !== 3)
    throw new Error("token must consist of 3 parts");
  const algorithm2 = algorithms[options.algorithm];
  if (!algorithm2)
    throw new Error("algorithm not found");
  const { header, payload } = decode(token);
  if (header?.alg !== options.algorithm) {
    if (options.throwError)
      throw new Error("ALG_MISMATCH");
    return false;
  }
  try {
    if (!payload)
      throw new Error("PARSE_ERROR");
    const now = Math.floor(Date.now() / 1e3);
    if (payload.nbf && payload.nbf > now && payload.nbf - now > (options.clockTolerance ?? 0))
      throw new Error("NOT_YET_VALID");
    if (payload.exp && payload.exp <= now && now - payload.exp > (options.clockTolerance ?? 0))
      throw new Error("EXPIRED");
    const key = secret instanceof CryptoKey ? secret : await importKey(secret, algorithm2, ["verify"]);
    return await crypto.subtle.verify(algorithm2, key, base64UrlToArrayBuffer(tokenParts[2]), textToArrayBuffer(`${tokenParts[0]}.${tokenParts[1]}`));
  } catch (err) {
    if (options.throwError)
      throw err;
    return false;
  }
}
__name(verify, "verify");
function decode(token) {
  return {
    header: decodePayload(token.split(".")[0].replace(/-/g, "+").replace(/_/g, "/")),
    payload: decodePayload(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))
  };
}
__name(decode, "decode");

// node_modules/teenybase/dist/worker/extensions/tableAuthExtension.schema.js
var defaultSchema = {
  // todo username should be case insensitive?
  username: external_exports.string().min(1).max(32).regex(/^[a-zA-Z][a-zA-Z0-9_]*$/),
  // username should not include `@`
  password: external_exports.string().min(8, { message: "Password must be at least 8 characters long" }).max(255, { message: "Password must be less than 255 characters long" }),
  email: external_exports.string().min(1).max(255).email(),
  identity: external_exports.string().min(1).max(255).email().or(external_exports.string().min(1).max(32).regex(/^[a-zA-Z][a-zA-Z0-9_]*$/)),
  // email or username
  name: external_exports.string().min(1).max(255).optional(),
  emailVerified: external_exports.coerce.boolean().optional()
};
var jwtTokenSchema = external_exports.string().min(10).describe("JWT token");
var uidTokenSchema = external_exports.string().length(22).describe("Token");

// node_modules/teenybase/dist/worker/extensions/tableAuthExtension.routes.js
function setupTableAuthExtensionRoutes() {
  const routeZod = {
    "/auth/login-token": () => ({
      description: "Login with token",
      request: { headers: external_exports.object({ Authorization: external_exports.string().min(10) }) },
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": {
            schema: external_exports.object({
              token: jwtTokenSchema,
              refresh_token: uidTokenSchema,
              verified: external_exports.boolean().optional().describe("Email verified. (only returned if false)")
            })
          } }
        }
      }
    }),
    "/auth/refresh-token": () => ({
      description: "Refresh login token",
      request: { headers: external_exports.object({ Authorization: external_exports.string().min(10) }), body: {
        required: true,
        content: { "application/json": { schema: {
          refresh_token: uidTokenSchema.describe("Refresh token provided with the token on login/refresh")
        } } }
      } },
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": {
            schema: external_exports.object({
              token: jwtTokenSchema,
              refresh_token: uidTokenSchema,
              verified: external_exports.boolean().optional().describe("Email verified. (only returned if false)")
            })
          } }
        }
      }
    }),
    "/auth/logout": () => ({
      description: "Logout. Invalidates the current session. (requires login)",
      request: {},
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": {
            schema: external_exports.object({ success: external_exports.literal(true) })
          } }
        }
      }
    }),
    "/auth/sign-up": () => ({
      description: "Sign up. (similar to insert, but returns the login token along with the record)",
      request: { body: {
        required: true,
        content: { "application/json": { schema: this.table.zodSchema } },
        // todo we can pick the fields here based on user fields mapping
        description: "Data to insert in the table along with passwordConfirm"
      } },
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": {
            schema: external_exports.object({
              token: jwtTokenSchema,
              refresh_token: uidTokenSchema,
              verified: external_exports.boolean().optional().describe("Email verified."),
              record: this.table.zodSchema
              // todo we can pick the fields here based on user fields mapping
            })
          } }
        }
      }
    }),
    "/auth/login-password": () => ({
      description: "Login with password",
      request: { body: {
        required: true,
        content: { "application/json": { schema: external_exports.object({
          identity: defaultSchema.identity.describe("Email or username")
          // [this.mapping.password]: defaultSchema.password,
        }).or(external_exports.record(external_exports.string(), external_exports.unknown())) } },
        // todo we can pick the fields here based on user fields mapping
        description: "identity/email/username and password"
      } },
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": {
            schema: external_exports.object({
              token: jwtTokenSchema,
              refresh_token: uidTokenSchema,
              record: this.table.zodSchema
              // todo we can pick the fields here based on user fields mapping
            })
          } }
        }
      }
    }),
    "/auth/change-password": () => ({
      description: "Change password",
      request: { body: {
        required: true,
        content: { "application/json": { schema: external_exports.object({
          // [this.mapping.password]: defaultSchema.password,
        }).or(external_exports.record(external_exports.string(), external_exports.unknown())) } },
        // todo we can pick the fields here based on user fields mapping
        description: "The current password, new password and new password confirm and changes the password"
      } },
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": {
            schema: external_exports.object({
              success: external_exports.literal(true)
            })
          } }
        }
      }
    }),
    "/auth/request-password-reset": () => ({
      description: "Request password reset. Sends an email to the user with a token to reset the password. (doesn't require login)",
      request: {
        body: {
          required: true,
          content: { "application/json": { schema: external_exports.object({
            // email: defaultSchema.identity.describe('Email field'), // todo
          }).or(external_exports.record(external_exports.string(), external_exports.unknown())) } },
          description: "identity/email/username"
        }
      },
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": {
            schema: external_exports.object({ success: external_exports.literal(true) })
          } }
        }
      }
    }),
    "/auth/confirm-password-reset": () => ({
      description: "Confirm password reset. Sends an email to the user with a token to reset the password.",
      request: {
        body: {
          required: true,
          content: { "application/json": { schema: external_exports.object({
            token: uidTokenSchema
          }).and(external_exports.record(external_exports.string(), external_exports.unknown())) } },
          // todo password fields
          description: "token and new password and new password confirm"
        }
      },
      responses: {
        "200": {
          description: "Success",
          schema: external_exports.object({
            token: jwtTokenSchema,
            refresh_token: uidTokenSchema,
            record: this.table.zodSchema
            // todo we can pick the fields here based on user fields mapping
          })
        }
      }
    }),
    "/auth/request-verification": () => ({
      description: "Request email verification. Sends an email to the user with a token to verify. (requires login)",
      request: {},
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": {
            schema: external_exports.object({ success: external_exports.literal(true) })
          } }
        }
      }
    }),
    "/auth/confirm-verification": () => ({
      description: "Confirm email verification with token. Returns token and refresh token if not authenticated",
      request: {
        body: {
          required: true,
          content: { "application/json": { schema: external_exports.object({
            token: uidTokenSchema
          }) } },
          description: "jwt token received in the email"
        }
      },
      responses: {
        "200": {
          description: "Success",
          schema: external_exports.object({
            token: jwtTokenSchema.optional(),
            refresh_token: uidTokenSchema.optional(),
            record: this.table.zodSchema
            // todo we can pick the fields here based on user fields mapping
          })
        }
      }
    })
  };
  this.routes.push({
    method: "post",
    path: "/auth/login-token",
    handler: this.loginWithToken.bind(this),
    zod: routeZod["/auth/login-token"]
  });
  this.routes.push({
    method: "post",
    path: "/auth/refresh-token",
    handler: this.refreshToken.bind(this),
    zod: routeZod["/auth/refresh-token"]
  });
  this.routes.push({
    method: "post",
    path: "/auth/logout",
    handler: { raw: this.logout.bind(this) },
    zod: routeZod["/auth/logout"]
  });
  if (this.mapping.password) {
    this.routes.push({
      method: "post",
      path: "/auth/sign-up",
      handler: this.signUp.bind(this),
      zod: routeZod["/auth/sign-up"]
    });
    this.routes.push({
      method: "post",
      path: "/auth/login-password",
      handler: this.loginWithPassword.bind(this),
      zod: routeZod["/auth/login-password"]
    });
    this.routes.push({
      method: "post",
      path: "/auth/change-password",
      handler: { raw: this.changePassword.bind(this) },
      zod: routeZod["/auth/change-password"]
    });
    this.routes.push({
      method: "post",
      path: "/auth/request-password-reset",
      handler: { raw: this.requestPasswordReset.bind(this) },
      zod: routeZod["/auth/request-password-reset"]
    });
    this.routes.push({
      method: "post",
      path: "/auth/confirm-password-reset",
      handler: { raw: this.confirmPasswordReset.bind(this) },
      zod: routeZod["/auth/confirm-password-reset"]
    });
  }
  if (this.mapping.emailVerified) {
    this.routes.push({
      method: "post",
      path: "/auth/request-verification",
      handler: { raw: this.requestVerification.bind(this) },
      zod: routeZod["/auth/request-verification"]
    });
    this.routes.push({
      method: "post",
      path: "/auth/confirm-verification",
      handler: { raw: this.confirmVerification.bind(this) },
      zod: routeZod["/auth/confirm-verification"]
    });
  }
}
__name(setupTableAuthExtensionRoutes, "setupTableAuthExtensionRoutes");

// node_modules/teenybase/dist/worker/extensions/tableAuthExtension.js
var SALT_LENGTH = 20;
var _TableAuthExtension = class extends TableExtension {
  c;
  mapping;
  jwtSecret;
  // todo remove c from here
  constructor(data, table3, jc, c) {
    super(tableAuthDataSchema.parse(data), table3, jc);
    this.c = c;
    if (data.name !== _TableAuthExtension.name)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    if (!this.table.mapping.uid)
      throw new HTTPException(500, { message: "Invalid Configuration - id field required" });
    this.jwtSecret = this.table.$db.secretResolver.resolver(this.data.jwtSecret, true, `JWT_SECRET for ${data.name}`);
    const aud = this.table.fieldsUsage.auth_audience;
    this.mapping = {
      uid: this.table.mapping.uid,
      username: external_exports.string().optional().parse(this.table.fieldsUsage.auth_username),
      email: external_exports.string().optional().parse(this.table.fieldsUsage.auth_email),
      emailVerified: external_exports.string().optional().parse(this.table.fieldsUsage.auth_email_verified),
      password: external_exports.string().optional().parse(this.table.fieldsUsage.auth_password),
      passwordSalt: external_exports.string().optional().parse(this.table.fieldsUsage.auth_password_salt),
      name: external_exports.string().optional().parse(this.table.fieldsUsage.auth_name),
      avatar: external_exports.string().optional().parse(this.table.fieldsUsage.auth_avatar),
      audience: aud && !Array.isArray(aud) ? [external_exports.string().parse(aud)] : aud,
      metadata: external_exports.string().optional().parse(this.table.fieldsUsage.auth_metadata)
      // resetSentAt: z.string().optional().parse(this.table.fieldsUsage.auth_reset_sent_at),
      // verificationSentAt: z.string().optional().parse(this.table.fieldsUsage.auth_verification_sent_at),
    };
    if (this.mapping.emailVerified && !this.mapping.email)
      throw new HTTPException(500, { message: "Invalid Configuration - email field required for emailVerified" });
    if (this.mapping.passwordSalt && !this.mapping.password)
      throw new HTTPException(500, { message: "Invalid Configuration - passwordSalt field required for password" });
    setupTableAuthExtensionRoutes.call(this);
  }
  async onInsertParse(query) {
    const v = query.values;
    const records = Array.isArray(v) ? v : [v];
    for (const record of records) {
      await this._parsePasswordFieldsInsert(record);
      this._parseUsername(record);
      if (this.mapping.email)
        this._parseEmail(record);
      if (this.mapping.name)
        defaultSchema.name.parse(record[this.mapping.name]?.l, { path: [this.mapping.name] });
      if (this.mapping.emailVerified) {
        let val = defaultSchema.emailVerified.parse(record[this.mapping.emailVerified]?.l, { path: [this.mapping.emailVerified] });
        if (!this.jc.globals.auth?.admin) {
          if (val !== void 0)
            throw new HTTPException(400, { message: `${this.mapping.emailVerified} must not be set` });
          record[this.mapping.emailVerified] = { l: false };
        }
      }
    }
  }
  async onUpdateParse(query) {
    const record = query.set;
    await this._parsePasswordFieldUpdate(record, query);
  }
  async onDeleteParse(query, admin) {
    if (!admin)
      throw new HTTPException(400, { message: `Not allowed` });
  }
  async onSelectParse(query) {
  }
  async onViewParse(query) {
    return this.onSelectParse(query);
  }
  // why is this required? because this returns a token...
  async signUp(data) {
    if (!this.mapping.username || !this.mapping.password)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    const user = await this._createUser(data);
    const ret = {
      ...await this.createSession(user),
      record: this._userToFields(user)
    };
    if (this.mapping.emailVerified) {
      ret.verified = user.emailVerified;
      if (!user.emailVerified && this.data.autoSendVerificationEmail) {
        this.c.executionCtx.waitUntil(this._requestVerification(user));
      }
    }
    return ret;
  }
  async requestVerification() {
    if (!this.mapping.email || !this.mapping.emailVerified)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    const auth = this.jc.globals.auth;
    if (!auth?.uid)
      throw new HTTPException(403, { message: "Unauthorized" });
    if (auth.verified)
      throw new HTTPException(400, { message: "Already verified" });
    const user = await this.getUser(auth.uid);
    if (!user)
      throw new HTTPException(400, { message: "User not found" });
    await this._requestVerification(user);
    return this.c.json({ success: true });
  }
  confirmRequiresAuth = false;
  // todo make setting
  async confirmVerification() {
    const data = await this.table.$db.getRequestBody();
    if (!data)
      throw new HTTPException(400, { message: "Usage: POST /auth/confirm-verification {data} in JSON/FormData" });
    const token = uidTokenSchema.parse(data.token);
    if (!token)
      throw new HTTPException(400, { message: "Token required" });
    const auth = this.jc.globals.auth;
    if (this.confirmRequiresAuth && (!auth || !auth.uid || !auth.sid))
      throw new HTTPException(403, { message: "Unauthorized" });
    const uid = this.confirmRequiresAuth ? auth.uid : void 0;
    const user = await this._confirmVerification(token, uid);
    const ret = {
      ...!auth?.sid && await this.createSession(user),
      record: this._userToFields(user)
    };
    return this.c.json(ret);
  }
  async requestPasswordReset() {
    if (!this.mapping.email || !this.mapping.password)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    const data = await this.table.$db.getRequestBody();
    if (!data)
      throw new HTTPException(400, { message: "Usage: POST /auth/request-password-reset {data} in JSON/FormData" });
    const record = recordToSqlValues(data);
    const email = this._parseEmail(record);
    const user = await this.findUser(email, true);
    if (!user)
      throw new HTTPException(400, { message: "User not found" });
    const auth = this.jc.globals.auth;
    if (auth?.uid && (auth.uid !== user.id || auth.email !== email))
      throw new HTTPException(403, { message: "Unauthorized" });
    await this._requestPasswordReset(user);
    return this.c.json({ success: true });
  }
  async confirmPasswordReset() {
    if (!this.mapping.email || !this.mapping.password)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    const data = await this.table.$db.getRequestBody();
    if (!data)
      throw new HTTPException(400, { message: "Usage: POST /auth/confirm-password-reset {data} in JSON/FormData" });
    const token = uidTokenSchema.parse(data.token);
    if (!token)
      throw new HTTPException(400, { message: "Token required" });
    delete data.token;
    const record = recordToSqlValues(data);
    const password = await this._parsePasswordFieldsInsert(record);
    if (!password)
      throw new HTTPException(400, { message: "Invalid password" });
    const user = await this._confirmPasswordReset(token, record);
    const ret = {
      ...await this.createSession(user),
      record: this._userToFields(user)
    };
    return this.c.json(ret);
  }
  async loginWithPassword(data) {
    if (!this.mapping.password)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    if (!data)
      throw new HTTPException(400, { message: "Usage: POST /auth/login-password {data} in JSON" });
    const record = recordToSqlValues(data);
    const username = this.mapping.email && record[this.mapping.email] ? this._parseEmail(record) : record["identity"] ? defaultSchema.identity.parse(record["identity"].l, { path: ["identity"] }) : this._parseUsername(record);
    const invalid = /* @__PURE__ */ __name(async () => {
      await new Promise((r) => setTimeout(r, Math.random() * 200));
      return new HTTPException(400, { message: "Invalid username or password" });
    }, "invalid");
    const user = username ? await this.findUser(username, false, true) : null;
    if (!user)
      throw await invalid();
    const salt = user.passwordSalt || "";
    const password = await this._parsePasswordFieldsLogin(record, salt).catch((e) => {
      console.error(e);
      return null;
    });
    if (!password || password !== user.password)
      throw await invalid();
    const ret = {
      ...await this.createSession(user),
      record: this._userToFields(user)
    };
    if (this.mapping.emailVerified && !user.emailVerified)
      ret.verified = false;
    return ret;
  }
  /**
   * validates token from google, github etc or self(disabled for now) and creates a new session
   */
  async loginWithToken() {
    const tok = this.c.req.header("Authorization")?.replace(/^Bearer /, "");
    if (!tok)
      throw new HTTPException(400, { message: "Authorization header required" });
    const payload = await this.table.$db.jwt.decodeAuth(tok, await this.jwtSecret(), false).catch(() => null);
    if (!payload)
      throw new HTTPException(401, { message: "Unauthorized" });
    let res = await this.findUser(payload.sub, true);
    if (payload.iss !== this.table.$db.jwt.issuer) {
      if (payload.verified === false || payload.verified === 0)
        throw new HTTPException(400, { message: "Not verified" });
      if (!res)
        res = await this._createUserToken(payload.sub, true, payload?.issData);
    } else {
      throw new HTTPException(400, { message: "Use refresh-token endpoint instead" });
    }
    if (!res)
      throw new HTTPException(401, { message: "Unauthorized" });
    if (res.email !== payload.sub)
      throw new HTTPException(400, { message: "Invalid email" });
    const ret = {
      ...await this.createSession(res),
      record: this._userToFields(res)
    };
    if (this.mapping.emailVerified && !res.emailVerified)
      ret.verified = false;
    return ret;
  }
  async refreshToken(data) {
    const tok = this.c.req.header("Authorization")?.replace(/^Bearer /, "");
    if (!tok)
      throw new HTTPException(400, { message: "Authorization header required" });
    const payloadUntrusted = decode(tok).payload;
    if (payloadUntrusted.iss !== this.table.$db.jwt.issuer || !payloadUntrusted.sub || !payloadUntrusted.sid)
      throw new HTTPException(401, { message: "Invalid token" });
    const { sub, sid } = payloadUntrusted;
    const refreshToken = uidTokenSchema.parse(data.refresh_token);
    const sessionId = external_exports.string().min(10).parse(sid);
    let res = await this.findUser(sub, true);
    if (!res)
      throw new HTTPException(401, { message: "Unauthorized" });
    if (res.email !== sub)
      throw new HTTPException(400, { message: "Invalid email" });
    const token = await this.refreshSession(res, sessionId, refreshToken);
    const ret = {
      ...token,
      record: this._userToFields(res)
    };
    if (this.mapping.emailVerified && !res.emailVerified)
      ret.verified = false;
    return ret;
  }
  async changePassword() {
    if (!this.data.passwordType)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    const email = this.jc.globals.auth?.email;
    if (!this.jc.globals.auth?.uid || !email)
      throw new HTTPException(401, { message: "Unauthorized" });
    const data = await this.c.req.json();
    if (!data)
      throw new HTTPException(400, { message: "Usage: POST /auth/change-password {data} in JSON" });
    const record = recordToSqlValues(data);
    const res = await this.findUser(email, false, true);
    if (!res)
      throw new HTTPException(400, { message: "Invalid user" });
    const salt = res.passwordSalt || "";
    if (this.data.passwordCurrentSuffix) {
      let current = await this._parseCurrentPasswordField(record, salt);
      if (current !== res.password)
        throw new HTTPException(400, { message: "Invalid current password" });
    }
    const password = await this._parsePasswordFieldsInsert(record);
    if (!password)
      throw new HTTPException(400, { message: "Invalid password" });
    const res2 = await this.updateUser(res.id, record);
    if (!res2 || res2.id !== res.id)
      throw new HTTPException(500, { message: "Failed to update password" });
    const _token = await this._invalidateAllUserSessions(res.id);
    return this.c.json({ success: true });
  }
  async logout() {
    const auth = this.jc.globals.auth;
    if (!auth?.uid || !auth?.sid)
      throw new HTTPException(401, { message: "Unauthorized" });
    const sessionKey = this._kvSessionKey(
      /*user*/
      { id: auth.uid },
      auth.sid
    );
    await this.table.$db.kv.remove(sessionKey);
    return this.c.json({ success: true });
  }
  // todo
  // login with token
  // reset/forgot password
  // username change
  // username recovery
  // no point of this for this frontend, just use normal token. auth0 also says no point - https://auth0.com/blog/refresh-tokens-what-are-they-and-when-to-use-them/
  // actually useful to update meta and stuff
  // refresh token
  async _refreshSession(res, session) {
    const data = {
      cid: this.table.data.name,
      user: res.username,
      // todo: should this be added?
      sub: res.email,
      id: res.id,
      meta: res.metadata,
      sid: session.id
      // session id
      // admin: false,
    };
    if (res.audience && res.audience.length)
      data.aud = res.audience;
    if (res.emailVerified !== void 0)
      data.verified = res.emailVerified;
    const now = this.getTimestamp();
    const refreshToken = generateUid();
    session.tok = refreshToken;
    session.rc++;
    session.rat = now;
    const refreshTokenDuration = (
      /*this.data.refreshTokenDuration || */
      60 * 60 * 24 * 7
    );
    const sessionDuration = (
      /*this.data.sessionDuration || */
      60 * 60 * 24 * 30
    );
    session.exp = now + sessionDuration;
    const sessionKey = this._kvSessionKey(res, session.id);
    await this.table.$db.kv.setMultiple({
      [sessionKey]: JSON.stringify(session)
    }, refreshTokenDuration);
    const token = await this.table.$db.jwt.createJwtToken(data, await this.jwtSecret(), this.data.jwtTokenDuration);
    return {
      token,
      refresh_token: refreshToken
    };
  }
  getTimestamp() {
    return Math.floor(Date.now() / 1e3);
  }
  async createSession(user) {
    const now = this.getTimestamp();
    const session = {
      id: generateUid(),
      tok: "",
      // refresh token
      cid: this.table.name,
      uid: user.id,
      sub: user.email,
      rc: 0,
      // refresh count
      cat: now,
      // created at
      rat: now,
      // refreshed at
      exp: now
      // expires at (updated in refresh)
      // todo ip etc
    };
    return await this._refreshSession(user, session);
  }
  async refreshSession(user, id, token) {
    const sessionKey = this._kvSessionKey(user, id);
    const sessionStr = await this.table.$db.kv.get(sessionKey);
    const now = this.getTimestamp();
    let session = null;
    if (sessionStr) {
      try {
        session = JSON.parse(sessionStr);
      } catch (e) {
        console.error(e);
      }
    }
    const isValid2 = !!session && session.tok === token && session.uid === user.id && (!this.data.maxTokenRefresh || session.rc < this.data.maxTokenRefresh) && (session.exp === void 0 || session.exp > now);
    if (!isValid2 || !session)
      throw new HTTPException(401, { message: "Invalid session" });
    return await this._refreshSession(user, session);
  }
  async findUser(loginId, emailOnly = false, asAdmin = false) {
    const username = !emailOnly && this.mapping.username ? `${ident(this.mapping.username, this.jc)} = {:loginId}` : null;
    const email = this.mapping.email ? `${ident(this.mapping.email, this.jc)} = {:loginId}` : null;
    if (!username && !email)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    const res = await this.table.$db.rawSelect(this.table, {
      from: this.jc.tableName,
      where: {
        q: username && email ? `${username} OR ${email}` : email || username,
        p: { loginId }
      },
      selects: this._userFields(true, asAdmin),
      limit: 1,
      _readOnly: true
    })?.run() ?? [];
    return this._fieldsToUser(res[0], true);
  }
  async getUser(id) {
    const res = await this.table.$db.rawSelect(this.table, {
      from: this.jc.tableName,
      where: {
        q: `${ident(this.mapping.uid, this.jc)} = {:uid}`,
        p: { uid: id }
      },
      selects: this._userFields(),
      limit: 1,
      _readOnly: true
    })?.run() ?? [];
    return this._fieldsToUser(res[0]);
  }
  async updateUser(id, data) {
    const res = await this.table.$db.rawUpdate(this.table, {
      table: this.jc.tableName,
      where: {
        q: `${ident(this.mapping.uid, this.jc)} = {:uid}`,
        p: { uid: id }
      },
      set: data,
      returning: this._userFields()
    })?.run() ?? [];
    return this._fieldsToUser(res[0]);
  }
  async _createUser(data) {
    const res = await this.table.insert({ values: data, returning: this._userFields(false) }) ?? [];
    const user = res ? this._fieldsToUser(res[0]) : null;
    if (!user)
      throw new HTTPException(400, { message: "Unable to create user" });
    return user;
  }
  // todo we need to save id of the user from the external platform also.
  // this should only be used for auto user creation
  async _createUserToken(email, verified, externalData, record, values2) {
    if (!this.table.data.autoSetUid)
      throw new HTTPException(500, { message: "Invalid Configuration - autoSetUid required for auth extension" });
    const values = {
      ...record,
      ...values2,
      [this.mapping.uid]: { l: generateUid() }
    };
    if (this.mapping.email && email)
      values[this.mapping.email] = { l: email };
    if (this.mapping.emailVerified)
      values[this.mapping.emailVerified] = { l: verified };
    if (this.mapping.username)
      values[this.mapping.username] = { l: externalData.username || email?.split("@")[0].toLowerCase().replace(/[^a-z0-9_]/g, "") || "" };
    if (this.mapping.name)
      values[this.mapping.name] = { l: externalData.name || "User" };
    if (this.data.passwordType && this.mapping.password && !values[this.mapping.password]) {
      let pass = generateUid();
      const salt = this.mapping.passwordSalt ? randomString(SALT_LENGTH) : "";
      pass = await this._hashPassword(pass, salt);
      values[this.mapping.password] = { l: pass };
      if (this.mapping.passwordSalt)
        values[this.mapping.passwordSalt] = { l: salt };
    }
    const res = await this.table.$db.rawInsert(this.table, {
      table: this.jc.tableName,
      values,
      returning: this._userFields()
    })?.run() ?? [];
    return this._fieldsToUser(res[0]);
  }
  _fieldsToUser(res, asAdmin = false) {
    return res ? {
      id: res[this.mapping.uid],
      username: this.mapping.username ? res[this.mapping.username] : void 0,
      email: this.mapping.email ? res[this.mapping.email] : void 0,
      password: asAdmin && this.mapping.password ? res[this.mapping.password] : void 0,
      passwordSalt: asAdmin && this.mapping.passwordSalt ? res[this.mapping.passwordSalt] : void 0,
      emailVerified: this.mapping.emailVerified ? Boolean(res[this.mapping.emailVerified]) : void 0,
      audience: this.mapping.audience ? this.mapping.audience.map((f) => res[f]).filter((v) => v) : void 0,
      metadata: this.mapping.metadata ? JSON.parse(res[this.mapping.metadata]) : void 0
    } : null;
  }
  _userToFields(user) {
    const res = {
      [this.mapping.uid]: user.id
    };
    if (this.mapping.username)
      res[this.mapping.username] = user.username;
    if (this.mapping.email)
      res[this.mapping.email] = user.email;
    if (this.mapping.emailVerified)
      res[this.mapping.emailVerified] = user.emailVerified;
    if (this.mapping.metadata)
      res[this.mapping.metadata] = JSON.stringify(user.metadata);
    return res;
  }
  _userFields(identifier = true, asAdmin = false) {
    const f = [
      this.mapping.uid,
      this.mapping.username,
      this.mapping.email,
      this.mapping.password,
      this.mapping.passwordSalt,
      this.mapping.emailVerified,
      ...this.mapping.audience ?? [],
      this.mapping.metadata
    ].filter((v) => {
      const f2 = v ? this.table.fields[v] : void 0;
      return f2 && (!f2.noSelect || asAdmin);
    });
    const jc = !asAdmin ? this.jc : {
      ...this.jc,
      _checkColumns: !asAdmin
      // todo see if we can pass asAdmin(or something) and that would include the password columns
    };
    return !identifier ? f : f.map((v) => ident(v, jc));
  }
  _kvVerificationSentKey = (user) => "@email_verification_sent_at_" + this.table.name + user.id;
  _kvTokenKey = (token) => "@token_" + token;
  // + this.table.name + user.id
  _kvSessionKey = (user, id) => "@session_" + this.table.name + user.id + "_" + id;
  // + this.table.name + user.id
  _kvPasswordResetSentKey = (user) => "@password_reset_sent_at_" + this.table.name + user.id;
  async _invalidateAllUserSessions(userId) {
  }
  _getEmailVars() {
    return {
      APP_NAME: this.table.$db.settings.appName || "Dollar App",
      APP_URL: this.table.$db.settings.appUrl
      // todo add RECORD:* for record specific data(username, name, email, role etc) like in pocketbase
    };
  }
  async _requestVerification(user) {
    if (!this.mapping.emailVerified)
      throw new HTTPException(500, { message: "Invalid Configuration - emailVerified field required" });
    if (!this.mapping.email)
      throw new HTTPException(500, { message: "Invalid Configuration - email field required" });
    if (!user.email)
      throw new HTTPException(500, { message: "No user" });
    if (user.emailVerified)
      return;
    const verificationKey = this._kvVerificationSentKey(user);
    const emailVerifyEmailDuration = this.data.emailVerifyEmailDuration || 2 * 60;
    const res = await this.table.$db.kv.get(verificationKey, "(unixepoch(CURRENT_TIMESTAMP) - unixepoch(value))");
    if (res !== null && res < emailVerifyEmailDuration - 1) {
      throw new HTTPException(400, { message: "Verification email already sent" });
    }
    const token = generateUid();
    const email = this.table.$db.email;
    if (!email)
      throw new HTTPException(500, { message: "Email not configured" });
    const template = this.data.emailTemplates?.verification || {};
    await email.sendActionLink({
      subject: template.subject || "Verify your {{APP_NAME}} email",
      tags: ["email-verification", "table-" + this.table.name, ...template.tags || []],
      to: user.email,
      variables: {
        message_title: "Email Verification",
        message_description: "Thank you for joining us at {{APP_NAME}}. Click the button below to verify your email address.",
        message_footer: "If you did not request this, please ignore this email.",
        action_text: "Verify Email",
        action_link: "{{APP_URL}}/verify-email/{{TOKEN}}",
        ...template.variables,
        TOKEN: token,
        ...this._getEmailVars()
      }
    });
    const verificationTokenKey = this._kvTokenKey(token);
    const emailVerifyTokenDuration = this.data.emailVerifyTokenDuration || 1 * 60 * 60;
    await this.table.$db.kv.setMultiple({
      [verificationKey]: { sql: "CURRENT_TIMESTAMP" },
      [verificationTokenKey + token]: JSON.stringify({ id: user.id, sub: user.email, typ: "verify_email", cid: this.table.name })
    }, emailVerifyTokenDuration);
  }
  async _confirmVerification(token, uid) {
    if (!this.mapping.emailVerified)
      throw new HTTPException(500, { message: "Invalid Configuration - emailVerified field required" });
    const { id, sub } = await this._useToken(token, "verify_email");
    if (uid && uid !== id)
      throw new Error("User mismatch");
    const user = await this.findUser(sub, true);
    if (!user || user.id !== id)
      throw new HTTPException(400, { message: "Invalid user" });
    if (user.emailVerified)
      return user;
    const user2 = await this.updateUser(user.id, {
      [this.mapping.emailVerified]: { l: true }
    });
    if (!user2)
      throw new HTTPException(500, { message: "Failed to verify email" });
    return user2;
  }
  async _requestPasswordReset(user) {
    if (!this.mapping.password)
      throw new HTTPException(500, { message: "Invalid Configuration - password field required" });
    if (!user.email)
      throw new HTTPException(500, { message: "No user" });
    const resetKey = this._kvPasswordResetSentKey(user);
    const passwordResetEmailDuration = this.data.passwordResetEmailDuration || 2 * 60;
    const res = await this.table.$db.kv.get(resetKey, "(unixepoch(CURRENT_TIMESTAMP) - unixepoch(value))");
    if (res !== null && res < passwordResetEmailDuration - 1) {
      throw new Error("Password reset email already sent");
    }
    const token = generateUid();
    const email = this.table.$db.email;
    if (!email)
      throw new HTTPException(500, { message: "Email not configured" });
    const template = this.data.emailTemplates?.passwordReset || {};
    await email.sendActionLink({
      subject: template.subject || "Reset your {{APP_NAME}} password",
      tags: ["password-reset", "table-" + this.table.name, ...template.tags || []],
      to: user.email,
      variables: {
        message_title: "Password Reset",
        message_description: "Click the button below to reset the password for your {{APP_NAME}} account.",
        message_footer: "If you did not request this, you can safely ignore this email.",
        action_text: "Reset Password",
        action_link: "{{APP_URL}}/reset-password/{{TOKEN}}",
        ...template.variables,
        TOKEN: token,
        ...this._getEmailVars()
      }
    });
    const resetTokenKey = this._kvTokenKey(token);
    const passwordResetTokenDuration = this.data.passwordResetTokenDuration || 60 * 60;
    await this.table.$db.kv.setMultiple({
      [resetKey]: { sql: "CURRENT_TIMESTAMP" },
      [resetTokenKey + token]: JSON.stringify({ id: user.id, sub: user.email, typ: "reset_password", cid: this.table.name })
    }, passwordResetTokenDuration);
  }
  // record should have password, passwordSalt
  async _confirmPasswordReset(token, record) {
    if (!this.mapping.password)
      throw new HTTPException(500, { message: "Invalid Configuration - password field required" });
    const { id, sub } = await this._useToken(token, "reset_password");
    const user = await this.getUser(id);
    if (!user || user.id !== id)
      throw new HTTPException(400, { message: "Invalid user" });
    if (sub !== user.email)
      throw new HTTPException(400, { message: "Invalid email" });
    const data = {};
    if (this.mapping.passwordSalt) {
      const salt = record[this.mapping.passwordSalt];
      if (!salt.l)
        throw new HTTPException(500, { message: "Invalid salt" });
      data[this.mapping.passwordSalt] = salt;
    }
    data[this.mapping.password] = record[this.mapping.password];
    if (this.mapping.emailVerified && !user.emailVerified)
      data[this.mapping.emailVerified] = { l: true };
    const user2 = await this.updateUser(user.id, data);
    if (!user2)
      throw new HTTPException(500, { message: "Failed to verify email" });
    const _token = await this._invalidateAllUserSessions(user.id);
    return user2;
  }
  async _useToken(token, typ1) {
    const res = await this.table.$db.kv.pop(this._kvTokenKey(token));
    let parsed = null;
    try {
      parsed = res ? JSON.parse(res) : null;
    } catch (e) {
      console.error(e);
    }
    if (!parsed)
      throw new HTTPException(400, { message: "Invalid token" });
    const { id, sub, typ, cid } = parsed;
    if (!id || !sub)
      throw new HTTPException(400, { message: "Invalid token" });
    if (cid !== this.table.name)
      throw new HTTPException(400, { message: "Invalid table" });
    if (typ !== typ1)
      throw new HTTPException(400, { message: "Invalid token type" });
    return { id, sub };
  }
  async _hashPassword(password, salt) {
    if (!this.data.passwordType)
      return "";
    return passwordProcessors[this.data.passwordType].hash(password, salt);
  }
  _parseUsername(record) {
    if (!this.mapping.username)
      return;
    let val = record[this.mapping.username]?.l;
    if (typeof val !== "string")
      throw new HTTPException(400, { message: `${this.mapping.username} must be a value, expressions not support in username` });
    val = defaultSchema.username.parse(val, { path: [this.mapping.username] });
    record[this.mapping.username] = { l: val };
    return val;
  }
  _parseEmail(record) {
    if (!this.mapping.email)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    let val = record[this.mapping.email]?.l;
    if (typeof val !== "string")
      throw new HTTPException(400, { message: `${this.mapping.email} must be a value, expressions not support in email` });
    val = defaultSchema.email.parse(val, { path: [this.mapping.email] });
    if (this.data.normalizeEmail !== false) {
      try {
        val = normalizeEmail(val);
      } catch (e) {
        console.error(e);
        throw new HTTPException(400, { message: `Invalid ${this.mapping.email} format` });
      }
    }
    record[this.mapping.email] = { l: val };
    return val;
  }
  async _parseCurrentPasswordField(record, salt) {
    let current = record[this.mapping.password + this.data.passwordCurrentSuffix]?.l;
    if (!current || typeof current !== "string")
      throw new HTTPException(400, { message: `${this.mapping.password + this.data.passwordCurrentSuffix} is required` });
    current = defaultSchema.password.parse(current, { path: [this.mapping.password + this.data.passwordCurrentSuffix] });
    delete record[this.mapping.password + this.data.passwordCurrentSuffix];
    return await this._hashPassword(current, salt);
  }
  async _parsePasswordFieldUpdate(record, query, salt) {
    if (!this.data.passwordType)
      return;
    if (!this.mapping.password)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    let password = record[this.mapping.password]?.l;
    if (!password) {
      if (record[this.mapping.password])
        delete record[this.mapping.password];
      if (this.data.passwordConfirmSuffix && record[this.mapping.password + this.data.passwordConfirmSuffix])
        delete record[this.mapping.password + this.data.passwordConfirmSuffix];
      return;
    }
    const isAdmin = this.jc.globals.auth?.admin;
    if (this.data.passwordCurrentSuffix && !isAdmin) {
      if (!this.mapping.passwordSalt || salt) {
        let current = await this._parseCurrentPasswordField(record, salt || "");
        const currentQ = literalToQuery(current);
        const where = {
          q: `${ident(this.mapping.password, this.jc)} = ${currentQ.q}`,
          p: currentQ.p
        };
        appendWhere(query, where);
      } else {
        throw new HTTPException(400, { message: "Not supported, use change-password route(TBD)" });
      }
    }
    await this._parsePasswordFieldsInsert(record);
  }
  async _parsePasswordFieldsInsert(record) {
    if (this.data.passwordType) {
      const field = this.mapping.password;
      if (!field)
        throw new HTTPException(500, { message: "Invalid Configuration" });
      let val = record[field]?.l;
      if (!val)
        throw new HTTPException(400, { message: `${field} is required` });
      if (typeof val !== "string")
        throw new HTTPException(400, { message: `${field} must be a value, expressions not support in password` });
      val = defaultSchema.password.parse(val, { path: [field] });
      if (this.data.passwordConfirmSuffix) {
        const confirmVal = record[field + this.data.passwordConfirmSuffix]?.l;
        external_exports.literal(val, {
          // todo better error message
          errorMap: () => ({ message: `${field} and ${field + this.data.passwordConfirmSuffix} do not match` })
        }).parse(confirmVal, { path: [field + this.data.passwordConfirmSuffix] });
        if (val !== confirmVal)
          throw new HTTPException(400, { message: "unknown zod error" });
        delete record[field + this.data.passwordConfirmSuffix];
      }
      const salt = this.mapping.passwordSalt ? randomString(SALT_LENGTH) : "";
      val = await this._hashPassword(val, salt);
      record[field] = { l: val };
      if (this.mapping.passwordSalt)
        record[this.mapping.passwordSalt] = { l: salt };
      return record[field];
    } else if (this.mapping.password) {
      throw new HTTPException(500, { message: "Invalid Configuration" });
    }
    return null;
  }
  async _parsePasswordFieldsLogin(record, salt) {
    if (!this.data.passwordType)
      return;
    const field = this.mapping.password;
    if (!field)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    let val = record[field]?.l;
    if (typeof val !== "string")
      throw new HTTPException(400, { message: `${field} must be a value, expressions not support in password` });
    val = defaultSchema.password.parse(val, { path: [field] });
    val = await this._hashPassword(val, salt);
    record[field] = { l: val };
    return val;
  }
};
var TableAuthExtension = _TableAuthExtension;
__publicField(TableAuthExtension, "name", "auth");

// node_modules/teenybase/dist/worker/extensions/tableCrudExtention.js
var tableCrudExtensionDataSchema = external_exports.object({});
var _TableCrudExtension = class extends TableExtension {
  constructor(data, table3, jc) {
    super(data, table3, jc);
    if (data.name !== _TableCrudExtension.name)
      throw new HTTPException(500, { message: "Invalid Configuration" });
    const recordResponse = /* @__PURE__ */ __name((schema) => ({
      "200": {
        description: "Success",
        content: { "application/json": {
          schema: schema ?? this.table.zodSchema.or(external_exports.record(external_exports.string(), external_exports.unknown()))
        } }
      }
    }), "recordResponse");
    this.routes.push({
      handler: async (body, p) => await this.table.select(body) ?? [],
      path: "/select",
      method: "get",
      zod: () => ({
        description: "Select records",
        request: { query: tableSelectSchema },
        responses: recordResponse()
      })
    });
    this.routes.push({
      handler: async (body, p) => await this.table.select(body) ?? [],
      path: "/select",
      method: "post",
      zod: () => ({
        description: "Select records",
        request: { body: {
          required: true,
          content: { "application/json": { schema: tableSelectSchema } }
        } },
        responses: recordResponse()
      })
    });
    this.routes.push({
      handler: async (body, p) => await this.table.select(body, true) ?? [],
      path: "/list",
      method: "get",
      zod: () => ({
        description: "Select records with total count",
        request: { query: tableSelectSchema },
        responses: recordResponse(external_exports.object({
          items: external_exports.array(this.table.zodSchema.or(external_exports.record(external_exports.string(), external_exports.unknown()))),
          total: external_exports.number().min(0).or(external_exports.literal(-1))
        }))
      })
    });
    this.routes.push({
      handler: async (body, p) => await this.table.select(body, true) ?? [],
      path: "/list",
      method: "post",
      zod: () => ({
        description: "Select records with total count",
        request: { body: {
          required: true,
          content: { "application/json": { schema: tableSelectSchema } }
        } },
        responses: recordResponse(external_exports.object({
          items: external_exports.array(this.table.zodSchema.or(external_exports.record(external_exports.string(), external_exports.unknown()))),
          total: external_exports.number().min(0).or(external_exports.literal(-1))
        }))
      })
    });
    this.routes.push({
      handler: async (body, p) => await this.table.update(body) ?? [],
      path: "/update",
      method: "post",
      zod: () => ({
        description: "Update records",
        request: { body: {
          required: true,
          content: { "application/json": { schema: tableUpdateSchema } }
        } },
        responses: recordResponse()
      })
    });
    this.routes.push({
      handler: async (body, p) => await this.table.insert(body) ?? [],
      path: "/insert",
      method: "post",
      zod: () => ({
        description: "Insert records",
        request: { body: {
          required: true,
          content: { "application/json": { schema: tableInsertSchema } }
        } },
        responses: recordResponse()
      })
    });
    this.routes.push({
      handler: async (body, p) => await this.table.delete(body) ?? [],
      path: "/delete",
      method: "post",
      zod: () => ({
        description: "Delete records",
        request: { body: {
          required: true,
          content: { "application/json": { schema: tableDeleteSchema } }
        } },
        responses: recordResponse()
      })
    });
    if (this.table.fieldsUsage.record_uid) {
      this.routes.push({
        handler: async (body, p) => await this.table.view(body, external_exports.string().min(1).max(255).parse(p.id)) ?? void 0,
        path: "/view/:id",
        method: "get",
        zod: () => ({
          description: "View record",
          request: { params: external_exports.object({ id: external_exports.string().min(1).max(255) }), query: tableViewSchema },
          responses: recordResponse()
        })
      });
      this.routes.push({
        handler: async (body, p) => {
          const returningParam = this.table.$db.c.req.query("returning");
          return await this.table.edit({
            setValues: body,
            // todo add to schema and docs that it will return uid by default if not specified
            returning: returningParam || this.table.mapping.uid || "*",
            or: tableEditSchema.shape.or.parse(this.table.$db.c.req.query("or"))
          }, external_exports.string().min(1).max(255).parse(p.id));
        },
        path: "/edit/:id",
        method: "post",
        zod: () => ({
          description: "Edit record",
          request: {
            params: external_exports.object({ id: external_exports.string().min(1).max(255) }),
            body: {
              required: true,
              content: { "application/json": { schema: this.table.zodSchema.or(external_exports.record(external_exports.string(), external_exports.unknown())) } }
            },
            query: tableEditSchema
          },
          responses: recordResponse()
        })
      });
    }
  }
};
var TableCrudExtension = _TableCrudExtension;
__publicField(TableCrudExtension, "name", "crud");

// node_modules/teenybase/dist/worker/extensions/index.js
var extensions = {
  [TableRulesExtension.name]: TableRulesExtension,
  [TableAuthExtension.name]: TableAuthExtension,
  [TableCrudExtension.name]: TableCrudExtension
};

// node_modules/teenybase/dist/sql/parse/update.js
function parseUpdateQuery(q, jc) {
  const updateData = updateSchema.parse(q);
  if (!updateData.set && !updateData.setValues || updateData.set && updateData.setValues) {
    throw new Error("Update query must have either set or setValues");
  }
  const set = updateData.set ? recordToSqlExpressions(updateData.set, jc) : updateData.setValues ? recordToSqlValues(updateData.setValues) : {};
  if (!Object.keys(set).length)
    throw new Error("Update query must have set or setValues with at least one field");
  const contextWithNew = {
    ...jc,
    extras: {
      ...jc.extras,
      [UPDATE_NEW_COL_ID]: {
        table: jc.tableName,
        literals: set
      }
    }
  };
  const updateQuery = {
    table: jc.tableName,
    where: updateData.where ? queryToSqlQuery(updateData.where, contextWithNew) : void 0,
    returning: updateData.returning ? parseColumnList(updateData.returning, jc, true, true) : void 0,
    set,
    contextWithNew,
    or: updateData.or
    // join
  };
  return updateQuery;
}
__name(parseUpdateQuery, "parseUpdateQuery");

// node_modules/teenybase/dist/sql/parse/insert.js
function parseInsertQuery(q, jc) {
  const insertData = insertSchema.parse(q);
  if (!insertData.expr && !insertData.values || insertData.expr && insertData.values) {
    throw new Error("Insert query must have either values or expr");
  }
  const values = [];
  if (insertData.expr) {
    const v = Array.isArray(insertData.expr) ? insertData.expr : [insertData.expr];
    for (let i = 0; i < v.length; i++) {
      const data = v[i];
      if (!data)
        throw new Error("Insert query must have values or expr " + i);
      if (!values[i])
        values[i] = {};
      Object.assign(values[i], recordToSqlExpressions(data, jc));
    }
  } else if (insertData.values) {
    const v = Array.isArray(insertData.values) ? insertData.values : [insertData.values];
    for (let i = 0; i < v.length; i++) {
      const data = v[i];
      if (!data)
        throw new Error("Insert query must have values or expr " + i);
      if (!values[i])
        values[i] = {};
      Object.assign(values[i], recordToSqlValues(data));
    }
  }
  const insertQuery = {
    table: jc.tableName,
    returning: insertData.returning ? parseColumnList(insertData.returning, jc, true, true) : void 0,
    values,
    or: insertData.or
    // join
  };
  return insertQuery;
}
__name(parseInsertQuery, "parseInsertQuery");

// node_modules/teenybase/dist/sql/parse/select.js
function parseSelectQuery(q, jc) {
  const selectData = selectSchema.parse(q);
  const select = {
    selects: selectData.select ? parseColumnList(selectData.select, jc, true, true, true) : void 0,
    from: jc.tableName,
    where: selectData.where ? queryToSqlQuery(selectData.where, jc) : void 0,
    groupBy: selectData.group ? parseColumnList(selectData.group, jc, false, false) : void 0,
    orderBy: selectData.order ? parseColumnListOrder(selectData.order, jc) : void 0,
    limit: selectData.limit,
    offset: selectData.offset,
    distinct: selectData.distinct
    // having: selectData.having ? queryToD1Query(selectData.having, table, c) : undefined,
    // selectOption: selectData
    // join
  };
  let readOnly = !select.selects || select.selects?.every((s) => typeof s === "string" || s._readOnly);
  readOnly = readOnly && !!(Array.isArray(select.where) ? select.where.every((s) => !s.q || s._readOnly) : !select.where?.q || select.where?._readOnly);
  if (readOnly)
    select._readOnly = true;
  return select;
}
__name(parseSelectQuery, "parseSelectQuery");

// node_modules/teenybase/dist/sql/parse/delete.js
function parseDeleteQuery(q, jc) {
  const deleteData = deleteSchema.parse(q);
  const deleteQuery = {
    table: jc.tableName,
    where: deleteData.where ? queryToSqlQuery(deleteData.where, jc) : void 0,
    returning: deleteData.returning ? parseColumnList(deleteData.returning, jc, true, true) : void 0
    // join
  };
  return deleteQuery;
}
__name(parseDeleteQuery, "parseDeleteQuery");

// node_modules/hono/dist/router/linear-router/router.js
var emptyParams = /* @__PURE__ */ Object.create(null);
var splitPathRe = /\/(:\w+(?:{(?:(?:{[\d,]+})|[^}])+})?)|\/[^\/\?]+|(\?)/g;
var splitByStarRe = /\*/;
var LinearRouter = /* @__PURE__ */ __name(class {
  name = "LinearRouter";
  #routes = [];
  add(method, path, handler) {
    for (let i = 0, paths = checkOptionalParameter(path) || [path], len = paths.length; i < len; i++) {
      this.#routes.push([method, paths[i], handler]);
    }
  }
  match(method, path) {
    const handlers = [];
    ROUTES_LOOP:
      for (let i = 0, len = this.#routes.length; i < len; i++) {
        const [routeMethod, routePath, handler] = this.#routes[i];
        if (routeMethod === method || routeMethod === METHOD_NAME_ALL) {
          if (routePath === "*" || routePath === "/*") {
            handlers.push([handler, emptyParams]);
            continue;
          }
          const hasStar = routePath.indexOf("*") !== -1;
          const hasLabel = routePath.indexOf(":") !== -1;
          if (!hasStar && !hasLabel) {
            if (routePath === path || routePath + "/" === path) {
              handlers.push([handler, emptyParams]);
            }
          } else if (hasStar && !hasLabel) {
            const endsWithStar = routePath.charCodeAt(routePath.length - 1) === 42;
            const parts = (endsWithStar ? routePath.slice(0, -2) : routePath).split(splitByStarRe);
            const lastIndex = parts.length - 1;
            for (let j = 0, pos = 0, len2 = parts.length; j < len2; j++) {
              const part = parts[j];
              const index = path.indexOf(part, pos);
              if (index !== pos) {
                continue ROUTES_LOOP;
              }
              pos += part.length;
              if (j === lastIndex) {
                if (!endsWithStar && pos !== path.length && !(pos === path.length - 1 && path.charCodeAt(pos) === 47)) {
                  continue ROUTES_LOOP;
                }
              } else {
                const index2 = path.indexOf("/", pos);
                if (index2 === -1) {
                  continue ROUTES_LOOP;
                }
                pos = index2;
              }
            }
            handlers.push([handler, emptyParams]);
          } else if (hasLabel && !hasStar) {
            const params = /* @__PURE__ */ Object.create(null);
            const parts = routePath.match(splitPathRe);
            const lastIndex = parts.length - 1;
            for (let j = 0, pos = 0, len2 = parts.length; j < len2; j++) {
              if (pos === -1 || pos >= path.length) {
                continue ROUTES_LOOP;
              }
              const part = parts[j];
              if (part.charCodeAt(1) === 58) {
                let name = part.slice(2);
                let value;
                if (name.charCodeAt(name.length - 1) === 125) {
                  const openBracePos = name.indexOf("{");
                  const pattern = name.slice(openBracePos + 1, -1);
                  const restPath = path.slice(pos + 1);
                  const match = new RegExp(pattern, "d").exec(restPath);
                  if (!match || match.indices[0][0] !== 0 || match.indices[0][1] === 0) {
                    continue ROUTES_LOOP;
                  }
                  name = name.slice(0, openBracePos);
                  value = restPath.slice(...match.indices[0]);
                  pos += match.indices[0][1] + 1;
                } else {
                  let endValuePos = path.indexOf("/", pos + 1);
                  if (endValuePos === -1) {
                    if (pos + 1 === path.length) {
                      continue ROUTES_LOOP;
                    }
                    endValuePos = path.length;
                  }
                  value = path.slice(pos + 1, endValuePos);
                  pos = endValuePos;
                }
                params[name] ||= value;
              } else {
                const index = path.indexOf(part, pos);
                if (index !== pos) {
                  continue ROUTES_LOOP;
                }
                pos += part.length;
              }
              if (j === lastIndex) {
                if (pos !== path.length && !(pos === path.length - 1 && path.charCodeAt(pos) === 47)) {
                  continue ROUTES_LOOP;
                }
              }
            }
            handlers.push([handler, params]);
          } else if (hasLabel && hasStar) {
            throw new UnsupportedPathError();
          }
        }
      }
    return [handlers];
  }
}, "LinearRouter");

// node_modules/teenybase/dist/worker/util/string.js
var maxFileNameLength = 100 - 7;
function normalizeFileName(name, suffix) {
  const split = name.split(".");
  const originalExt = split.length > 1 ? split.pop() : "";
  let cleanExt = originalExt.replace(/[^\w\.\*\-_\+\=\#]+/g, "");
  if (!cleanExt)
    cleanExt = "dat";
  let cleanName = Snakecase(split.join(".").replace(/[^a-zA-Z0-9_\.]/g, "_"));
  if (cleanName.length < 3) {
    cleanName += randomString(5);
  } else if (cleanName.length > maxFileNameLength) {
    cleanName = cleanName.substring(0, maxFileNameLength);
  }
  return `${cleanName}${suffix ?? "_" + randomString(10)}.${cleanExt}`;
}
__name(normalizeFileName, "normalizeFileName");
var snakecaseSplitRegex = "[W_]+";
function Snakecase(str) {
  let result = "";
  const words = str.split(new RegExp(snakecaseSplitRegex, "g"));
  words.forEach((word) => {
    if (word == "")
      return;
    if (result.length > 0)
      result += "_";
    for (let i = 0; i < word.length; i++) {
      const c = word[i];
      if (c >= "A" && c <= "Z" && i > 0 && !(word[i - 1] > "A" && word[i - 1] < "Z")) {
        result += "_";
      }
      result += c;
    }
  });
  return result.toLowerCase();
}
__name(Snakecase, "Snakecase");

// node_modules/teenybase/dist/types/dataTypes.js
var TableFieldDataType;
(function(TableFieldDataType2) {
  TableFieldDataType2["text"] = "text";
  TableFieldDataType2["number"] = "number";
  TableFieldDataType2["bool"] = "bool";
  TableFieldDataType2["email"] = "email";
  TableFieldDataType2["url"] = "url";
  TableFieldDataType2["editor"] = "editor";
  TableFieldDataType2["date"] = "date";
  TableFieldDataType2["select"] = "select";
  TableFieldDataType2["json"] = "json";
  TableFieldDataType2["file"] = "file";
  TableFieldDataType2["relation"] = "relation";
  TableFieldDataType2["password"] = "password";
  TableFieldDataType2["integer"] = "integer";
  TableFieldDataType2["blob"] = "blob";
})(TableFieldDataType || (TableFieldDataType = {}));
var TableFieldSqlDataType0;
(function(TableFieldSqlDataType02) {
  TableFieldSqlDataType02["text"] = "text";
  TableFieldSqlDataType02["integer"] = "integer";
  TableFieldSqlDataType02["real"] = "real";
  TableFieldSqlDataType02["blob"] = "blob";
  TableFieldSqlDataType02["null"] = "null";
})(TableFieldSqlDataType0 || (TableFieldSqlDataType0 = {}));
var TableFieldSqlDataType1;
(function(TableFieldSqlDataType12) {
  TableFieldSqlDataType12["json"] = "json";
  TableFieldSqlDataType12["date"] = "date";
  TableFieldSqlDataType12["datetime"] = "datetime";
  TableFieldSqlDataType12["time"] = "time";
  TableFieldSqlDataType12["timestamp"] = "timestamp";
  TableFieldSqlDataType12["float"] = "float";
  TableFieldSqlDataType12["int"] = "int";
  TableFieldSqlDataType12["boolean"] = "boolean";
  TableFieldSqlDataType12["numeric"] = "numeric";
})(TableFieldSqlDataType1 || (TableFieldSqlDataType1 = {}));

// node_modules/teenybase/dist/types/zod/dataTypesSchemas.js
var tableFieldTypeToZod = {
  text: external_exports.string(),
  number: external_exports.number(),
  bool: external_exports.boolean(),
  email: external_exports.string().email(),
  url: external_exports.string().url(),
  editor: external_exports.string(),
  date: external_exports.string(),
  datetime: external_exports.string(),
  time: external_exports.string(),
  timestamp: external_exports.string(),
  json: external_exports.record(external_exports.any()),
  // file: z.instanceof(File),
  file: external_exports.string(),
  // relation: z.string(),
  // autodate: z.string(),
  integer: external_exports.number().int(),
  real: external_exports.number(),
  blob: external_exports.string(),
  float: external_exports.number(),
  int: external_exports.number().int(),
  boolean: external_exports.boolean(),
  numeric: external_exports.number()
};
var sqlDataTypeToDataTypeDefaults = {
  [TableFieldSqlDataType0.text]: TableFieldDataType.text,
  [TableFieldSqlDataType0.integer]: TableFieldDataType.integer,
  [TableFieldSqlDataType0.real]: TableFieldDataType.number,
  [TableFieldSqlDataType0.blob]: TableFieldDataType.blob,
  [TableFieldSqlDataType0.null]: TableFieldDataType.text,
  [TableFieldSqlDataType1.json]: TableFieldDataType.json,
  [TableFieldSqlDataType1.date]: TableFieldDataType.date,
  [TableFieldSqlDataType1.datetime]: TableFieldDataType.date,
  [TableFieldSqlDataType1.time]: TableFieldDataType.date,
  [TableFieldSqlDataType1.timestamp]: TableFieldDataType.date,
  [TableFieldSqlDataType1.float]: TableFieldDataType.number,
  [TableFieldSqlDataType1.int]: TableFieldDataType.integer,
  [TableFieldSqlDataType1.boolean]: TableFieldDataType.bool,
  [TableFieldSqlDataType1.numeric]: TableFieldDataType.number
};
var dataTypeToSqlDataType = Object.fromEntries(Object.entries(sqlDataTypeToDataTypeDefaults).map(([k, v]) => [v, k]));
var sqlDataTypeAliases = {
  [TableFieldSqlDataType0.text]: TableFieldSqlDataType0.text,
  [TableFieldSqlDataType0.integer]: TableFieldSqlDataType0.integer,
  [TableFieldSqlDataType0.real]: TableFieldSqlDataType0.real,
  [TableFieldSqlDataType0.blob]: TableFieldSqlDataType0.blob,
  [TableFieldSqlDataType0.null]: TableFieldSqlDataType0.null,
  [TableFieldSqlDataType1.json]: TableFieldSqlDataType0.text,
  [TableFieldSqlDataType1.date]: TableFieldSqlDataType0.text,
  [TableFieldSqlDataType1.datetime]: TableFieldSqlDataType0.text,
  [TableFieldSqlDataType1.time]: TableFieldSqlDataType0.text,
  [TableFieldSqlDataType1.timestamp]: TableFieldSqlDataType0.text,
  [TableFieldSqlDataType1.float]: TableFieldSqlDataType0.real,
  [TableFieldSqlDataType1.int]: TableFieldSqlDataType0.integer,
  [TableFieldSqlDataType1.boolean]: TableFieldSqlDataType0.integer,
  [TableFieldSqlDataType1.numeric]: TableFieldSqlDataType0.real
};
var supportedTypesForSql = {
  [TableFieldSqlDataType0.text]: [TableFieldDataType.text, TableFieldDataType.json, TableFieldDataType.date, TableFieldDataType.file, TableFieldDataType.editor, TableFieldDataType.select, TableFieldDataType.email, TableFieldDataType.url, TableFieldDataType.relation],
  [TableFieldSqlDataType0.integer]: [TableFieldDataType.number, TableFieldDataType.integer, TableFieldDataType.bool, TableFieldDataType.select, TableFieldDataType.relation],
  [TableFieldSqlDataType0.real]: [TableFieldDataType.number, TableFieldDataType.select, TableFieldDataType.relation],
  [TableFieldSqlDataType0.blob]: [TableFieldDataType.blob],
  [TableFieldSqlDataType0.null]: [TableFieldDataType.text]
};

// node_modules/teenybase/dist/worker/$Table.js
var $Table = class {
  data;
  jc;
  $db;
  extensions = [];
  fileFields;
  // jsonFields?: string[]
  // editorFields?: string[]
  mapping;
  fields;
  /**
   * Maps usage strings to field name/array of field names(for multiple)
   */
  fieldsUsage;
  autoDeleteR2Files;
  allowMultipleFileRef;
  allowWildcard;
  // this is allow direct wildcard in select/returning instead of expanding it automatically. todo maybe this should be renamed
  extension(key) {
    const ext = this.extensions.find((e) => e.name === key);
    if (!ext)
      throw new ProcessError("Extension not found", 500);
    return ext;
  }
  get name() {
    return this.data.name;
  }
  // get id(){
  //     return this.data.id
  // }
  constructor(data, jc, $db) {
    this.data = data;
    this.jc = jc;
    this.$db = $db;
    this.fieldsUsage = data.fields.reduce((acc, f) => {
      if (!f.usage)
        return acc;
      let v = acc[f.usage];
      if (!v)
        v = f.name;
      else if (Array.isArray(v))
        v.push(f.name);
      else
        v = [v, f.name];
      acc[f.usage] = v;
      return acc;
    }, {});
    if (Array.isArray(this.fieldsUsage.record_uid))
      throw new ProcessError("Multiple fields for record_uid not supported", 500);
    if (Array.isArray(this.fieldsUsage.record_created))
      throw new ProcessError("Multiple fields for record_created not supported", 500);
    if (Array.isArray(this.fieldsUsage.record_updated))
      throw new ProcessError("Multiple fields for record_updated not supported", 500);
    this.mapping = {
      uid: external_exports.string().optional().parse(this.fieldsUsage.record_uid),
      // uid. this is for unique id(used in view route, auth etc).
      created: external_exports.string().optional().parse(this.fieldsUsage.record_created),
      // created
      updated: external_exports.string().optional().parse(this.fieldsUsage.record_updated)
      // updated
    };
    this.allowWildcard = data.allowWildcard ?? false;
    this.fields = Object.fromEntries(this.data.fields.map((f) => [f.name, f]));
    this.fileFields = this.data.fields.filter((f) => f.type === "file").map((f) => f.name);
    this.extensions.push(new TableCrudExtension({ name: "crud" }, this, jc));
    for (const ext of data.extensions) {
      const extClass = extensions[ext.name];
      if (extClass)
        this.extensions.push(new extClass(ext, this, jc, $db.c));
      else
        throw new ProcessError("Invalid extension " + ext.name + " for table " + data.name, 500);
    }
    if (this.data.idInR2 && (!this.mapping.uid || !this.fields[this.mapping.uid].noUpdate))
      throw new ProcessError("Invalid Configuration for idInR2 - uid field must be present and set to noUpdate", 500);
    this.autoDeleteR2Files = this.data.autoDeleteR2Files !== void 0 ? this.data.autoDeleteR2Files : true;
    this.allowMultipleFileRef = this.data.allowMultipleFileRef !== void 0 ? this.data.allowMultipleFileRef : false;
    if (this.allowMultipleFileRef && this.data.idInR2)
      throw new ProcessError("Invalid Configuration for idInR2 - allowMultipleFileRef cannot be true", 500);
    if (this.allowMultipleFileRef && this.autoDeleteR2Files)
      throw new ProcessError("Invalid Configuration for autoDeleteR2Files - allowMultipleFileRef cannot be true", 500);
  }
  // setup db etc
  async setup(version2) {
    return this;
  }
  // todo why is initialize required?
  // if it needs to be initialized then wait for it in any function call.
  initialize() {
    for (const ext of this.extensions) {
      ext.initialize && ext.initialize();
    }
    return this;
  }
  // crud
  async edit(data, id) {
    return await (await this.rawEdit(data, id))?.run();
  }
  async view(data, id) {
    return await (await this.rawView(data, id))?.run();
  }
  async select(data, countTotal) {
    return typeof countTotal === "boolean" ? await (await this.rawSelect(data, countTotal))?.run() : await (await this.rawSelect(data, countTotal))?.run();
  }
  async selectCount(data) {
    return await (await this.rawSelectCount(data))?.run();
  }
  async selectRaise(data) {
    return await (await this.rawSelectRaise(data))?.run();
  }
  async update(data, then) {
    return await (await this.rawUpdate(data, then))?.run();
  }
  async insert(data, then) {
    return await (await this.rawInsert(data, then))?.run();
  }
  async delete(data, then) {
    return await (await this.rawDelete(data, then))?.run();
  }
  async rawDelete(data, then) {
    let query;
    try {
      query = parseDeleteQuery(data, this.jc);
    } catch (e) {
      throw new ProcessError("Error parsing DELETE data", 400, { input: data }, e);
    }
    await this.onDeleteParse(query);
    const fileFields = this.fileFields;
    const res = this.$db.rawDelete(this, query, fileFields, then);
    return res;
  }
  async rawInsert(data, then) {
    const values = Array.isArray(data.values) ? data.values : data.values ? [data.values] : void 0;
    let filesToUpload = {};
    let filesToRef = [];
    const data2 = {
      ...data,
      values: []
    };
    if (values) {
      for (const setValues of values) {
        if (!setValues)
          continue;
        this.checkNewRecordValues(setValues);
        const { values: _values } = this.filesToUpload(setValues, filesToUpload, filesToRef);
        data2.values.push(_values);
      }
    }
    let query;
    try {
      query = parseInsertQuery(data2, this.jc);
    } catch (e) {
      throw new ProcessError("Error parsing INSERT data", 400, data, e);
    }
    await this.onInsertParse(query);
    const values0 = Array.isArray(data2.values) ? data2.values[0] : data2.values;
    const fileFields = values0 && this.fileFields?.filter((f) => values0[f] !== void 0);
    const res = this.$db.rawInsert(this, query, filesToUpload, filesToRef, fileFields, then);
    return res;
  }
  async rawUpdate(data, then) {
    const set = data.set;
    if (set && this.fileFields)
      for (const [key, val] of Object.entries(set)) {
        if (this.fileFields.includes(key))
          throw new ProcessError("File fields can only be set using setValues");
      }
    this.checkNewRecordValues(data.setValues);
    const { filesToUpload, filesToRef, values } = data.setValues ? this.filesToUpload(data.setValues) : {};
    const data2 = {
      ...data,
      setValues: values
    };
    let updateQuery;
    try {
      updateQuery = parseUpdateQuery(data2, this.jc);
    } catch (e) {
      throw new ProcessError("Error parsing UPDATE data", 400, data, e);
    }
    await this.onUpdateParse(updateQuery);
    const fileFields = this.fileFields?.filter((f) => updateQuery.set[f] !== void 0);
    const res = this.$db.rawUpdate(this, updateQuery, filesToUpload, filesToRef, [], fileFields, then);
    return res;
  }
  async rawView(data, id) {
    if (!this.mapping.uid)
      throw new HTTPException(404, { message: "Not supported without uidField." });
    let query;
    try {
      query = parseSelectQuery({
        where: `${this.data.name}.${this.mapping.uid}=${JSON.stringify(id)}` + (data.where ? `& (${data.where})` : ""),
        limit: 1,
        select: data.select
      }, this.jc);
    } catch (e) {
      throw new ProcessError("Error parsing SELECT(view) data", 400, data, e);
    }
    await this.onViewParse(query, id);
    const res = this.$db.rawSelect(this, query, (r) => r?.length ? r[0] : null);
    return res;
  }
  async rawEdit(data, id) {
    if (!this.mapping.uid)
      throw new HTTPException(404, { message: "Not supported without uidField." });
    const res = data.or !== "INSERT" ? await this.rawUpdate({
      where: `${this.data.name}.${this.mapping.uid}=${JSON.stringify(id)}`,
      setValues: data.setValues,
      returning: data.returning,
      or: data.or
    }, (r) => r?.length ? r[0] : null) : await this.rawInsert({
      values: {
        ...data.setValues,
        [this.mapping.uid]: id
      },
      returning: data.returning,
      or: "REPLACE"
    }, (r) => r?.length ? r[0] : null);
    return res;
  }
  async rawSelect(data, countTotal) {
    let query;
    try {
      query = parseSelectQuery(data, this.jc);
    } catch (e) {
      throw new ProcessError("Error parsing SELECT data", 400, data, e);
    }
    await this.onSelectParse(query);
    if (countTotal === void 0 || typeof countTotal === "function")
      return this.$db.rawSelect(this, query, countTotal);
    return this.$db.rawSelect(this, query, countTotal);
  }
  async rawSelectCount(data) {
    let query;
    try {
      query = parseSelectQuery(data, this.jc);
    } catch (e) {
      throw new ProcessError("Error parsing SELECT data", 400, data, e);
    }
    await this.onSelectParse(query);
    if (query.selects?.length ?? 0 > 1)
      throw new ProcessError("Invalid select count query, only 1 field allowed");
    const countField = query.selects?.length === 1 ? query.selects[0] : this.mapping.uid ? `${this.data.name}.${columnify(this.mapping.uid)}` : "*";
    const res = this.$db.rawSelect(this, {
      ...query,
      selects: [`count(${countField}) as total`],
      limit: void 0,
      offset: void 0,
      orderBy: void 0,
      groupBy: void 0,
      distinct: false
    }, (r) => r?.length ? r[0].total : -1);
    return res;
  }
  async rawSelectRaise(data) {
    const { message, code } = external_exports.object({
      message: external_exports.string(),
      code: external_exports.enum(["ROLLBACK", "ABORT", "FAIL"]).optional().default("FAIL")
    }).parse(data);
    const data2 = {
      ...data,
      select: `RAISE(${code}, ${JSON.stringify(message)})`
    };
    let query;
    try {
      query = parseSelectQuery(data2, this.jc);
    } catch (e) {
      throw new ProcessError("Error parsing SELECT data", 400, data, e);
    }
    await this.onSelectParse(query);
    const res = this.$db.rawSelect(this, query, (r) => {
      if (r.length)
        throw new ProcessError(message, 409, { code });
      return null;
    });
    return res;
  }
  // hooks
  async onInsertParse(query) {
    let v = Array.isArray(query.values) ? query.values : [query.values];
    if (v.length && v[0]) {
      const setKeys = Object.keys(v[0]);
      for (const key of setKeys) {
        const field = this.fields[key];
        if (!field)
          continue;
        if (field.noInsert)
          throw new ProcessError("Cannot insert " + key + " field", this.jc.globals.auth?.uid ? 403 : 401);
      }
      if (this.mapping.uid && this.data.autoSetUid) {
        for (const val of v) {
          if (!val[this.mapping.uid])
            val[this.mapping.uid] = { l: generateUid() };
        }
      }
    }
    if (query.returning)
      query.returning = this.checkColsWildcard(Array.isArray(query.returning) ? query.returning : [query.returning]);
    for (const ext of this.extensions) {
      ext.onInsertParse && await ext.onInsertParse(query);
    }
    v = Array.isArray(query.values) ? query.values : [query.values];
    if (v.length && v[0]) {
      const setKeys = Object.keys(v[0]);
      for (const key of setKeys) {
        const field = this.fields[key];
        if (!field)
          throw new ProcessError("Invalid field " + key);
      }
    }
  }
  async onDeleteParse(query) {
    if (query.returning)
      query.returning = this.checkColsWildcard(Array.isArray(query.returning) ? query.returning : [query.returning]);
    for (const ext of this.extensions) {
      ext.onDeleteParse && await ext.onDeleteParse(query, this.jc.globals.auth?.admin ?? false);
    }
  }
  async onUpdateParse(query) {
    let setKeys = Object.keys(query.set);
    for (const key of setKeys) {
      const field = this.fields[key];
      if (!field)
        continue;
      if (field.noUpdate)
        throw new ProcessError("Cannot update " + key + " field", this.jc.globals.auth?.uid ? 403 : 401);
    }
    if (this.mapping.updated)
      query.set[this.mapping.updated] = { q: "CURRENT_TIMESTAMP" };
    if (query.returning)
      query.returning = this.checkColsWildcard(Array.isArray(query.returning) ? query.returning : [query.returning]);
    for (const ext of this.extensions) {
      ext.onUpdateParse && await ext.onUpdateParse(query);
    }
    setKeys = Object.keys(query.set);
    for (const key of setKeys) {
      const field = this.fields[key];
      if (!field)
        throw new ProcessError("Invalid field " + key);
    }
  }
  async onSelectParse(query) {
    const allowSubqueries = true;
    query.selects = this.checkColsWildcard(Array.isArray(query.selects) ? query.selects : [query.selects || "*"], allowSubqueries);
    this.handleSelectDeps(query);
    for (const ext of this.extensions) {
      ext.onSelectParse && await ext.onSelectParse(query);
    }
    await this.handleSelectSubQueries(query, allowSubqueries);
  }
  async onViewParse(query, id) {
    const allowSubqueries = true;
    query.selects = this.checkColsWildcard(Array.isArray(query.selects) ? query.selects : [query.selects || "*"], allowSubqueries);
    this.handleSelectDeps(query);
    for (const ext of this.extensions) {
      ext.onViewParse && await ext.onViewParse(query, id);
    }
    await this.handleSelectSubQueries(query, allowSubqueries);
  }
  handleSelectDeps(query) {
    const allQueries = [query.where, query.having].flat();
    for (const sqlQuery of allQueries) {
      if (!sqlQuery)
        continue;
      const deps = sqlQuery.dependencies;
      if (!deps?.length)
        continue;
      for (const dep of deps) {
        if (dep.type === "fts") {
          const { table: table3, column } = dep;
          if (table3 !== this.jc.tableName)
            throw new ProcessError("Invalid FTS dependency table " + table3);
          if (!this.data.fullTextSearch || this.data.fullTextSearch.enabled === false)
            throw new ProcessError("FTS not available or disabled on table " + table3);
          if (column && !this.data.fullTextSearch.fields.map((f) => columnify(f)).includes(column))
            throw new ProcessError("Invalid FTS column " + column);
          const content_rowid = this.data.fullTextSearch.content_rowid ?? "rowid";
          const ftsTable = columnify(fts5TableName(this.name));
          const join = {
            table: ftsTable,
            on: { q: `${columnify(this.name)}.${content_rowid} = ${ftsTable}.rowid` }
          };
          appendJoin(query, join);
          appendOrderBy(query, `${ftsTable}.rank`);
          continue;
        }
        throw new ProcessError("Invalid SQLQuery dependency type " + dep.type);
      }
    }
  }
  async handleSelectSubQueries(query, allowSubqueries) {
    const subQueries = getSubSelectQueries(query);
    for (const subQuery of subQueries) {
      if (!allowSubqueries)
        throw new ProcessError("Subqueries not allowed");
      if (typeof subQuery.from !== "string")
        throw new ProcessError("Subquery from must be a string");
      const table3 = this.$db.table(uncolumnify(subQuery.from));
      if (!table3)
        throw new ProcessError("Subquery table not found");
      await table3.onSelectParse(subQuery);
    }
  }
  checkNewRecordValues(setValues) {
    if (!setValues)
      return;
    for (const [key, val] of Object.entries(setValues)) {
      if (Array.isArray(val))
        throw new ProcessError("Array values not supported at the moment");
      const field = this.fields[key];
      if (!field)
        continue;
      const directNullableTypes = ["file", "number", "bool", "email", "url", "date", "json", "integer", "blob"];
      if (directNullableTypes.includes(field.type) && val === "null") {
        setValues[key] = null;
        continue;
      }
      if (field.type === "json") {
        if (typeof val === "string" && val !== "") {
          try {
            const l = JSON.parse(val);
            if (l === null)
              setValues[key] = l;
          } catch (e) {
            throw new ProcessError("Invalid JSON value for " + key);
          }
        }
      }
    }
  }
  // D1 Helpers
  parseD1Error(e) {
    const msg = e?.errorMessage;
    const errorMap2 = {
      "UNIQUE constraint failed": "A record with this value already exists.",
      "NOT NULL constraint failed": "This field cannot be NULL.",
      // 'FOREIGN KEY constraint failed': 'Unable to find related record (Foreign Key).',
      "FOREIGN KEY constraint failed": "Foreign Key constraint failed."
    };
    const parts = msg.split(":").map((p) => p.trim());
    const column = parts.find((p) => {
      const c = p.split(".").pop();
      return c && this.fields[c];
    })?.split(".").pop();
    const mess = parts[0];
    if (column) {
      const code = parts.pop();
      e.data = {
        [column]: {
          code,
          message: errorMap2[mess] ?? mess
        }
      };
    } else if (errorMap2[mess]) {
      e.message += " - " + errorMap2[mess];
    }
    return e;
  }
  // R2 Helpers
  // private async filesToDelete(desQuery: UpdateQuery|DeleteQuery, fileFields?: string[]) {
  //     if(!fileFields) fileFields = this.fileFields || []
  //     if (!fileFields.length) return undefined
  //     if(desQuery.table !== this.jc.tableName) throw new ProcessError('Invalid table for filesToDelete')
  //     const selects = fileFields.map(f => ident(f, this.jc))
  //     // const res = await this.run<any>(selectQuery, 'Failed to run select query')
  //     const res = await this.$db.rawSelect(this, {
  //         from: desQuery.table,
  //         where: desQuery.where, // this will have the rule as well.
  //         selects,
  //         // limit: desQuery.limit,
  //         params: desQuery.params,
  //     })?.run() || []
  //     return res.flatMap(r => Object.values(r)).filter(v => !!v) as string[]
  // }
  // returning is not used, todo remove?
  filesToUpload(values, filesToUpload, filesToRef, returning) {
    filesToUpload = filesToUpload ?? {};
    filesToRef = filesToRef ?? [];
    returning = returning ?? [];
    if (!values || !this.fileFields)
      return { filesToUpload, filesToRef, values: sqlValSchemaRecord.parse(values), returning };
    const transformed = {};
    for (let [key, val] of Object.entries(values)) {
      const isFileField = this.fileFields.includes(key);
      if (isFileField && Array.isArray(val)) {
        val = val.filter((v) => v !== "");
        if (val.length === 1)
          val = val[0];
      }
      if (isFileField && val === "")
        continue;
      if (!(val instanceof File)) {
        transformed[key] = val;
      }
      if (!isFileField || val === null || val === void 0)
        continue;
      if (val === "@null") {
        transformed[key] = null;
        continue;
      }
      if (typeof val === "string") {
        const allowArbitraryStringsInFile = false;
        if (allowArbitraryStringsInFile) {
          transformed[key] = val;
          continue;
        }
        if (this.allowMultipleFileRef) {
          const name = normalizeFileName(val, "");
          if (name !== val)
            throw new ProcessError("Invalid file name " + val);
          filesToRef.push(name);
          continue;
        }
        throw new ProcessError('File URLs not supported. Set "allowMultipleFileRef" to refer to files from other records.');
      }
      if (val instanceof File) {
        const name = normalizeFileName(val.name);
        filesToUpload[name] = val;
        transformed[key] = name;
        if (!returning.includes(key))
          returning.push(key);
        continue;
      }
      throw new ProcessError("File or string expected in file field " + key);
    }
    return { filesToUpload, filesToRef, values: sqlValSchemaRecord.parse(transformed), returning };
  }
  fileRoute(key, recordId) {
    return `/api/v1/files/${this.name}/${recordId}/${key}`;
  }
  // todo record id like in pocketbase? not using right now because id can change which would break.
  fileKey(key, _recordId) {
    let basePath = this.data.r2Base ?? this.data.name;
    if (this.data.idInR2) {
      if (!_recordId)
        throw new HTTPException(500, { message: "Record id required when idInR2 is true" });
      basePath += "/" + _recordId;
    }
    return `${basePath}/${key}`;
  }
  async getFile(key, _recordId) {
    const fileKey = this.fileKey(key, _recordId);
    const object = await this.$db.getFileObject(fileKey).catch((e) => {
      console.error("Failed to get file", key, e);
      throw new HTTPException(500, { message: "Failed to get file" });
    });
    if (!object)
      throw new HTTPException(404, { message: "File not found" });
    return object;
  }
  checkColsWildcard(cols, allowSubqueries = false) {
    const res = [];
    const isAdmin = !!this.jc.globals.auth?.admin;
    const aliases = /* @__PURE__ */ new Set();
    const addAlias = /* @__PURE__ */ __name((alias) => {
      if (aliases.has(alias))
        throw new ProcessError("Duplicate field access " + alias);
      aliases.add(alias);
    }, "addAlias");
    for (const col of cols) {
      if (col === "*") {
        if (!this.allowWildcard) {
          const fields = Object.entries(this.fields).filter((f) => isAdmin || !f[1].noSelect);
          const fieldsSql = fields.map((s) => ident(s[0], this.jc));
          res.push(...fieldsSql);
          fields.forEach((f) => addAlias(f[0]));
          continue;
        }
        res.push("*");
        addAlias("*");
        continue;
      }
      if (typeof col === "string" || typeof col.q === "string") {
        const strCol = typeof col === "string" ? col : col.q;
        if (strCol.includes("*") && strCol !== "COUNT(*)")
          throw new ProcessError("Invalid column " + strCol);
        const alias = typeof col !== "string" ? col.as ?? strCol : strCol;
        addAlias(alias);
      } else {
        if (!allowSubqueries)
          throw new ProcessError("Subqueries not allowed");
        if (!col.as)
          throw new Error("Subquery must have an alias");
        addAlias(col.as);
      }
      res.push(col);
    }
    return res;
  }
  // Routing (separate from $Database so we only init the routes for the table when required)
  router;
  _routesInit = false;
  routes = [];
  _initRoutes() {
    if (!this.router)
      this.router = new LinearRouter();
    if (this._routesInit)
      return this.router;
    this.routes.push(...this.extensions.flatMap((e) => e.routes));
    for (const route of this.routes) {
      this.router.add(route.method.toUpperCase(), route.path, this.$db.rawRouteHandler(route));
    }
    this._routesInit = true;
    return this.router;
  }
  async route(path) {
    const router = this._initRoutes();
    const match = router.match(this.$db.requestMethod, path);
    const [handler, params] = match[0]?.[0] ?? [void 0];
    if (!handler)
      return void 0;
    return await handler(params, path);
  }
  getRoutes() {
    this._initRoutes();
    return this.routes;
  }
  _zodSchema;
  get zodSchema() {
    if (this._zodSchema)
      return this._zodSchema;
    const schema = {};
    for (const field of this.data.fields) {
      schema[field.name] = tableFieldTypeToZod[field.type] ?? tableFieldTypeToZod[field.sqlType];
    }
    this._zodSchema = external_exports.object(schema);
    return this._zodSchema;
  }
};
__name($Table, "$Table");

// node_modules/teenybase/dist/security/JWTTokenHelper.js
var JWTTokenHelper = class {
  secret;
  issuer;
  algorithm;
  allowedIssuers = [];
  constructor(secret, issuer = "$db", algorithm2 = "HS256", allowedIssuers) {
    this.secret = secret;
    this.issuer = issuer;
    this.algorithm = algorithm2;
    this.allowedIssuers.push(issuer);
    if (allowedIssuers)
      this.allowedIssuers.push(...allowedIssuers);
  }
  async createJwtToken(payload, secret, secondsDuration) {
    const time4 = Math.floor(Date.now() / 1e3);
    const claims = {
      ...payload,
      iat: time4,
      exp: time4 + secondsDuration,
      // admin: false,
      iss: this.issuer
    };
    return sign(claims, await this.secret() + secret, { algorithm: this.algorithm, header: { typ: "JWT" } });
  }
  async decodeAuth(auth, secret, onlyVerified = true, issuers, payload) {
    payload = payload || decode(auth).payload;
    if (!this.allowedIssuers.includes(payload.iss))
      throw new HTTPException(401, { message: "Invalid app, " + payload.iss });
    if (issuers && !issuers.includes(payload.iss))
      throw new HTTPException(401, { message: "Invalid issuer" });
    if (payload.iss === "https://accounts.google.com") {
      const res = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${auth}`);
      const json = await res.json().catch((_) => ({}));
      if (!res.ok || !json || json.error || !json.email || !json.email_verified)
        throw new HTTPException(401, { message: "Invalid google token, unable to find email" });
      if (payload.email !== json.email)
        throw new HTTPException(401, { message: "Unknown error, Invalid email from google verification" });
      return { issData: payload, verified: true, sub: json.email, iss: "google" };
    }
    if (payload.iss !== this.issuer)
      throw new HTTPException(400, { message: "Invalid issuer" });
    const valid = await verify(auth, await this.secret() + secret, {
      throwError: false,
      algorithm: this.algorithm
    });
    if (!valid)
      throw new HTTPException(401, { message: "Unauthorized - invalid token" });
    const email = payload.sub;
    if (!payload.verified) {
      if (onlyVerified)
        throw new HTTPException(403, { message: "Not verified" });
    }
    return payload;
  }
};
__name(JWTTokenHelper, "JWTTokenHelper");

// node_modules/teenybase/dist/worker/email/discordNotify.js
async function discordNotify(webhookPath, content, files) {
  const webhook = !webhookPath.startsWith("https:/") ? "https://discord.com/api/webhooks/" + webhookPath : webhookPath;
  let init = {
    method: "POST"
  };
  if (!files)
    init = {
      ...init,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content })
    };
  else {
    const form = new FormData();
    form.append("content", content);
    files.forEach((file, index) => {
      form.append(`files[${index}]`, file, file.name);
    });
    init = {
      ...init,
      // DO NOT pass headers here as it overrides the boundary https://stackoverflow.com/questions/35192841/how-do-i-post-with-multipart-form-data-using-fetch#comment91367674_40714217
      // headers: {
      //     'Content-Type': 'multipart/form-data',
      // },
      body: form
    };
  }
  const res = await fetch(webhook, init).catch((err) => ({ ok: false, statusText: err.message }));
  if (!res.ok)
    console.error("Failed to call discord webhook", res.statusText);
  return res.ok;
}
__name(discordNotify, "discordNotify");

// node_modules/teenybase/dist/utils/helpers.js
function pathJoin(parts, sep) {
  const separator = sep || "/";
  const replace = new RegExp(separator + "{1,}", "g");
  return parts.join(separator).replace(replace, separator);
}
__name(pathJoin, "pathJoin");

// node_modules/teenybase/dist/worker/email/block-list.js
var emailBlockList = "yopmail.com,mailinator.com,guerrillamail.com,sharklasers.com,maildrop.cc";
function checkBlocklist(to, blocklist) {
  const toOrigin = to.split("@")[1].split("?")[0];
  if (emailBlockList.match(new RegExp("(,|^)" + toOrigin + "(,|$)", "i")))
    throw new HTTPException(400, { message: "Invalid email domain" });
  if (blocklist?.match(new RegExp("(,|^)" + toOrigin + "(,|$)", "i")))
    throw new HTTPException(400, { message: "Invalid email domain" });
}
__name(checkBlocklist, "checkBlocklist");

// node_modules/teenybase/dist/worker/email/mailgun.js
var MailgunHelper = class {
  baseUrl = "https://api.mailgun.net/v3/";
  bindings;
  constructor(bindings) {
    this.bindings = bindings;
    if (bindings.MAILGUN_API_URL?.startsWith("https://"))
      this.baseUrl = bindings.MAILGUN_API_URL;
    else if (bindings.MAILGUN_API_URL)
      throw new HTTPException(400, { message: "Invalid mailgun configuration - MAILGUN_API_URL must start with https://" });
    if (!this.bindings.MAILGUN_API_SERVER)
      throw new HTTPException(400, { message: "Invalid mailgun configuration - missing MAILGUN_API_SERVER or MAILGUN_API_KEY" });
  }
  async sendEmail({ from, to, subject, html: html2, tags }) {
    checkBlocklist(to, this.bindings.EMAIL_BLOCKLIST);
    const form = new FormData();
    form.append("from", from);
    form.append("to", to);
    form.append("subject", subject);
    form.append("html", html2);
    tags.forEach((tag) => form.append("o:tag", tag));
    const _key = this.bindings.MAILGUN_API_KEY;
    const key = typeof _key === "string" || !_key ? _key : await _key();
    if (!key)
      throw new HTTPException(500, { message: "Invalid mailgun configuration - missing MAILGUN_API_KEY" });
    let res = await fetch(pathJoin([this.baseUrl, this.bindings.MAILGUN_API_SERVER, "/messages"]), {
      method: "POST",
      headers: {
        "Authorization": "Basic " + btoa("api:" + key)
        // don't add content-type header for multipart
      },
      body: form
    }).catch((e) => {
      console.error("Failed to fetch mailgun", e);
      return new Response("Failed to fetch mailgun - " + e.message || e, { status: 500 });
    });
    let resJson = void 0;
    let resp = "";
    try {
      resp = await res.text();
      resJson = JSON.parse(resp);
    } catch (e) {
      console.error("Failed to parse mailgun response", e);
    }
    if (!resJson) {
      console.error("Error sending email, ", res?.status, resp);
      if (this.bindings.DISCORD_MAILGUN_NOTIFY_WEBHOOK)
        await discordNotify(this.bindings.DISCORD_MAILGUN_NOTIFY_WEBHOOK, `Failed to send email(\`${res.status}\`) to \`${to}\` 
\`\`\`${resp}\`\`\``);
      throw new HTTPException(500, { message: "Failed to send email" });
    }
    return resJson;
  }
  async receiveWebhook(data) {
    const _key = this.bindings.MAILGUN_WEBHOOK_SIGNING_KEY;
    const key = typeof _key === "string" || !_key ? _key : await _key();
    const signature = data.signature;
    const verified = !key || !signature ? false : await verify2({ signingKey: key, ...signature });
    let message = "";
    if (!verified) {
      console.error("Invalid Webhook Signature", JSON.stringify(data));
      message += "[Invalid Webhook Signature]\n";
    }
    const eventData = data["event-data"];
    if (!eventData && !verified) {
      if (this.bindings.DISCORD_MAILGUN_NOTIFY_WEBHOOK)
        await discordNotify(this.bindings.DISCORD_MAILGUN_NOTIFY_WEBHOOK, `Empty webhook notification from mailgun, make sure https is used in webhook. https://app.mailgun.com/mg/sending/${this.bindings.MAILGUN_API_SERVER}/logs`);
      return;
    }
    if (!eventData)
      throw new HTTPException(400, { message: "Invalid mailgun webhook data" });
    const timestamp = eventData.timestamp ?? Date.now();
    const logLevel = eventData["log-level"];
    const { event, recipient } = eventData;
    message += `${logLevel?.toUpperCase() || "UNKNOWN"} - ${event?.toUpperCase() || "UNKNOWN"} at ${new Date(parseInt(timestamp) * 1e3).toISOString()}
`;
    if (event.toLowerCase() === "failed") {
      message += `Severity: ${eventData.severity}
`;
      message += `Reason: ${eventData.reason}
`;
    }
    if (recipient)
      message += `Recipient: ${recipient}
`;
    if (logLevel !== "info") {
      const json = JSON.stringify(eventData, null, 2);
      const res = this.bindings.DISCORD_MAILGUN_NOTIFY_WEBHOOK ? await discordNotify(this.bindings.DISCORD_MAILGUN_NOTIFY_WEBHOOK, message, [new File([json], "event.json", {
        type: "application/json"
      })]) : false;
      if (!res) {
        logLevel === "warn" ? console.warn(message, json) : console.error(message, json);
        if (this.bindings.DISCORD_MAILGUN_NOTIFY_WEBHOOK)
          throw new HTTPException(500, { message: "Failed to notify destination" });
      }
    } else {
      console.log(message);
    }
    if (!verified)
      throw new HTTPException(406, { message: "Invalid mailgun webhook signature" + key ? "" : ", no key to verify" });
  }
  getRoutes(c) {
    const path = "/mailgun/webhook/:wid?";
    const handler = {
      raw: async (params) => {
        const wid = params?.wid;
        if ((c.env.MAILGUN_WEBHOOK_ID || wid) && wid !== c.env.MAILGUN_WEBHOOK_ID)
          throw new HTTPException(404, { message: "Not found" });
        let body;
        try {
          body = JSON.parse(await c.req.text() || "{}");
        } catch (e) {
          throw new HTTPException(400, { message: "Invalid mailgun webhook data" });
        }
        await this.receiveWebhook(body);
        return c.json({ message: "Received" }, 200);
      }
    };
    const zod = /* @__PURE__ */ __name(() => ({
      description: "Mailgun webhook. Webhook can send email errors/events to this endpoint",
      request: {
        headers: external_exports.object({}),
        params: external_exports.object({ wid: external_exports.string().optional().describe("Optional id for the webhook.") }),
        body: {
          required: true,
          content: { "application/json": { schema: zMailgunWebhookData } }
        }
      },
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": { schema: external_exports.object({ message: external_exports.literal("Received") }) } }
        },
        "400": { description: "Invalid mailgun webhook data, retry in some time." },
        "406": { description: "Invalid mailgun webhook signature, don't retry" },
        "500": { description: "Failed to notify destination or other error, retry in some time." }
      }
    }), "zod");
    return [{ method: "get", path, handler, zod }, { method: "post", path, handler, zod }];
  }
};
__name(MailgunHelper, "MailgunHelper");
var zMailgunWebhookData = external_exports.object({
  signature: external_exports.object({
    timestamp: external_exports.string(),
    token: external_exports.string(),
    signature: external_exports.string()
  }),
  "event-data": external_exports.record(external_exports.string())
  // todo could it be anything else?
});
async function verify2({ signingKey, timestamp, token, signature }) {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(signingKey);
  const message = encoder.encode(timestamp + token);
  const key = await crypto.subtle.importKey("raw", keyData, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signatureBuffer = await crypto.subtle.sign("HMAC", key, message);
  const signatureArray = Array.from(new Uint8Array(signatureBuffer));
  const encodedToken = signatureArray.map((b) => b.toString(16).padStart(2, "0")).join("");
  return encodedToken === signature;
}
__name(verify2, "verify");

// node_modules/teenybase/dist/worker/util/replaceTemplateVariables.js
function replaceTemplateVariables(html2, variables, times = 1) {
  if (!html2 || !times)
    return html2;
  let res = html2.replace(/\{\{(.*?)}}/g, (match, p1) => {
    const split = p1.split("|");
    const key = split[0]?.trim() || "";
    const def = split.slice(1).join("|").trim() || "";
    return (variables[key] || def) + "";
  });
  if (times > 1 && res.search(/\{\{(.*?)}}/))
    res = replaceTemplateVariables(res, variables, times - 1);
  return res;
}
__name(replaceTemplateVariables, "replaceTemplateVariables");

// node_modules/teenybase/dist/worker/email/templates/base-layout-1.js
var baseLayout1 = `
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml"
>
<head>
    <title>{{company_name}}</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <meta http-equiv="X-UA-Compatible" content="IE=edge"/>
    <meta name="viewport" content="width=device-width, initial-scale=1.0 "/>
    <meta name="format-detection" content="telephone=no"/>
    <style type="text/css">
        body {
            margin: 0;
            padding: 0;
            -webkit-text-size-adjust: 100% !important;
            -ms-text-size-adjust: 100% !important;
            -webkit-font-smoothing: antialiased !important;
            background-color: #F0F2F8;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Ubuntu, sans-serif;
        }

        img {
            border: 0 !important;
            outline: none !important;
        }

        p {
            Margin: 0px !important;
            Padding: 0px !important;
        }

        table {
            border-collapse: collapse;
            mso-table-lspace: 0px;
            mso-table-rspace: 0px;
        }

        td, a, span {
            border-collapse: collapse;
            mso-line-height-rule: exactly;
        }

        .ExternalClass * {
            line-height: 100%;
        }

        .em_blue a {
            text-decoration: none;
            color: #264780;
        }

        .em_grey a {
            text-decoration: none;
            color: #434343;
        }

        .em_white a {
            text-decoration: none;
            color: #ffffff;
        }

        .em_aside5 {
            padding: 0 20px !important;
        }

        @media only screen and (min-width: 481px) and (max-width: 649px) {
            .em_main_table {
                width: 100% !important;
            }

            .em_wrapper {
                width: 100% !important;
            }

            .em_hide {
                display: none !important;
            }

            .em_aside10 {
                padding: 0px 10px !important;
            }

            .em_h20 {
                height: 20px !important;
                font-size: 1px !important;
                line-height: 1px !important;
            }

            .em_h10 {
                height: 10px !important;
                font-size: 1px !important;
                line-height: 1px !important;
            }

            .em_aside5 {
                padding: 0px 10px !important;
            }
        }

        @media only screen and (min-width: 375px) and (max-width: 480px) {
            .em_main_table {
                width: 100% !important;
            }

            .em_wrapper {
                width: 100% !important;
            }

            .em_hide {
                display: none !important;
            }

            .em_aside10 {
                padding: 0px 10px !important;
            }

            .em_aside5 {
                padding: 0px 8px !important;
            }

            .em_h20 {
                height: 20px !important;
                font-size: 1px !important;
                line-height: 1px !important;
            }

            .em_h10 {
                height: 10px !important;
                font-size: 1px !important;
                line-height: 1px !important;
            }

            .em_font_11 {
                font-size: 12px !important;
            }

            .em_font_22 {
                font-size: 22px !important;
                line-height: 25px !important;
            }

            .em_w5 {
                width: 7px !important;
            }

            u + .em_body .em_full_wrap {
                width: 100% !important;
                width: 100vw !important;
            }
        }

        @media only screen and (max-width: 374px) {
            .em_main_table {
                width: 100% !important;
            }

            .em_wrapper {
                width: 100% !important;
            }

            .em_hide {
                display: none !important;
            }

            .em_aside10 {
                padding: 0px 10px !important;
            }

            .em_aside5 {
                padding: 0px 8px !important;
            }

            .em_h20 {
                height: 20px !important;
                font-size: 1px !important;
                line-height: 1px !important;
            }

            .em_h10 {
                height: 10px !important;
                font-size: 1px !important;
                line-height: 1px !important;
            }

            .em_font_11 {
                font-size: 11px !important;
            }

            .em_font_22 {
                font-size: 22px !important;
                line-height: 25px !important;
            }

            .em_w5 {
                width: 5px !important;
            }

            u + .em_body .em_full_wrap {
                width: 100% !important;
                width: 100vw !important;
            }
        }
    </style>
</head>
<body class="em_body" style="margin:0px auto; padding:0px;" bgcolor="#F0F2F8">
<table width="100%" border="0" cellspacing="0" cellpadding="0" class="em_full_wrap" align="center" bgcolor="#F0F2F8">
    <tr>
        <td align="center" valign="top">
            <table align="center" width="480" border="0" cellspacing="0" cellpadding="0" class="em_main_table"
                   style="width:480px; min-width:480px; max-width:480px;">
                <tr>
                    <td align="left" valign="top" style="padding:0 ;" class="em_aside10">
                        <table width="100%" border="0" cellspacing="0" cellpadding="0" align="left">
                            <tr>
                                <td height="58" style="height:58px;" class="em_h20">&nbsp;</td>
                            </tr>
                            <tr>
                                <td align="left" valign="top">
                                    <a href="{{company_url}}" target="_blank" style="text-decoration:none;">
                                        <span style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Ubuntu, sans-serif; font-size:20px; line-height:24px; color:rgb(0,0,0); font-weight:500;">{{company_name}}</span>
                                    </a>
                                </td>
                            </tr>
                            <tr>
                                <td height="32" style="height:32px;" class="em_h20">&nbsp;</td>
                            </tr>
                        </table>
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
<table width="100%" border="0" cellspacing="0" cellpadding="0" class="em_full_wrap" align="center" bgcolor="#F0F2F8">
    <tr>
        <td align="center" valign="top" class="em_aside5">
            <table align="center" width="480" border="0" cellspacing="0" cellpadding="0" class="em_main_table"
                   style="width:480px; min-width:480px; max-width:480px;">
                <tr>
                    <td align="center" valign="top"
                        style="padding:0 20px; background-color:#ffffff; border-radius:12px;">
                        {{EMAIL_CONTENT}}
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
<table width="100%" border="0" cellspacing="0" cellpadding="0" class="em_full_wrap" align="center" bgcolor="#F0F2F8">
    <tr>
        <td align="center" valign="top">
            <table align="center" width="480" border="0" cellspacing="0" cellpadding="0" class="em_main_table"
                   style="width:480px; min-width:480px; max-width:480px;">
                <tr>
                    <td align="center" valign="top" style="padding:0 20px;" class="em_aside10">
                        <table width="100%" border="0" cellspacing="0" cellpadding="0" align="center">
                            <tr>
                                <td height="32" style="height:32px;" class="em_h20">&nbsp;</td>
                            </tr>
                            <tr>
                                <td class="em_grey" align="center" valign="top"
                                    style="font-family: Arial, sans-serif; font-size: 15px; line-height: 18px; color:#434343; font-weight:bold;">
                                    Problems or questions?
                                </td>
                            </tr>
                            <tr>
                                <td height="10" style="height:10px; font-size:1px; line-height:1px;">&nbsp;</td>
                            </tr>
                            <tr>
                                <td align="center" valign="top" style="font-size:0px; line-height:0px;">
                                    <table border="0" cellspacing="0" cellpadding="0" align="center">
                                        <tr>
                                            <td class="em_grey em_font_11" align="left" valign="middle"
                                                style="font-family: Arial, sans-serif; font-size: 13px; line-height: 15px; color:#434343;">
                                                <a href="mailto:{{support_email}}"
                                                   style="text-decoration:none; color:#434343;">{{support_email}}</a>
                                                <a href="mailto:{{support_email}}"
                                                   style="text-decoration:none; color:#434343;">[mailto:{{support_email}}]</a>
                                            </td>
                                        </tr>
                                    </table>
                                </td>
                            </tr>
                            <tr>
                                <td height="9" style="font-size:0px; line-height:0px; height:9px;" class="em_h10">
                                </td>
                            </tr>
                            <tr>
                                <td align="center" valign="top">
                                    <table border="0" cellspacing="0" cellpadding="0" align="center">
                                        <tr>
                                            <td width="12" align="left" valign="middle"
                                                style="font-size:0px; line-height:0px; width:12px;">
                                                <!--                                                <a href="#" target="_blank" style="text-decoration:none;"></a>-->
                                            </td>
                                            <td width="7" style="width:7px; font-size:0px; line-height:0px;"
                                                class="em_w5">&nbsp;
                                            </td>
                                            <td class="em_grey em_font_11" align="left" valign="middle"
                                                style="font-family: Arial, sans-serif; font-size: 13px; line-height: 15px; color:#434343;">
                                                <a href="{{company_url}}" target="_blank"
                                                   style="text-decoration:none; color:#434343;">{{company_name}}</a>
                                                &bull; {{company_address}}
                                            </td>
                                        </tr>
                                    </table>
                                </td>
                            </tr>
                            <tr>
                                <td height="35" style="height:35px;" class="em_h20">&nbsp;</td>
                            </tr>
                        </table>
                    </td>
                </tr>
                <tr>
                    <td height="1" bgcolor="#dadada" style="font-size:0px; line-height:0px; height:1px;">
                    </td>
                </tr>
                <tr>
                    <td align="center" valign="top" style="padding:0 20px;" class="em_aside10">
                        <table width="100%" border="0" cellspacing="0" cellpadding="0" align="center">
                            <tr>
                                <td height="16" style="font-size:0px; line-height:0px; height:16px;">&nbsp;</td>
                            </tr>
                            <tr>
                                <td align="center" valign="top">
                                    <table border="0" cellspacing="0" cellpadding="0" align="left" class="em_wrapper">
                                        <tr>
                                            <td class="em_grey" align="center" valign="middle"
                                                style="font-family: Arial, sans-serif; font-size: 11px; line-height: 16px; color:#434343;">
                                                &copy; {{company_copyright | Copyright}} &nbsp;
                                                <!--|&nbsp;  <a href="#" target="_blank" style="text-decoration:underline; color:#434343;">Unsubscribe</a>-->
                                            </td>
                                        </tr>
                                    </table>
                                </td>
                            </tr>
                            <tr>
                                <td height="16" style="font-size:0px; line-height:0px; height:16px;">&nbsp;</td>
                            </tr>
                        </table>
                    </td>
                </tr>
                <tr>
                    <td class="em_hide" style="line-height:1px;min-width:480px;background-color:#F0F2F8;">
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</body>
</html>
`;

// node_modules/teenybase/dist/worker/email/templates/message-layout-1.js
var messageLayout1 = `
<table width="100%" border="0" cellspacing="0" cellpadding="0" align="center">
    <tr>
        <td height="16" style="height:16px; font-size:0px; line-height:0px;">&nbsp;</td>
    </tr>
    <tr>
        <td class="em_blue em_font_22" align="left" valign="top"
            style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Ubuntu, sans-serif; font-size: 20px; line-height: 28px; color:#303030; font-weight:600;">
            {{message_title}}
        </td>
    </tr>
    <tr>
        <td height="16" style="height:16px; font-size:0px; line-height:0px;">&nbsp;</td>
    </tr>
    <tr>
        <td class="em_grey" align="left" valign="top"
            style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Ubuntu, sans-serif; font-size: 14px; line-height: 20px; color:#4d4d4d;">
            {{message_description}}
        </td>
    </tr>
    <tr>
        <td align="center" valign="top" style="padding: 20px 0;">
            {{EMAIL_CONTENT}}
        </td>
    </tr>
    <tr>
        <td class="em_grey" align="left" valign="top"
            style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Ubuntu, sans-serif; font-size: 14px; line-height: 20px; color:#4d4d4d;">
            {{message_footer}}
        </td>
    </tr>
    <tr>
        <td height="16" style="height:16px; font-size:0px; line-height:0px;">&nbsp;</td>
    </tr>
</table>
`;

// node_modules/teenybase/dist/worker/email/templates/action-link.js
var actionLinkTemplate = `
<a href="{{action_link}}" target="_blank" style="text-decoration:none;">
    <table width="100%" border="0" cellspacing="0" cellpadding="0" align="center">
        <tr>
            <td align="center" valign="middle"
                style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Ubuntu, sans-serif; font-size: 16px; color:{{action_text_color | #ffffff}}; font-weight:500; height:44px; background-color:{{action_button_color | #0074d4}}; border-radius:6px;">
                {{action_text | Click Here}}
            </td>
        </tr>
    </table>
</a>
`;

// node_modules/teenybase/dist/worker/email/templates/action-text.js
var actionTextTemplate = `
<table width="100%" border="0" cellspacing="0" cellpadding="0" align="center">
    <tr>
        <td align="center" valign="middle"
            style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Ubuntu, sans-serif; font-size: 16px; color:{{action_text_color | #ffffff}}; font-weight:500; height:44px; background-color:{{action_button_color | #0074d4}}; border-radius:6px;">
            {{action_text}}
        </td>
    </tr>
</table>
`;

// node_modules/teenybase/dist/worker/$DBExtension.js
var $DBExtension = class {
  db;
  constructor(db) {
    this.db = db;
  }
  routes = [];
};
__name($DBExtension, "$DBExtension");

// node_modules/@asteasolutions/zod-to-openapi/dist/index.mjs
function __rest(s, e) {
  var t = {};
  for (var p in s)
    if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0)
      t[p] = s[p];
  if (s != null && typeof Object.getOwnPropertySymbols === "function")
    for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) {
      if (e.indexOf(p[i]) < 0 && Object.prototype.propertyIsEnumerable.call(s, p[i]))
        t[p[i]] = s[p[i]];
    }
  return t;
}
__name(__rest, "__rest");
function isZodType(schema, typeName) {
  var _a2;
  return ((_a2 = schema === null || schema === void 0 ? void 0 : schema._def) === null || _a2 === void 0 ? void 0 : _a2.typeName) === typeName;
}
__name(isZodType, "isZodType");
function isAnyZodType(schema) {
  return "_def" in schema;
}
__name(isAnyZodType, "isAnyZodType");
function preserveMetadataFromModifier(zod, modifier) {
  const zodModifier = zod.ZodType.prototype[modifier];
  zod.ZodType.prototype[modifier] = function(...args) {
    const result = zodModifier.apply(this, args);
    result._def.openapi = this._def.openapi;
    return result;
  };
}
__name(preserveMetadataFromModifier, "preserveMetadataFromModifier");
function extendZodWithOpenApi(zod) {
  if (typeof zod.ZodType.prototype.openapi !== "undefined") {
    return;
  }
  zod.ZodType.prototype.openapi = function(refOrOpenapi, metadata) {
    var _a2, _b, _c, _d, _e, _f;
    const openapi = typeof refOrOpenapi === "string" ? metadata : refOrOpenapi;
    const _g = openapi !== null && openapi !== void 0 ? openapi : {}, { param } = _g, restOfOpenApi = __rest(_g, ["param"]);
    const _internal = Object.assign(Object.assign({}, (_a2 = this._def.openapi) === null || _a2 === void 0 ? void 0 : _a2._internal), typeof refOrOpenapi === "string" ? { refId: refOrOpenapi } : void 0);
    const resultMetadata = Object.assign(Object.assign(Object.assign({}, (_b = this._def.openapi) === null || _b === void 0 ? void 0 : _b.metadata), restOfOpenApi), ((_d = (_c = this._def.openapi) === null || _c === void 0 ? void 0 : _c.metadata) === null || _d === void 0 ? void 0 : _d.param) || param ? {
      param: Object.assign(Object.assign({}, (_f = (_e = this._def.openapi) === null || _e === void 0 ? void 0 : _e.metadata) === null || _f === void 0 ? void 0 : _f.param), param)
    } : void 0);
    const result = new this.constructor(Object.assign(Object.assign({}, this._def), { openapi: Object.assign(Object.assign({}, Object.keys(_internal).length > 0 ? { _internal } : void 0), Object.keys(resultMetadata).length > 0 ? { metadata: resultMetadata } : void 0) }));
    if (isZodType(this, "ZodObject")) {
      const originalExtend = this.extend;
      result.extend = function(...args) {
        var _a3, _b2, _c2, _d2, _e2, _f2, _g2;
        const extendedResult = originalExtend.apply(this, args);
        extendedResult._def.openapi = {
          _internal: {
            extendedFrom: ((_b2 = (_a3 = this._def.openapi) === null || _a3 === void 0 ? void 0 : _a3._internal) === null || _b2 === void 0 ? void 0 : _b2.refId) ? { refId: (_d2 = (_c2 = this._def.openapi) === null || _c2 === void 0 ? void 0 : _c2._internal) === null || _d2 === void 0 ? void 0 : _d2.refId, schema: this } : (_f2 = (_e2 = this._def.openapi) === null || _e2 === void 0 ? void 0 : _e2._internal) === null || _f2 === void 0 ? void 0 : _f2.extendedFrom
          },
          metadata: (_g2 = extendedResult._def.openapi) === null || _g2 === void 0 ? void 0 : _g2.metadata
        };
        return extendedResult;
      };
    }
    return result;
  };
  preserveMetadataFromModifier(zod, "optional");
  preserveMetadataFromModifier(zod, "nullable");
  preserveMetadataFromModifier(zod, "default");
  preserveMetadataFromModifier(zod, "transform");
  preserveMetadataFromModifier(zod, "refine");
  const zodDeepPartial = zod.ZodObject.prototype.deepPartial;
  zod.ZodObject.prototype.deepPartial = function() {
    const initialShape = this._def.shape();
    const result = zodDeepPartial.apply(this);
    const resultShape = result._def.shape();
    Object.entries(resultShape).forEach(([key, value]) => {
      var _a2, _b;
      value._def.openapi = (_b = (_a2 = initialShape[key]) === null || _a2 === void 0 ? void 0 : _a2._def) === null || _b === void 0 ? void 0 : _b.openapi;
    });
    result._def.openapi = void 0;
    return result;
  };
  const zodPick = zod.ZodObject.prototype.pick;
  zod.ZodObject.prototype.pick = function(...args) {
    const result = zodPick.apply(this, args);
    result._def.openapi = void 0;
    return result;
  };
  const zodOmit = zod.ZodObject.prototype.omit;
  zod.ZodObject.prototype.omit = function(...args) {
    const result = zodOmit.apply(this, args);
    result._def.openapi = void 0;
    return result;
  };
}
__name(extendZodWithOpenApi, "extendZodWithOpenApi");
function isEqual(x, y) {
  if (x === null || x === void 0 || y === null || y === void 0) {
    return x === y;
  }
  if (x === y || x.valueOf() === y.valueOf()) {
    return true;
  }
  if (Array.isArray(x)) {
    if (!Array.isArray(y)) {
      return false;
    }
    if (x.length !== y.length) {
      return false;
    }
  }
  if (!(x instanceof Object) || !(y instanceof Object)) {
    return false;
  }
  const keysX = Object.keys(x);
  return Object.keys(y).every((keyY) => keysX.indexOf(keyY) !== -1) && keysX.every((key) => isEqual(x[key], y[key]));
}
__name(isEqual, "isEqual");
function isUndefined(value) {
  return value === void 0;
}
__name(isUndefined, "isUndefined");
function mapValues(object, mapper) {
  const result = {};
  Object.entries(object).forEach(([key, value]) => {
    result[key] = mapper(value);
  });
  return result;
}
__name(mapValues, "mapValues");
function omit(object, keys) {
  const result = {};
  Object.entries(object).forEach(([key, value]) => {
    if (!keys.some((keyToOmit) => keyToOmit === key)) {
      result[key] = value;
    }
  });
  return result;
}
__name(omit, "omit");
function omitBy(object, predicate) {
  const result = {};
  Object.entries(object).forEach(([key, value]) => {
    if (!predicate(value, key)) {
      result[key] = value;
    }
  });
  return result;
}
__name(omitBy, "omitBy");
function compact(arr) {
  return arr.filter((elem) => !isUndefined(elem));
}
__name(compact, "compact");
var objectEquals = isEqual;
function isString(val) {
  return typeof val === "string";
}
__name(isString, "isString");
var OpenAPIRegistry = class {
  constructor(parents) {
    this.parents = parents;
    this._definitions = [];
  }
  get definitions() {
    var _a2, _b;
    const parentDefinitions = (_b = (_a2 = this.parents) === null || _a2 === void 0 ? void 0 : _a2.flatMap((par) => par.definitions)) !== null && _b !== void 0 ? _b : [];
    return [...parentDefinitions, ...this._definitions];
  }
  /**
   * Registers a new component schema under /components/schemas/${name}
   */
  register(refId, zodSchema) {
    const schemaWithRefId = this.schemaWithRefId(refId, zodSchema);
    this._definitions.push({ type: "schema", schema: schemaWithRefId });
    return schemaWithRefId;
  }
  /**
   * Registers a new parameter schema under /components/parameters/${name}
   */
  registerParameter(refId, zodSchema) {
    var _a2, _b, _c;
    const schemaWithRefId = this.schemaWithRefId(refId, zodSchema);
    const currentMetadata = (_a2 = schemaWithRefId._def.openapi) === null || _a2 === void 0 ? void 0 : _a2.metadata;
    const schemaWithMetadata = schemaWithRefId.openapi(Object.assign(Object.assign({}, currentMetadata), { param: Object.assign(Object.assign({}, currentMetadata === null || currentMetadata === void 0 ? void 0 : currentMetadata.param), { name: (_c = (_b = currentMetadata === null || currentMetadata === void 0 ? void 0 : currentMetadata.param) === null || _b === void 0 ? void 0 : _b.name) !== null && _c !== void 0 ? _c : refId }) }));
    this._definitions.push({
      type: "parameter",
      schema: schemaWithMetadata
    });
    return schemaWithMetadata;
  }
  /**
   * Registers a new path that would be generated under paths:
   */
  registerPath(route) {
    this._definitions.push({
      type: "route",
      route
    });
  }
  /**
   * Registers a new webhook that would be generated under webhooks:
   */
  registerWebhook(webhook) {
    this._definitions.push({
      type: "webhook",
      webhook
    });
  }
  /**
   * Registers a raw OpenAPI component. Use this if you have a simple object instead of a Zod schema.
   *
   * @param type The component type, e.g. `schemas`, `responses`, `securitySchemes`, etc.
   * @param name The name of the object, it is the key under the component
   *             type in the resulting OpenAPI document
   * @param component The actual object to put there
   */
  registerComponent(type, name, component) {
    this._definitions.push({
      type: "component",
      componentType: type,
      name,
      component
    });
    return {
      name,
      ref: { $ref: `#/components/${type}/${name}` }
    };
  }
  schemaWithRefId(refId, zodSchema) {
    return zodSchema.openapi(refId);
  }
};
__name(OpenAPIRegistry, "OpenAPIRegistry");
var ZodToOpenAPIError = class {
  constructor(message) {
    this.message = message;
  }
};
__name(ZodToOpenAPIError, "ZodToOpenAPIError");
var ConflictError = class extends ZodToOpenAPIError {
  constructor(message, data) {
    super(message);
    this.data = data;
  }
};
__name(ConflictError, "ConflictError");
var MissingParameterDataError = class extends ZodToOpenAPIError {
  constructor(data) {
    super(`Missing parameter data, please specify \`${data.missingField}\` and other OpenAPI parameter props using the \`param\` field of \`ZodSchema.openapi\``);
    this.data = data;
  }
};
__name(MissingParameterDataError, "MissingParameterDataError");
function enhanceMissingParametersError(action, paramsToAdd) {
  try {
    return action();
  } catch (error4) {
    if (error4 instanceof MissingParameterDataError) {
      throw new MissingParameterDataError(Object.assign(Object.assign({}, error4.data), paramsToAdd));
    }
    throw error4;
  }
}
__name(enhanceMissingParametersError, "enhanceMissingParametersError");
var UnknownZodTypeError = class extends ZodToOpenAPIError {
  constructor(data) {
    super(`Unknown zod object type, please specify \`type\` and other OpenAPI props using \`ZodSchema.openapi\`.`);
    this.data = data;
  }
};
__name(UnknownZodTypeError, "UnknownZodTypeError");
var Metadata = class {
  static getMetadata(zodSchema) {
    var _a2;
    const innerSchema = this.unwrapChained(zodSchema);
    const metadata = zodSchema._def.openapi ? zodSchema._def.openapi : innerSchema._def.openapi;
    const zodDescription = (_a2 = zodSchema.description) !== null && _a2 !== void 0 ? _a2 : innerSchema.description;
    return {
      _internal: metadata === null || metadata === void 0 ? void 0 : metadata._internal,
      metadata: Object.assign({ description: zodDescription }, metadata === null || metadata === void 0 ? void 0 : metadata.metadata)
    };
  }
  static getInternalMetadata(zodSchema) {
    const innerSchema = this.unwrapChained(zodSchema);
    const openapi = zodSchema._def.openapi ? zodSchema._def.openapi : innerSchema._def.openapi;
    return openapi === null || openapi === void 0 ? void 0 : openapi._internal;
  }
  static getParamMetadata(zodSchema) {
    var _a2, _b;
    const innerSchema = this.unwrapChained(zodSchema);
    const metadata = zodSchema._def.openapi ? zodSchema._def.openapi : innerSchema._def.openapi;
    const zodDescription = (_a2 = zodSchema.description) !== null && _a2 !== void 0 ? _a2 : innerSchema.description;
    return {
      _internal: metadata === null || metadata === void 0 ? void 0 : metadata._internal,
      metadata: Object.assign(Object.assign({}, metadata === null || metadata === void 0 ? void 0 : metadata.metadata), {
        // A description provided from .openapi() should be taken with higher precedence
        param: Object.assign({ description: zodDescription }, (_b = metadata === null || metadata === void 0 ? void 0 : metadata.metadata) === null || _b === void 0 ? void 0 : _b.param)
      })
    };
  }
  /**
   * A method that omits all custom keys added to the regular OpenAPI
   * metadata properties
   */
  static buildSchemaMetadata(metadata) {
    return omitBy(omit(metadata, ["param"]), isUndefined);
  }
  static buildParameterMetadata(metadata) {
    return omitBy(metadata, isUndefined);
  }
  static applySchemaMetadata(initialData, metadata) {
    return omitBy(Object.assign(Object.assign({}, initialData), this.buildSchemaMetadata(metadata)), isUndefined);
  }
  static getRefId(zodSchema) {
    var _a2;
    return (_a2 = this.getInternalMetadata(zodSchema)) === null || _a2 === void 0 ? void 0 : _a2.refId;
  }
  static unwrapChained(schema) {
    return this.unwrapUntil(schema);
  }
  static getDefaultValue(zodSchema) {
    const unwrapped = this.unwrapUntil(zodSchema, "ZodDefault");
    return unwrapped === null || unwrapped === void 0 ? void 0 : unwrapped._def.defaultValue();
  }
  static unwrapUntil(schema, typeName) {
    if (typeName && isZodType(schema, typeName)) {
      return schema;
    }
    if (isZodType(schema, "ZodOptional") || isZodType(schema, "ZodNullable") || isZodType(schema, "ZodBranded")) {
      return this.unwrapUntil(schema.unwrap(), typeName);
    }
    if (isZodType(schema, "ZodDefault") || isZodType(schema, "ZodReadonly")) {
      return this.unwrapUntil(schema._def.innerType, typeName);
    }
    if (isZodType(schema, "ZodEffects")) {
      return this.unwrapUntil(schema._def.schema, typeName);
    }
    if (isZodType(schema, "ZodPipeline")) {
      return this.unwrapUntil(schema._def.in, typeName);
    }
    return typeName ? void 0 : schema;
  }
  static isOptionalSchema(zodSchema) {
    return zodSchema.isOptional();
  }
};
__name(Metadata, "Metadata");
var ArrayTransformer = class {
  transform(zodSchema, mapNullableType, mapItems) {
    var _a2, _b;
    const itemType = zodSchema._def.type;
    return Object.assign(Object.assign({}, mapNullableType("array")), { items: mapItems(itemType), minItems: (_a2 = zodSchema._def.minLength) === null || _a2 === void 0 ? void 0 : _a2.value, maxItems: (_b = zodSchema._def.maxLength) === null || _b === void 0 ? void 0 : _b.value });
  }
};
__name(ArrayTransformer, "ArrayTransformer");
var BigIntTransformer = class {
  transform(mapNullableType) {
    return Object.assign(Object.assign({}, mapNullableType("string")), { pattern: `^d+$` });
  }
};
__name(BigIntTransformer, "BigIntTransformer");
var DiscriminatedUnionTransformer = class {
  transform(zodSchema, isNullable, mapNullableOfArray, mapItem, generateSchemaRef) {
    const options = [...zodSchema.options.values()];
    const optionSchema = options.map(mapItem);
    if (isNullable) {
      return {
        oneOf: mapNullableOfArray(optionSchema, isNullable)
      };
    }
    return {
      oneOf: optionSchema,
      discriminator: this.mapDiscriminator(options, zodSchema.discriminator, generateSchemaRef)
    };
  }
  mapDiscriminator(zodObjects, discriminator, generateSchemaRef) {
    if (zodObjects.some((obj) => Metadata.getRefId(obj) === void 0)) {
      return void 0;
    }
    const mapping = {};
    zodObjects.forEach((obj) => {
      var _a2;
      const refId = Metadata.getRefId(obj);
      const value = (_a2 = obj.shape) === null || _a2 === void 0 ? void 0 : _a2[discriminator];
      if (isZodType(value, "ZodEnum") || isZodType(value, "ZodNativeEnum")) {
        const keys = Object.values(value.enum).filter(isString);
        keys.forEach((enumValue) => {
          mapping[enumValue] = generateSchemaRef(refId);
        });
        return;
      }
      const literalValue = value === null || value === void 0 ? void 0 : value._def.value;
      if (typeof literalValue !== "string") {
        throw new Error(`Discriminator ${discriminator} could not be found in one of the values of a discriminated union`);
      }
      mapping[literalValue] = generateSchemaRef(refId);
    });
    return {
      propertyName: discriminator,
      mapping
    };
  }
};
__name(DiscriminatedUnionTransformer, "DiscriminatedUnionTransformer");
var EnumTransformer = class {
  transform(zodSchema, mapNullableType) {
    return Object.assign(Object.assign({}, mapNullableType("string")), { enum: zodSchema._def.values });
  }
};
__name(EnumTransformer, "EnumTransformer");
var IntersectionTransformer = class {
  transform(zodSchema, isNullable, mapNullableOfArray, mapItem) {
    const subtypes = this.flattenIntersectionTypes(zodSchema);
    const allOfSchema = {
      allOf: subtypes.map(mapItem)
    };
    if (isNullable) {
      return {
        anyOf: mapNullableOfArray([allOfSchema], isNullable)
      };
    }
    return allOfSchema;
  }
  flattenIntersectionTypes(schema) {
    if (!isZodType(schema, "ZodIntersection")) {
      return [schema];
    }
    const leftSubTypes = this.flattenIntersectionTypes(schema._def.left);
    const rightSubTypes = this.flattenIntersectionTypes(schema._def.right);
    return [...leftSubTypes, ...rightSubTypes];
  }
};
__name(IntersectionTransformer, "IntersectionTransformer");
var LiteralTransformer = class {
  transform(zodSchema, mapNullableType) {
    return Object.assign(Object.assign({}, mapNullableType(typeof zodSchema._def.value)), { enum: [zodSchema._def.value] });
  }
};
__name(LiteralTransformer, "LiteralTransformer");
function enumInfo(enumObject) {
  const keysExceptReverseMappings = Object.keys(enumObject).filter((key) => typeof enumObject[enumObject[key]] !== "number");
  const values = keysExceptReverseMappings.map((key) => enumObject[key]);
  const numericCount = values.filter((_) => typeof _ === "number").length;
  const type = numericCount === 0 ? "string" : numericCount === values.length ? "numeric" : "mixed";
  return { values, type };
}
__name(enumInfo, "enumInfo");
var NativeEnumTransformer = class {
  transform(zodSchema, mapNullableType) {
    const { type, values } = enumInfo(zodSchema._def.values);
    if (type === "mixed") {
      throw new ZodToOpenAPIError("Enum has mixed string and number values, please specify the OpenAPI type manually");
    }
    return Object.assign(Object.assign({}, mapNullableType(type === "numeric" ? "integer" : "string")), { enum: values });
  }
};
__name(NativeEnumTransformer, "NativeEnumTransformer");
var NumberTransformer = class {
  transform(zodSchema, mapNullableType, getNumberChecks) {
    return Object.assign(Object.assign({}, mapNullableType(zodSchema.isInt ? "integer" : "number")), getNumberChecks(zodSchema._def.checks));
  }
};
__name(NumberTransformer, "NumberTransformer");
var ObjectTransformer = class {
  transform(zodSchema, defaultValue, mapNullableType, mapItem) {
    var _a2;
    const extendedFrom = (_a2 = Metadata.getInternalMetadata(zodSchema)) === null || _a2 === void 0 ? void 0 : _a2.extendedFrom;
    const required = this.requiredKeysOf(zodSchema);
    const properties = mapValues(zodSchema._def.shape(), mapItem);
    if (!extendedFrom) {
      return Object.assign(Object.assign(Object.assign(Object.assign({}, mapNullableType("object")), { properties, default: defaultValue }), required.length > 0 ? { required } : {}), this.generateAdditionalProperties(zodSchema, mapItem));
    }
    const parent = extendedFrom.schema;
    mapItem(parent);
    const keysRequiredByParent = this.requiredKeysOf(parent);
    const propsOfParent = mapValues(parent === null || parent === void 0 ? void 0 : parent._def.shape(), mapItem);
    const propertiesToAdd = Object.fromEntries(Object.entries(properties).filter(([key, type]) => {
      return !objectEquals(propsOfParent[key], type);
    }));
    const additionallyRequired = required.filter((prop) => !keysRequiredByParent.includes(prop));
    const objectData = Object.assign(Object.assign(Object.assign(Object.assign({}, mapNullableType("object")), { default: defaultValue, properties: propertiesToAdd }), additionallyRequired.length > 0 ? { required: additionallyRequired } : {}), this.generateAdditionalProperties(zodSchema, mapItem));
    return {
      allOf: [
        { $ref: `#/components/schemas/${extendedFrom.refId}` },
        objectData
      ]
    };
  }
  generateAdditionalProperties(zodSchema, mapItem) {
    const unknownKeysOption = zodSchema._def.unknownKeys;
    const catchallSchema = zodSchema._def.catchall;
    if (isZodType(catchallSchema, "ZodNever")) {
      if (unknownKeysOption === "strict") {
        return { additionalProperties: false };
      }
      return {};
    }
    return { additionalProperties: mapItem(catchallSchema) };
  }
  requiredKeysOf(objectSchema) {
    return Object.entries(objectSchema._def.shape()).filter(([_key, type]) => !Metadata.isOptionalSchema(type)).map(([key, _type]) => key);
  }
};
__name(ObjectTransformer, "ObjectTransformer");
var RecordTransformer = class {
  transform(zodSchema, mapNullableType, mapItem) {
    const propertiesType = zodSchema._def.valueType;
    const keyType = zodSchema._def.keyType;
    const propertiesSchema = mapItem(propertiesType);
    if (isZodType(keyType, "ZodEnum") || isZodType(keyType, "ZodNativeEnum")) {
      const keys = Object.values(keyType.enum).filter(isString);
      const properties = keys.reduce((acc, curr) => Object.assign(Object.assign({}, acc), { [curr]: propertiesSchema }), {});
      return Object.assign(Object.assign({}, mapNullableType("object")), { properties });
    }
    return Object.assign(Object.assign({}, mapNullableType("object")), { additionalProperties: propertiesSchema });
  }
};
__name(RecordTransformer, "RecordTransformer");
var StringTransformer = class {
  transform(zodSchema, mapNullableType) {
    var _a2, _b, _c;
    const regexCheck = this.getZodStringCheck(zodSchema, "regex");
    const length = (_a2 = this.getZodStringCheck(zodSchema, "length")) === null || _a2 === void 0 ? void 0 : _a2.value;
    const maxLength = Number.isFinite(zodSchema.minLength) ? (_b = zodSchema.minLength) !== null && _b !== void 0 ? _b : void 0 : void 0;
    const minLength = Number.isFinite(zodSchema.maxLength) ? (_c = zodSchema.maxLength) !== null && _c !== void 0 ? _c : void 0 : void 0;
    return Object.assign(Object.assign({}, mapNullableType("string")), {
      // FIXME: https://github.com/colinhacks/zod/commit/d78047e9f44596a96d637abb0ce209cd2732d88c
      minLength: length !== null && length !== void 0 ? length : maxLength,
      maxLength: length !== null && length !== void 0 ? length : minLength,
      format: this.mapStringFormat(zodSchema),
      pattern: regexCheck === null || regexCheck === void 0 ? void 0 : regexCheck.regex.source
    });
  }
  /**
   * Attempts to map Zod strings to known formats
   * https://json-schema.org/understanding-json-schema/reference/string.html#built-in-formats
   */
  mapStringFormat(zodString) {
    if (zodString.isUUID)
      return "uuid";
    if (zodString.isEmail)
      return "email";
    if (zodString.isURL)
      return "uri";
    if (zodString.isDate)
      return "date";
    if (zodString.isDatetime)
      return "date-time";
    if (zodString.isCUID)
      return "cuid";
    if (zodString.isCUID2)
      return "cuid2";
    if (zodString.isULID)
      return "ulid";
    if (zodString.isIP)
      return "ip";
    if (zodString.isEmoji)
      return "emoji";
    return void 0;
  }
  getZodStringCheck(zodString, kind) {
    return zodString._def.checks.find((check) => {
      return check.kind === kind;
    });
  }
};
__name(StringTransformer, "StringTransformer");
var TupleTransformer = class {
  constructor(versionSpecifics) {
    this.versionSpecifics = versionSpecifics;
  }
  transform(zodSchema, mapNullableType, mapItem) {
    const { items } = zodSchema._def;
    const schemas = items.map(mapItem);
    return Object.assign(Object.assign({}, mapNullableType("array")), this.versionSpecifics.mapTupleItems(schemas));
  }
};
__name(TupleTransformer, "TupleTransformer");
var UnionTransformer = class {
  transform(zodSchema, mapNullableOfArray, mapItem) {
    const options = this.flattenUnionTypes(zodSchema);
    const schemas = options.map((schema) => {
      const optionToGenerate = this.unwrapNullable(schema);
      return mapItem(optionToGenerate);
    });
    return {
      anyOf: mapNullableOfArray(schemas)
    };
  }
  flattenUnionTypes(schema) {
    if (!isZodType(schema, "ZodUnion")) {
      return [schema];
    }
    const options = schema._def.options;
    return options.flatMap((option) => this.flattenUnionTypes(option));
  }
  unwrapNullable(schema) {
    if (isZodType(schema, "ZodNullable")) {
      return this.unwrapNullable(schema.unwrap());
    }
    return schema;
  }
};
__name(UnionTransformer, "UnionTransformer");
var OpenApiTransformer = class {
  constructor(versionSpecifics) {
    this.versionSpecifics = versionSpecifics;
    this.objectTransformer = new ObjectTransformer();
    this.stringTransformer = new StringTransformer();
    this.numberTransformer = new NumberTransformer();
    this.bigIntTransformer = new BigIntTransformer();
    this.literalTransformer = new LiteralTransformer();
    this.enumTransformer = new EnumTransformer();
    this.nativeEnumTransformer = new NativeEnumTransformer();
    this.arrayTransformer = new ArrayTransformer();
    this.unionTransformer = new UnionTransformer();
    this.discriminatedUnionTransformer = new DiscriminatedUnionTransformer();
    this.intersectionTransformer = new IntersectionTransformer();
    this.recordTransformer = new RecordTransformer();
    this.tupleTransformer = new TupleTransformer(versionSpecifics);
  }
  transform(zodSchema, isNullable, mapItem, generateSchemaRef, defaultValue) {
    if (isZodType(zodSchema, "ZodNull")) {
      return this.versionSpecifics.nullType;
    }
    if (isZodType(zodSchema, "ZodUnknown") || isZodType(zodSchema, "ZodAny")) {
      return this.versionSpecifics.mapNullableType(void 0, isNullable);
    }
    if (isZodType(zodSchema, "ZodObject")) {
      return this.objectTransformer.transform(
        zodSchema,
        defaultValue,
        // verified on TS level from input
        // verified on TS level from input
        (_) => this.versionSpecifics.mapNullableType(_, isNullable),
        mapItem
      );
    }
    const schema = this.transformSchemaWithoutDefault(zodSchema, isNullable, mapItem, generateSchemaRef);
    return Object.assign(Object.assign({}, schema), { default: defaultValue });
  }
  transformSchemaWithoutDefault(zodSchema, isNullable, mapItem, generateSchemaRef) {
    if (isZodType(zodSchema, "ZodUnknown") || isZodType(zodSchema, "ZodAny")) {
      return this.versionSpecifics.mapNullableType(void 0, isNullable);
    }
    if (isZodType(zodSchema, "ZodString")) {
      return this.stringTransformer.transform(zodSchema, (schema) => this.versionSpecifics.mapNullableType(schema, isNullable));
    }
    if (isZodType(zodSchema, "ZodNumber")) {
      return this.numberTransformer.transform(zodSchema, (schema) => this.versionSpecifics.mapNullableType(schema, isNullable), (_) => this.versionSpecifics.getNumberChecks(_));
    }
    if (isZodType(zodSchema, "ZodBigInt")) {
      return this.bigIntTransformer.transform((schema) => this.versionSpecifics.mapNullableType(schema, isNullable));
    }
    if (isZodType(zodSchema, "ZodBoolean")) {
      return this.versionSpecifics.mapNullableType("boolean", isNullable);
    }
    if (isZodType(zodSchema, "ZodLiteral")) {
      return this.literalTransformer.transform(zodSchema, (schema) => this.versionSpecifics.mapNullableType(schema, isNullable));
    }
    if (isZodType(zodSchema, "ZodEnum")) {
      return this.enumTransformer.transform(zodSchema, (schema) => this.versionSpecifics.mapNullableType(schema, isNullable));
    }
    if (isZodType(zodSchema, "ZodNativeEnum")) {
      return this.nativeEnumTransformer.transform(zodSchema, (schema) => this.versionSpecifics.mapNullableType(schema, isNullable));
    }
    if (isZodType(zodSchema, "ZodArray")) {
      return this.arrayTransformer.transform(zodSchema, (_) => this.versionSpecifics.mapNullableType(_, isNullable), mapItem);
    }
    if (isZodType(zodSchema, "ZodTuple")) {
      return this.tupleTransformer.transform(zodSchema, (_) => this.versionSpecifics.mapNullableType(_, isNullable), mapItem);
    }
    if (isZodType(zodSchema, "ZodUnion")) {
      return this.unionTransformer.transform(zodSchema, (_) => this.versionSpecifics.mapNullableOfArray(_, isNullable), mapItem);
    }
    if (isZodType(zodSchema, "ZodDiscriminatedUnion")) {
      return this.discriminatedUnionTransformer.transform(zodSchema, isNullable, (_) => this.versionSpecifics.mapNullableOfArray(_, isNullable), mapItem, generateSchemaRef);
    }
    if (isZodType(zodSchema, "ZodIntersection")) {
      return this.intersectionTransformer.transform(zodSchema, isNullable, (_) => this.versionSpecifics.mapNullableOfArray(_, isNullable), mapItem);
    }
    if (isZodType(zodSchema, "ZodRecord")) {
      return this.recordTransformer.transform(zodSchema, (_) => this.versionSpecifics.mapNullableType(_, isNullable), mapItem);
    }
    if (isZodType(zodSchema, "ZodDate")) {
      return this.versionSpecifics.mapNullableType("string", isNullable);
    }
    const refId = Metadata.getRefId(zodSchema);
    throw new UnknownZodTypeError({
      currentSchema: zodSchema._def,
      schemaName: refId
    });
  }
};
__name(OpenApiTransformer, "OpenApiTransformer");
var OpenAPIGenerator = class {
  constructor(definitions, versionSpecifics) {
    this.definitions = definitions;
    this.versionSpecifics = versionSpecifics;
    this.schemaRefs = {};
    this.paramRefs = {};
    this.pathRefs = {};
    this.rawComponents = [];
    this.openApiTransformer = new OpenApiTransformer(versionSpecifics);
    this.sortDefinitions();
  }
  generateDocumentData() {
    this.definitions.forEach((definition) => this.generateSingle(definition));
    return {
      components: this.buildComponents(),
      paths: this.pathRefs
    };
  }
  generateComponents() {
    this.definitions.forEach((definition) => this.generateSingle(definition));
    return {
      components: this.buildComponents()
    };
  }
  buildComponents() {
    var _a2, _b;
    const rawComponents = {};
    this.rawComponents.forEach(({ componentType, name, component }) => {
      var _a3;
      (_a3 = rawComponents[componentType]) !== null && _a3 !== void 0 ? _a3 : rawComponents[componentType] = {};
      rawComponents[componentType][name] = component;
    });
    return Object.assign(Object.assign({}, rawComponents), { schemas: Object.assign(Object.assign({}, (_a2 = rawComponents.schemas) !== null && _a2 !== void 0 ? _a2 : {}), this.schemaRefs), parameters: Object.assign(Object.assign({}, (_b = rawComponents.parameters) !== null && _b !== void 0 ? _b : {}), this.paramRefs) });
  }
  sortDefinitions() {
    const generationOrder = [
      "schema",
      "parameter",
      "component",
      "route"
    ];
    this.definitions.sort((left, right) => {
      if (!("type" in left)) {
        if (!("type" in right)) {
          return 0;
        }
        return -1;
      }
      if (!("type" in right)) {
        return 1;
      }
      const leftIndex = generationOrder.findIndex((type) => type === left.type);
      const rightIndex = generationOrder.findIndex((type) => type === right.type);
      return leftIndex - rightIndex;
    });
  }
  generateSingle(definition) {
    if (!("type" in definition)) {
      this.generateSchemaWithRef(definition);
      return;
    }
    switch (definition.type) {
      case "parameter":
        this.generateParameterDefinition(definition.schema);
        return;
      case "schema":
        this.generateSchemaWithRef(definition.schema);
        return;
      case "route":
        this.generateSingleRoute(definition.route);
        return;
      case "component":
        this.rawComponents.push(definition);
        return;
    }
  }
  generateParameterDefinition(zodSchema) {
    const refId = Metadata.getRefId(zodSchema);
    const result = this.generateParameter(zodSchema);
    if (refId) {
      this.paramRefs[refId] = result;
    }
    return result;
  }
  getParameterRef(schemaMetadata, external) {
    var _a2, _b, _c, _d, _e;
    const parameterMetadata = (_a2 = schemaMetadata === null || schemaMetadata === void 0 ? void 0 : schemaMetadata.metadata) === null || _a2 === void 0 ? void 0 : _a2.param;
    const existingRef = ((_b = schemaMetadata === null || schemaMetadata === void 0 ? void 0 : schemaMetadata._internal) === null || _b === void 0 ? void 0 : _b.refId) ? this.paramRefs[(_c = schemaMetadata._internal) === null || _c === void 0 ? void 0 : _c.refId] : void 0;
    if (!((_d = schemaMetadata === null || schemaMetadata === void 0 ? void 0 : schemaMetadata._internal) === null || _d === void 0 ? void 0 : _d.refId) || !existingRef) {
      return void 0;
    }
    if (parameterMetadata && existingRef.in !== parameterMetadata.in || (external === null || external === void 0 ? void 0 : external.in) && existingRef.in !== external.in) {
      throw new ConflictError(`Conflicting location for parameter ${existingRef.name}`, {
        key: "in",
        values: compact([
          existingRef.in,
          external === null || external === void 0 ? void 0 : external.in,
          parameterMetadata === null || parameterMetadata === void 0 ? void 0 : parameterMetadata.in
        ])
      });
    }
    if (parameterMetadata && existingRef.name !== parameterMetadata.name || (external === null || external === void 0 ? void 0 : external.name) && existingRef.name !== (external === null || external === void 0 ? void 0 : external.name)) {
      throw new ConflictError(`Conflicting names for parameter`, {
        key: "name",
        values: compact([
          existingRef.name,
          external === null || external === void 0 ? void 0 : external.name,
          parameterMetadata === null || parameterMetadata === void 0 ? void 0 : parameterMetadata.name
        ])
      });
    }
    return {
      $ref: `#/components/parameters/${(_e = schemaMetadata._internal) === null || _e === void 0 ? void 0 : _e.refId}`
    };
  }
  generateInlineParameters(zodSchema, location) {
    var _a2;
    const metadata = Metadata.getMetadata(zodSchema);
    const parameterMetadata = (_a2 = metadata === null || metadata === void 0 ? void 0 : metadata.metadata) === null || _a2 === void 0 ? void 0 : _a2.param;
    const referencedSchema = this.getParameterRef(metadata, { in: location });
    if (referencedSchema) {
      return [referencedSchema];
    }
    if (isZodType(zodSchema, "ZodObject")) {
      const propTypes = zodSchema._def.shape();
      const parameters = Object.entries(propTypes).map(([key, schema]) => {
        var _a3, _b;
        const innerMetadata = Metadata.getMetadata(schema);
        const referencedSchema2 = this.getParameterRef(innerMetadata, {
          in: location,
          name: key
        });
        if (referencedSchema2) {
          return referencedSchema2;
        }
        const innerParameterMetadata = (_a3 = innerMetadata === null || innerMetadata === void 0 ? void 0 : innerMetadata.metadata) === null || _a3 === void 0 ? void 0 : _a3.param;
        if ((innerParameterMetadata === null || innerParameterMetadata === void 0 ? void 0 : innerParameterMetadata.name) && innerParameterMetadata.name !== key) {
          throw new ConflictError(`Conflicting names for parameter`, {
            key: "name",
            values: [key, innerParameterMetadata.name]
          });
        }
        if ((innerParameterMetadata === null || innerParameterMetadata === void 0 ? void 0 : innerParameterMetadata.in) && innerParameterMetadata.in !== location) {
          throw new ConflictError(`Conflicting location for parameter ${(_b = innerParameterMetadata.name) !== null && _b !== void 0 ? _b : key}`, {
            key: "in",
            values: [location, innerParameterMetadata.in]
          });
        }
        return this.generateParameter(schema.openapi({ param: { name: key, in: location } }));
      });
      return parameters;
    }
    if ((parameterMetadata === null || parameterMetadata === void 0 ? void 0 : parameterMetadata.in) && parameterMetadata.in !== location) {
      throw new ConflictError(`Conflicting location for parameter ${parameterMetadata.name}`, {
        key: "in",
        values: [location, parameterMetadata.in]
      });
    }
    return [
      this.generateParameter(zodSchema.openapi({ param: { in: location } }))
    ];
  }
  generateSimpleParameter(zodSchema) {
    var _a2;
    const metadata = Metadata.getParamMetadata(zodSchema);
    const paramMetadata = (_a2 = metadata === null || metadata === void 0 ? void 0 : metadata.metadata) === null || _a2 === void 0 ? void 0 : _a2.param;
    const required = !Metadata.isOptionalSchema(zodSchema) && !zodSchema.isNullable();
    const schema = this.generateSchemaWithRef(zodSchema);
    return Object.assign({
      schema,
      required
    }, paramMetadata ? Metadata.buildParameterMetadata(paramMetadata) : {});
  }
  generateParameter(zodSchema) {
    var _a2;
    const metadata = Metadata.getMetadata(zodSchema);
    const paramMetadata = (_a2 = metadata === null || metadata === void 0 ? void 0 : metadata.metadata) === null || _a2 === void 0 ? void 0 : _a2.param;
    const paramName = paramMetadata === null || paramMetadata === void 0 ? void 0 : paramMetadata.name;
    const paramLocation = paramMetadata === null || paramMetadata === void 0 ? void 0 : paramMetadata.in;
    if (!paramName) {
      throw new MissingParameterDataError({ missingField: "name" });
    }
    if (!paramLocation) {
      throw new MissingParameterDataError({
        missingField: "in",
        paramName
      });
    }
    const baseParameter = this.generateSimpleParameter(zodSchema);
    return Object.assign(Object.assign({}, baseParameter), { in: paramLocation, name: paramName });
  }
  generateSchemaWithMetadata(zodSchema) {
    var _a2;
    const innerSchema = Metadata.unwrapChained(zodSchema);
    const metadata = Metadata.getMetadata(zodSchema);
    const defaultValue = Metadata.getDefaultValue(zodSchema);
    const result = ((_a2 = metadata === null || metadata === void 0 ? void 0 : metadata.metadata) === null || _a2 === void 0 ? void 0 : _a2.type) ? { type: metadata === null || metadata === void 0 ? void 0 : metadata.metadata.type } : this.toOpenAPISchema(innerSchema, zodSchema.isNullable(), defaultValue);
    return (metadata === null || metadata === void 0 ? void 0 : metadata.metadata) ? Metadata.applySchemaMetadata(result, metadata.metadata) : omitBy(result, isUndefined);
  }
  /**
   * Same as above but applies nullable
   */
  constructReferencedOpenAPISchema(zodSchema) {
    var _a2;
    const metadata = Metadata.getMetadata(zodSchema);
    const innerSchema = Metadata.unwrapChained(zodSchema);
    const defaultValue = Metadata.getDefaultValue(zodSchema);
    const isNullableSchema = zodSchema.isNullable();
    if ((_a2 = metadata === null || metadata === void 0 ? void 0 : metadata.metadata) === null || _a2 === void 0 ? void 0 : _a2.type) {
      return this.versionSpecifics.mapNullableType(metadata.metadata.type, isNullableSchema);
    }
    return this.toOpenAPISchema(innerSchema, isNullableSchema, defaultValue);
  }
  /**
   * Generates an OpenAPI SchemaObject or a ReferenceObject with all the provided metadata applied
   */
  generateSimpleSchema(zodSchema) {
    var _a2;
    const metadata = Metadata.getMetadata(zodSchema);
    const refId = Metadata.getRefId(zodSchema);
    if (!refId || !this.schemaRefs[refId]) {
      return this.generateSchemaWithMetadata(zodSchema);
    }
    const schemaRef = this.schemaRefs[refId];
    const referenceObject = {
      $ref: this.generateSchemaRef(refId)
    };
    const newMetadata = omitBy(Metadata.buildSchemaMetadata((_a2 = metadata === null || metadata === void 0 ? void 0 : metadata.metadata) !== null && _a2 !== void 0 ? _a2 : {}), (value, key) => value === void 0 || objectEquals(value, schemaRef[key]));
    if (newMetadata.type) {
      return {
        allOf: [referenceObject, newMetadata]
      };
    }
    const newSchemaMetadata = omitBy(this.constructReferencedOpenAPISchema(zodSchema), (value, key) => value === void 0 || objectEquals(value, schemaRef[key]));
    const appliedMetadata = Metadata.applySchemaMetadata(newSchemaMetadata, newMetadata);
    if (Object.keys(appliedMetadata).length > 0) {
      return {
        allOf: [referenceObject, appliedMetadata]
      };
    }
    return referenceObject;
  }
  /**
   * Same as `generateSchema` but if the new schema is added into the
   * referenced schemas, it would return a ReferenceObject and not the
   * whole result.
   *
   * Should be used for nested objects, arrays, etc.
   */
  generateSchemaWithRef(zodSchema) {
    const refId = Metadata.getRefId(zodSchema);
    const result = this.generateSimpleSchema(zodSchema);
    if (refId && this.schemaRefs[refId] === void 0) {
      this.schemaRefs[refId] = result;
      return { $ref: this.generateSchemaRef(refId) };
    }
    return result;
  }
  generateSchemaRef(refId) {
    return `#/components/schemas/${refId}`;
  }
  getRequestBody(requestBody) {
    if (!requestBody) {
      return;
    }
    const { content } = requestBody, rest = __rest(requestBody, ["content"]);
    const requestBodyContent = this.getBodyContent(content);
    return Object.assign(Object.assign({}, rest), { content: requestBodyContent });
  }
  getParameters(request) {
    if (!request) {
      return [];
    }
    const { headers } = request;
    const query = this.cleanParameter(request.query);
    const params = this.cleanParameter(request.params);
    const cookies = this.cleanParameter(request.cookies);
    const queryParameters = enhanceMissingParametersError(() => query ? this.generateInlineParameters(query, "query") : [], { location: "query" });
    const pathParameters = enhanceMissingParametersError(() => params ? this.generateInlineParameters(params, "path") : [], { location: "path" });
    const cookieParameters = enhanceMissingParametersError(() => cookies ? this.generateInlineParameters(cookies, "cookie") : [], { location: "cookie" });
    const headerParameters = enhanceMissingParametersError(() => {
      if (Array.isArray(headers)) {
        return headers.flatMap((header) => this.generateInlineParameters(header, "header"));
      }
      const cleanHeaders = this.cleanParameter(headers);
      return cleanHeaders ? this.generateInlineParameters(cleanHeaders, "header") : [];
    }, { location: "header" });
    return [
      ...pathParameters,
      ...queryParameters,
      ...headerParameters,
      ...cookieParameters
    ];
  }
  cleanParameter(schema) {
    if (!schema) {
      return void 0;
    }
    return isZodType(schema, "ZodEffects") ? this.cleanParameter(schema._def.schema) : schema;
  }
  generatePath(route) {
    const { method, path, request, responses } = route, pathItemConfig = __rest(route, ["method", "path", "request", "responses"]);
    const generatedResponses = mapValues(responses, (response) => {
      return this.getResponse(response);
    });
    const parameters = enhanceMissingParametersError(() => this.getParameters(request), { route: `${method} ${path}` });
    const requestBody = this.getRequestBody(request === null || request === void 0 ? void 0 : request.body);
    const routeDoc = {
      [method]: Object.assign(Object.assign(Object.assign(Object.assign({}, pathItemConfig), parameters.length > 0 ? {
        parameters: [...pathItemConfig.parameters || [], ...parameters]
      } : {}), requestBody ? { requestBody } : {}), { responses: generatedResponses })
    };
    return routeDoc;
  }
  generateSingleRoute(route) {
    const routeDoc = this.generatePath(route);
    this.pathRefs[route.path] = Object.assign(Object.assign({}, this.pathRefs[route.path]), routeDoc);
    return routeDoc;
  }
  getResponse(response) {
    if (this.isReferenceObject(response)) {
      return response;
    }
    const { content, headers } = response, rest = __rest(response, ["content", "headers"]);
    const responseContent = content ? { content: this.getBodyContent(content) } : {};
    if (!headers) {
      return Object.assign(Object.assign({}, rest), responseContent);
    }
    const responseHeaders = isZodType(headers, "ZodObject") ? this.getResponseHeaders(headers) : (
      // This is input data so it is okay to cast in the common generator
      // since this is the user's responsibility to keep it correct
      headers
    );
    return Object.assign(Object.assign(Object.assign({}, rest), { headers: responseHeaders }), responseContent);
  }
  isReferenceObject(schema) {
    return "$ref" in schema;
  }
  getResponseHeaders(headers) {
    const schemaShape = headers._def.shape();
    const responseHeaders = mapValues(schemaShape, (_) => this.generateSimpleParameter(_));
    return responseHeaders;
  }
  getBodyContent(content) {
    return mapValues(content, (config2) => {
      if (!config2 || !isAnyZodType(config2.schema)) {
        return config2;
      }
      const { schema: configSchema } = config2, rest = __rest(config2, ["schema"]);
      const schema = this.generateSchemaWithRef(configSchema);
      return Object.assign({ schema }, rest);
    });
  }
  toOpenAPISchema(zodSchema, isNullable, defaultValue) {
    return this.openApiTransformer.transform(zodSchema, isNullable, (_) => this.generateSchemaWithRef(_), (_) => this.generateSchemaRef(_), defaultValue);
  }
};
__name(OpenAPIGenerator, "OpenAPIGenerator");
var OpenApiGeneratorV31Specifics = class {
  get nullType() {
    return { type: "null" };
  }
  mapNullableOfArray(objects, isNullable) {
    if (isNullable) {
      return [...objects, this.nullType];
    }
    return objects;
  }
  mapNullableType(type, isNullable) {
    if (!type) {
      return {};
    }
    if (isNullable) {
      return {
        type: Array.isArray(type) ? [...type, "null"] : [type, "null"]
      };
    }
    return {
      type
    };
  }
  mapTupleItems(schemas) {
    return {
      prefixItems: schemas
    };
  }
  getNumberChecks(checks) {
    return Object.assign({}, ...checks.map((check) => {
      switch (check.kind) {
        case "min":
          return check.inclusive ? { minimum: Number(check.value) } : { exclusiveMinimum: Number(check.value) };
        case "max":
          return check.inclusive ? { maximum: Number(check.value) } : { exclusiveMaximum: Number(check.value) };
        default:
          return {};
      }
    }));
  }
};
__name(OpenApiGeneratorV31Specifics, "OpenApiGeneratorV31Specifics");
function isWebhookDefinition(definition) {
  return "type" in definition && definition.type === "webhook";
}
__name(isWebhookDefinition, "isWebhookDefinition");
var OpenApiGeneratorV31 = class {
  constructor(definitions) {
    this.definitions = definitions;
    this.webhookRefs = {};
    const specifics = new OpenApiGeneratorV31Specifics();
    this.generator = new OpenAPIGenerator(this.definitions, specifics);
  }
  generateDocument(config2) {
    const baseDocument = this.generator.generateDocumentData();
    this.definitions.filter(isWebhookDefinition).forEach((definition) => this.generateSingleWebhook(definition.webhook));
    return Object.assign(Object.assign(Object.assign({}, config2), baseDocument), { webhooks: this.webhookRefs });
  }
  generateComponents() {
    return this.generator.generateComponents();
  }
  generateSingleWebhook(route) {
    const routeDoc = this.generator.generatePath(route);
    this.webhookRefs[route.path] = Object.assign(Object.assign({}, this.webhookRefs[route.path]), routeDoc);
    return routeDoc;
  }
};
__name(OpenApiGeneratorV31, "OpenApiGeneratorV31");

// node_modules/hono/dist/utils/cookie.js
var algorithm = { name: "HMAC", hash: "SHA-256" };
var getCryptoKey = /* @__PURE__ */ __name(async (secret) => {
  const secretBuf = typeof secret === "string" ? new TextEncoder().encode(secret) : secret;
  return await crypto.subtle.importKey("raw", secretBuf, algorithm, false, ["sign", "verify"]);
}, "getCryptoKey");
var makeSignature = /* @__PURE__ */ __name(async (value, secret) => {
  const key = await getCryptoKey(secret);
  const signature = await crypto.subtle.sign(algorithm.name, key, new TextEncoder().encode(value));
  return btoa(String.fromCharCode(...new Uint8Array(signature)));
}, "makeSignature");
var verifySignature = /* @__PURE__ */ __name(async (base64Signature, value, secret) => {
  try {
    const signatureBinStr = atob(base64Signature);
    const signature = new Uint8Array(signatureBinStr.length);
    for (let i = 0, len = signatureBinStr.length; i < len; i++) {
      signature[i] = signatureBinStr.charCodeAt(i);
    }
    return await crypto.subtle.verify(algorithm, secret, signature, new TextEncoder().encode(value));
  } catch {
    return false;
  }
}, "verifySignature");
var validCookieNameRegEx = /^[\w!#$%&'*.^`|~+-]+$/;
var validCookieValueRegEx = /^[ !#-:<-[\]-~]*$/;
var parse = /* @__PURE__ */ __name((cookie, name) => {
  if (name && cookie.indexOf(name) === -1) {
    return {};
  }
  const pairs = cookie.trim().split(";");
  const parsedCookie = {};
  for (let pairStr of pairs) {
    pairStr = pairStr.trim();
    const valueStartPos = pairStr.indexOf("=");
    if (valueStartPos === -1) {
      continue;
    }
    const cookieName2 = pairStr.substring(0, valueStartPos).trim();
    if (name && name !== cookieName2 || !validCookieNameRegEx.test(cookieName2)) {
      continue;
    }
    let cookieValue = pairStr.substring(valueStartPos + 1).trim();
    if (cookieValue.startsWith('"') && cookieValue.endsWith('"')) {
      cookieValue = cookieValue.slice(1, -1);
    }
    if (validCookieValueRegEx.test(cookieValue)) {
      parsedCookie[cookieName2] = decodeURIComponent_(cookieValue);
      if (name) {
        break;
      }
    }
  }
  return parsedCookie;
}, "parse");
var parseSigned = /* @__PURE__ */ __name(async (cookie, secret, name) => {
  const parsedCookie = {};
  const secretKey = await getCryptoKey(secret);
  for (const [key, value] of Object.entries(parse(cookie, name))) {
    const signatureStartPos = value.lastIndexOf(".");
    if (signatureStartPos < 1) {
      continue;
    }
    const signedValue = value.substring(0, signatureStartPos);
    const signature = value.substring(signatureStartPos + 1);
    if (signature.length !== 44 || !signature.endsWith("=")) {
      continue;
    }
    const isVerified = await verifySignature(signature, signedValue, secretKey);
    parsedCookie[key] = isVerified ? signedValue : false;
  }
  return parsedCookie;
}, "parseSigned");
var _serialize = /* @__PURE__ */ __name((name, value, opt = {}) => {
  let cookie = `${name}=${value}`;
  if (name.startsWith("__Secure-") && !opt.secure) {
    throw new Error("__Secure- Cookie must have Secure attributes");
  }
  if (name.startsWith("__Host-")) {
    if (!opt.secure) {
      throw new Error("__Host- Cookie must have Secure attributes");
    }
    if (opt.path !== "/") {
      throw new Error('__Host- Cookie must have Path attributes with "/"');
    }
    if (opt.domain) {
      throw new Error("__Host- Cookie must not have Domain attributes");
    }
  }
  if (opt && typeof opt.maxAge === "number" && opt.maxAge >= 0) {
    if (opt.maxAge > 3456e4) {
      throw new Error(
        "Cookies Max-Age SHOULD NOT be greater than 400 days (34560000 seconds) in duration."
      );
    }
    cookie += `; Max-Age=${opt.maxAge | 0}`;
  }
  if (opt.domain && opt.prefix !== "host") {
    cookie += `; Domain=${opt.domain}`;
  }
  if (opt.path) {
    cookie += `; Path=${opt.path}`;
  }
  if (opt.expires) {
    if (opt.expires.getTime() - Date.now() > 3456e7) {
      throw new Error(
        "Cookies Expires SHOULD NOT be greater than 400 days (34560000 seconds) in the future."
      );
    }
    cookie += `; Expires=${opt.expires.toUTCString()}`;
  }
  if (opt.httpOnly) {
    cookie += "; HttpOnly";
  }
  if (opt.secure) {
    cookie += "; Secure";
  }
  if (opt.sameSite) {
    cookie += `; SameSite=${opt.sameSite.charAt(0).toUpperCase() + opt.sameSite.slice(1)}`;
  }
  if (opt.partitioned) {
    if (!opt.secure) {
      throw new Error("Partitioned Cookie must have Secure attributes");
    }
    cookie += "; Partitioned";
  }
  return cookie;
}, "_serialize");
var serialize = /* @__PURE__ */ __name((name, value, opt) => {
  value = encodeURIComponent(value);
  return _serialize(name, value, opt);
}, "serialize");
var serializeSigned = /* @__PURE__ */ __name(async (name, value, secret, opt = {}) => {
  const signature = await makeSignature(value, secret);
  value = `${value}.${signature}`;
  value = encodeURIComponent(value);
  return _serialize(name, value, opt);
}, "serializeSigned");

// node_modules/hono/dist/helper/cookie/index.js
var getCookie = /* @__PURE__ */ __name((c, key, prefix) => {
  const cookie = c.req.raw.headers.get("Cookie");
  if (typeof key === "string") {
    if (!cookie) {
      return void 0;
    }
    let finalKey = key;
    if (prefix === "secure") {
      finalKey = "__Secure-" + key;
    } else if (prefix === "host") {
      finalKey = "__Host-" + key;
    }
    const obj2 = parse(cookie, finalKey);
    return obj2[finalKey];
  }
  if (!cookie) {
    return {};
  }
  const obj = parse(cookie);
  return obj;
}, "getCookie");
var getSignedCookie = /* @__PURE__ */ __name(async (c, secret, key, prefix) => {
  const cookie = c.req.raw.headers.get("Cookie");
  if (typeof key === "string") {
    if (!cookie) {
      return void 0;
    }
    let finalKey = key;
    if (prefix === "secure") {
      finalKey = "__Secure-" + key;
    } else if (prefix === "host") {
      finalKey = "__Host-" + key;
    }
    const obj2 = await parseSigned(cookie, secret, finalKey);
    return obj2[finalKey];
  }
  if (!cookie) {
    return {};
  }
  const obj = await parseSigned(cookie, secret);
  return obj;
}, "getSignedCookie");
var setCookie = /* @__PURE__ */ __name((c, name, value, opt) => {
  let cookie;
  if (opt?.prefix === "secure") {
    cookie = serialize("__Secure-" + name, value, { path: "/", ...opt, secure: true });
  } else if (opt?.prefix === "host") {
    cookie = serialize("__Host-" + name, value, {
      ...opt,
      path: "/",
      secure: true,
      domain: void 0
    });
  } else {
    cookie = serialize(name, value, { path: "/", ...opt });
  }
  c.header("Set-Cookie", cookie, { append: true });
}, "setCookie");
var setSignedCookie = /* @__PURE__ */ __name(async (c, name, value, secret, opt) => {
  let cookie;
  if (opt?.prefix === "secure") {
    cookie = await serializeSigned("__Secure-" + name, value, secret, {
      path: "/",
      ...opt,
      secure: true
    });
  } else if (opt?.prefix === "host") {
    cookie = await serializeSigned("__Host-" + name, value, secret, {
      ...opt,
      path: "/",
      secure: true,
      domain: void 0
    });
  } else {
    cookie = await serializeSigned(name, value, secret, { path: "/", ...opt });
  }
  c.header("set-cookie", cookie, { append: true });
}, "setSignedCookie");
var deleteCookie = /* @__PURE__ */ __name((c, name, opt) => {
  const deletedCookie = getCookie(c, name);
  setCookie(c, name, "", { ...opt, maxAge: 0 });
  return deletedCookie;
}, "deleteCookie");

// node_modules/@hono/zod-openapi/dist/index.mjs
extendZodWithOpenApi(external_exports);

// node_modules/teenybase/dist/worker/email/resend.js
var ResendHelper = class {
  baseUrl = "https://api.resend.com/emails";
  bindings;
  constructor(bindings) {
    this.bindings = bindings;
    if (bindings.RESEND_API_URL?.startsWith("https://"))
      this.baseUrl = bindings.RESEND_API_URL;
    else if (bindings.RESEND_API_URL)
      throw new HTTPException(400, { message: "Invalid Resend configuration" });
    if (!this.bindings.RESEND_API_KEY) {
      throw new Error("Invalid Resend configuration - missing RESEND_API_KEY");
    }
  }
  async sendEmail({ from, to, subject, html: html2, tags }) {
    to = Array.isArray(to) ? to : [to];
    to.forEach((recipient) => checkBlocklist(recipient, this.bindings.EMAIL_BLOCKLIST));
    const payload = { from, to, subject, html: html2 };
    if (tags)
      payload.tags = tags;
    const _key = this.bindings.RESEND_API_KEY;
    const key = typeof _key === "string" || !_key ? _key : await _key();
    if (!key)
      throw new HTTPException(500, { message: "Invalid resend configuration - missing RESEND_API_KEY" });
    const res = await fetch(this.baseUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    }).catch((e) => {
      console.error("Failed to fetch resend", e);
      return new Response("Failed to fetch resend - " + e.message || e, { status: 500 });
    });
    let resJson = void 0;
    let resp = "";
    try {
      resp = await res.text();
      resJson = JSON.parse(resp);
    } catch (e) {
      console.error("Failed to parse resend response", e);
    }
    if (!resJson || !res.ok) {
      console.error("Error sending email, ", res?.status, resp);
      if (this.bindings.DISCORD_RESEND_NOTIFY_WEBHOOK)
        await discordNotify(this.bindings.DISCORD_RESEND_NOTIFY_WEBHOOK, `Failed to send email(\`${res.status}\`) to \`${to}\` 
\`\`\`${resp}\`\`\``);
      throw new HTTPException(500, { message: "Failed to send email" });
    }
    return resJson;
  }
  async receiveWebhook(headers, body) {
    let data;
    try {
      data = JSON.parse(body);
    } catch (e) {
      console.error("Failed to parse resend webhook data", e);
      throw new HTTPException(400, { message: "Invalid resend webhook data" });
    }
    const _key = this.bindings.RESEND_WEBHOOK_SECRET;
    const key = typeof _key === "string" || !_key ? _key : await _key();
    const verified = !key || !data ? false : await verify3({ headers, body, secret: key });
    let message = "";
    if (!verified) {
      console.error("Invalid Webhook Signature", body);
      message += "[Invalid Webhook Signature]\n";
    }
    const parsed = zResendWebhookData.safeParse(data);
    let eventData;
    if (!parsed.success) {
      console.error("Invalid Webhook Data", parsed.error);
      message += `[Invalid Webhook Data] ${parsed.error}
`;
      eventData = data;
    } else {
      eventData = parsed.data;
    }
    const timestamp = headers["svix-timestamp"] ?? Date.now();
    const event = eventData.data;
    const recipient = (Array.isArray(event.to) ? event.to : [event.to]).join(", ");
    message += `${eventData.type} at ${new Date(parseInt(timestamp) * 1e3).toISOString()}
`;
    if (recipient)
      message += `Recipient: ${JSON.stringify(eventData.data.to)}
`;
    const notifyEvents = [
      "email.bounced",
      "email.complained",
      "email.delivery_delayed",
      "contact.deleted",
      "domain.deleted"
    ];
    if (notifyEvents.includes(eventData.type)) {
      const res = this.bindings.DISCORD_RESEND_NOTIFY_WEBHOOK ? await discordNotify(this.bindings.DISCORD_RESEND_NOTIFY_WEBHOOK, message, [new File([body], "event.json", {
        type: "application/json"
      })]) : false;
      if (!res) {
        console.error(message, event);
        if (this.bindings.DISCORD_RESEND_NOTIFY_WEBHOOK)
          throw new HTTPException(406, { message: "Failed to notify destination" });
      }
    } else {
      console.log("Unhandled event type:", eventData.type);
    }
  }
  getRoutes(c) {
    const path = "/resend/webhook/:wid?";
    const handler = {
      raw: async (params) => {
        const wid = params?.wid;
        if ((c.env.RESEND_WEBHOOK_ID || wid) && wid !== c.env.RESEND_WEBHOOK_ID)
          throw new HTTPException(404, { message: "Not found" });
        let body;
        try {
          body = await c.req.text();
        } catch (e) {
          throw new HTTPException(400, { message: "Invalid resend webhook data" });
        }
        await this.receiveWebhook(c.req.header(), body);
        return c.json({ message: "Received" }, 200);
      }
    };
    const zod = /* @__PURE__ */ __name(() => ({
      description: "Resend webhook. Webhook can send email errors/events to this endpoint",
      request: {
        headers: external_exports.object({}),
        params: external_exports.object({ wid: external_exports.string().optional().describe("Optional id for the webhook.") }),
        body: {
          required: true,
          content: { "application/json": { schema: zResendWebhookData } }
        }
      },
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": { schema: external_exports.object({ message: external_exports.literal("Received") }) } }
        },
        "400": { description: "Invalid resend webhook data, retry in some time." },
        "406": { description: "Invalid resend webhook signature, don't retry" },
        "500": { description: "Failed to notify destination or other error, retry in some time." }
      }
    }), "zod");
    return [{ method: "get", path, handler, zod }, { method: "post", path, handler, zod }];
  }
};
__name(ResendHelper, "ResendHelper");
var zResendWebhookData = external_exports.object({
  type: external_exports.string(),
  created_at: external_exports.string(),
  data: external_exports.object({
    created_at: external_exports.string(),
    email_id: external_exports.string(),
    from: external_exports.string(),
    to: external_exports.union([external_exports.string(), external_exports.array(external_exports.string())]),
    subject: external_exports.string().optional(),
    bounce: external_exports.object({
      message: external_exports.string().optional(),
      subType: external_exports.string().optional(),
      type: external_exports.string().optional()
    }).optional()
  })
});
async function verify3({ headers, body, secret }) {
  const svixId = headers["svix-id"];
  const svixTimestamp = headers["svix-timestamp"];
  const svixSignature = headers["svix-signature"];
  if (!svixId || !svixTimestamp || !svixSignature) {
    console.error("Invalid webhook headers", headers);
    return false;
  }
  const signedContent = `${svixId}.${svixTimestamp}.${body}`;
  const encoder = new TextEncoder();
  const keyData = encoder.encode(atob(secret.split("_")[1]));
  const message = encoder.encode(signedContent);
  const key = await crypto.subtle.importKey("raw", keyData, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signatureBuffer = await crypto.subtle.sign("HMAC", key, message);
  const b64encoded = btoa(String.fromCharCode(...new Uint8Array(signatureBuffer)));
  return b64encoded === svixSignature;
}
__name(verify3, "verify");

// node_modules/teenybase/dist/worker/email/send-email.js
function buildEmailTemplate(templates) {
  return templates.reduce((acc, t) => acc.replace("{{EMAIL_CONTENT}}", t), "{{EMAIL_CONTENT}}");
}
__name(buildEmailTemplate, "buildEmailTemplate");
var EmailSendClient = class extends $DBExtension {
  props;
  mg;
  rd;
  constructor(db, props, mg, rd) {
    super(db);
    this.props = props;
    this.mg = mg ? new MailgunHelper(mg) : null;
    this.rd = rd ? new ResendHelper(rd) : null;
    this.mg && this.routes.push(...this.mg.getRoutes(this.db.c));
    this.rd && this.routes.push(...this.rd.getRoutes(this.db.c));
  }
  templates = {
    actionLink: [baseLayout1, messageLayout1, actionLinkTemplate],
    actionText: [baseLayout1, messageLayout1, actionTextTemplate]
  };
  sendActionLink(prop) {
    if (!prop.variables.action_link)
      throw new Error("action_link is required");
    if (!prop.variables.action_text)
      prop.variables.action_text = "Click here";
    return this.sendEmail({
      html: buildEmailTemplate(this.templates.actionLink),
      ...prop,
      tags: ["action-link", ...prop.tags || []]
    });
  }
  sendActionText(prop) {
    if (!prop.variables.action_text)
      throw new Error("action_text is required");
    return this.sendEmail({
      html: buildEmailTemplate(this.templates.actionLink),
      ...prop,
      tags: ["action-text", ...prop.tags || []]
    });
  }
  sendEmail(prop) {
    const props = {
      ...this.props,
      ...prop,
      variables: {
        ...this.props.variables,
        ...prop.variables
      },
      tags: [...this.props.tags || [], ...prop.tags || []]
    };
    if (!props.html)
      throw new Error("html is required");
    if (!props.subject)
      throw new Error("html is required");
    if (props.variables) {
      props.html = replaceTemplateVariables(props.html, props.variables, 3);
      props.subject = replaceTemplateVariables(props.subject, props.variables, 2);
      delete props.variables;
    }
    if (!props.to)
      throw new Error("to is required");
    if (!props.subject)
      throw new Error("subject is required");
    if (!props.from)
      throw new Error("from is required");
    if (this.mg) {
      return this.mg.sendEmail({
        from: props.from,
        html: props.html,
        subject: props.subject,
        tags: props.tags || [],
        to: props.to
      });
    } else if (this.rd) {
      return this.rd.sendEmail({
        from: props.from,
        html: props.html,
        subject: props.subject,
        tags: props.tags.map((t) => ({ name: t, value: "true" })) || [],
        to: props.to
      });
    } else
      throw new HTTPException(500, { message: "Email provider not configured" });
  }
};
__name(EmailSendClient, "EmailSendClient");

// node_modules/teenybase/dist/worker/internalKV.js
var InternalKV = class {
  db;
  tableName;
  constructor(db, tableName = "_ddb_internal_kv") {
    this.db = db;
    this.tableName = tableName;
  }
  async setup(version2) {
    if (version2 >= 0) {
      const sql = `
            CREATE TABLE IF NOT EXISTS "${this.tableName}" (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                expiry INTEGER NULL
            )`.split("\n").map((l) => l.trim()).join(" ");
      await this.db.rawSQL({ q: sql, v: [] }).run();
    }
  }
  async get(key, field) {
    const rnd = "_" + Math.random().toString(36).substring(7);
    const q = `SELECT (${field || "value"}) as ${rnd} FROM ${this.tableName} WHERE key = ? AND (expiry IS NULL OR expiry > unixepoch(CURRENT_TIMESTAMP))`;
    const res = await this.db.rawSQL({ q, v: [key] }).run();
    return res?.[0] ? res[0][rnd] : null;
  }
  async pop(key, field) {
    const rnd = "_" + Math.random().toString(36).substring(7);
    const q = `DELETE FROM ${this.tableName} WHERE key = ? AND (expiry IS NULL OR expiry > unixepoch(CURRENT_TIMESTAMP)) RETURNING (${field || "value"}) as ${rnd}`;
    const res = await this.db.rawSQL({ q, v: [key] }).run();
    return res?.[0] ? res[0][rnd] : null;
  }
  async get2(key, ...fields) {
    const q = `SELECT value, expiry, ${fields.join(", ")} FROM ${this.tableName} WHERE key = ? AND (expiry IS NULL OR expiry > unixepoch(CURRENT_TIMESTAMP))`;
    const res = await this.db.rawSQL({ q, v: [key] }).run();
    return res?.[0] || null;
  }
  async set(key, value, expiryOffsetSeconds) {
    return this.db.rawSQL(this.setQuery(key, value, expiryOffsetSeconds)).run();
  }
  setQuery(key, value, expiryOffsetSeconds) {
    const s = typeof value !== "string";
    if (typeof expiryOffsetSeconds !== "number" || isNaN(expiryOffsetSeconds)) {
      expiryOffsetSeconds = 1;
    }
    const q = `INSERT OR REPLACE INTO ${this.tableName} (key, value, expiry) VALUES (?, ${s ? value.sql || "''" : "?"}, ${expiryOffsetSeconds ? `unixepoch(CURRENT_TIMESTAMP) + ${expiryOffsetSeconds}` : "NULL"})`;
    const b = [key];
    if (!s)
      b.push(value);
    return { q, v: b };
  }
  async setMultiple(data, expiryOffsetSeconds) {
    const qs = [];
    const b = [];
    const expiry = expiryOffsetSeconds ? `unixepoch(CURRENT_TIMESTAMP) + ${expiryOffsetSeconds}` : "NULL";
    for (const [key, value] of Object.entries(data)) {
      const s = typeof value !== "string";
      qs.push(`(?, ${s ? value.sql || "''" : "?"}, ${expiry})`);
      b.push(key);
      if (!s)
        b.push(value);
    }
    const q = `INSERT OR REPLACE INTO ${this.tableName} (key, value, expiry) VALUES ${qs.join(", ")}`;
    return this.db.rawSQL({ q, v: b }).run();
  }
  async remove(key) {
    const q = `DELETE FROM ${this.tableName} WHERE key = ?`;
    await this.db.rawSQL({ q, v: [key] }).run();
  }
  async setSql(key, value, expiryOffsetSeconds) {
    return await this.set(key, { sql: value }, expiryOffsetSeconds);
  }
};
__name(InternalKV, "InternalKV");

// node_modules/teenybase/dist/sql/build/d1.js
function sqlQueryToD1Query(query) {
  if (!query.p)
    return { q: query.q, v: [] };
  const regex = /(?:^|\s|\W)\{\:([a-zA-Z0-9_]+)\}(?:\s|\W|$)/g;
  const matches = query.q.match(regex);
  if (!matches?.length)
    return { q: query.q, v: [] };
  let { p, q } = query;
  const vals = [];
  for (const m1 of matches) {
    const m = m1.trim();
    const key = m.split("{:")[1].split("}")[0];
    let v = p?.[key];
    if (v === void 0) {
      console.warn("Missing parameter", key, "in params.", q, p);
      throw new Error(`Missing parameter ${key} in params.`);
    }
    q = q.replace("{:" + key + "}", "?");
    if (v !== null && (typeof v === "object" || Array.isArray(v))) {
      v = JSON.stringify(v);
    }
    vals.push(v);
  }
  return { q, v: vals };
}
__name(sqlQueryToD1Query, "sqlQueryToD1Query");

// node_modules/teenybase/dist/worker/wrangler/d1/trimmer.js
function trimSqlQuery(sql) {
  if (!mayContainTransaction(sql)) {
    return sql;
  }
  const trimmedSql = sql.replace("BEGIN TRANSACTION;", "").replace("COMMIT;", "");
  if (mayContainTransaction(trimmedSql)) {
    throw new Error("Wrangler could not process the provided SQL file, as it contains several transactions.\nD1 runs your SQL in a transaction for you.\nPlease export an SQL file from your SQLite database and try again.");
  }
  return trimmedSql;
}
__name(trimSqlQuery, "trimSqlQuery");
function mayContainTransaction(sql) {
  return sql.includes("BEGIN TRANSACTION");
}
__name(mayContainTransaction, "mayContainTransaction");

// node_modules/teenybase/dist/worker/wrangler/d1/splitter.js
function mayContainMultipleStatements(sql) {
  const trimmed = sql.trimEnd();
  const semiColonIndex = trimmed.indexOf(";");
  return semiColonIndex !== -1 && semiColonIndex !== trimmed.length - 1;
}
__name(mayContainMultipleStatements, "mayContainMultipleStatements");
function splitSqlQuery(sql) {
  const trimmedSql = trimSqlQuery(sql);
  if (!mayContainMultipleStatements(trimmedSql)) {
    return [trimmedSql];
  }
  const split = splitSqlIntoStatements(trimmedSql);
  if (split.length === 0) {
    return [trimmedSql];
  } else {
    return split;
  }
}
__name(splitSqlQuery, "splitSqlQuery");
function splitSqlIntoStatements(sql) {
  const statements = [];
  let str = "";
  const compoundStatementStack = [];
  const iterator = sql[Symbol.iterator]();
  let next = iterator.next();
  while (!next.done) {
    const char = next.value;
    if (compoundStatementStack[0]?.(str + char)) {
      compoundStatementStack.shift();
    }
    switch (char) {
      case `'`:
      case `"`:
      case "`":
        str += char + consumeUntilMarker(iterator, char);
        break;
      case `$`: {
        const dollarQuote = "$" + consumeWhile(iterator, isDollarQuoteIdentifier);
        str += dollarQuote;
        if (dollarQuote.endsWith("$")) {
          str += consumeUntilMarker(iterator, dollarQuote);
        }
        break;
      }
      case `-`:
        str += char;
        next = iterator.next();
        if (!next.done && next.value === "-") {
          str += next.value + consumeUntilMarker(iterator, "\n");
          break;
        } else {
          continue;
        }
      case `/`:
        str += char;
        next = iterator.next();
        if (!next.done && next.value === "*") {
          str += next.value + consumeUntilMarker(iterator, "*/");
          break;
        } else {
          continue;
        }
      case `;`:
        if (compoundStatementStack.length === 0) {
          statements.push(str);
          str = "";
        } else {
          str += char;
        }
        break;
      default:
        str += char;
        break;
    }
    if (isCompoundStatementStart(str)) {
      compoundStatementStack.unshift(isCompoundStatementEnd);
    }
    next = iterator.next();
  }
  statements.push(str);
  return statements.map((statement) => statement.trim()).filter((statement) => statement.length > 0);
}
__name(splitSqlIntoStatements, "splitSqlIntoStatements");
function consumeWhile(iterator, predicate) {
  let next = iterator.next();
  let str = "";
  while (!next.done) {
    str += next.value;
    if (!predicate(str)) {
      break;
    }
    next = iterator.next();
  }
  return str;
}
__name(consumeWhile, "consumeWhile");
function consumeUntilMarker(iterator, endMarker) {
  return consumeWhile(iterator, (str) => !str.endsWith(endMarker));
}
__name(consumeUntilMarker, "consumeUntilMarker");
function isDollarQuoteIdentifier(str) {
  const lastChar = str.slice(-1);
  return (
    // The $ marks the end of the identifier
    lastChar !== "$" && // we allow numbers, underscore and letters with diacritical marks
    (/[0-9_]/i.test(lastChar) || lastChar.toLowerCase() !== lastChar.toUpperCase())
  );
}
__name(isDollarQuoteIdentifier, "isDollarQuoteIdentifier");
function isCompoundStatementStart(str) {
  return /\s(BEGIN|CASE)\s$/i.test(str);
}
__name(isCompoundStatementStart, "isCompoundStatementStart");
function isCompoundStatementEnd(str) {
  return /\sEND[;\s]$/.test(str);
}
__name(isCompoundStatementEnd, "isCompoundStatementEnd");

// node_modules/teenybase/dist/types/zod/tableFieldDataSchema.js
var zForeignKeyAction = external_exports.enum(["SET NULL", "SET DEFAULT", "CASCADE", "RESTRICT", "NO ACTION"]);
var tableFieldDataSchema = external_exports.object({
  name: external_exports.string(),
  sqlType: external_exports.nativeEnum(TableFieldSqlDataType0).or(external_exports.nativeEnum(TableFieldSqlDataType1)),
  type: external_exports.nativeEnum(TableFieldDataType),
  usage: external_exports.string().optional(),
  primary: external_exports.coerce.boolean().optional(),
  autoIncrement: external_exports.coerce.boolean().optional(),
  unique: external_exports.coerce.boolean().optional(),
  notNull: external_exports.coerce.boolean().optional(),
  collate: external_exports.string().optional(),
  // todo enum
  default: zSQLQueryOrLiteral.or(external_exports.string()).optional(),
  check: zSQLQueryOrLiteral.or(external_exports.string()).optional(),
  foreignKey: external_exports.object({
    table: external_exports.string(),
    column: external_exports.string(),
    onUpdate: zForeignKeyAction.optional(),
    onDelete: zForeignKeyAction.optional()
  }).optional(),
  // updateTriggers: z.array(zSQLTrigger.omit({updateOf: true, event: true})).optional(),
  noUpdate: external_exports.coerce.boolean().optional(),
  noInsert: external_exports.coerce.boolean().optional(),
  noSelect: external_exports.coerce.boolean().optional(),
  lastName: external_exports.string().optional()
});

// node_modules/teenybase/dist/types/zod/tableDataSchema.js
var tableDataSchema = external_exports.object({
  // id: z.string(),
  name: tableColumnNameSchema,
  r2Base: external_exports.string().optional(),
  idInR2: external_exports.coerce.boolean().optional(),
  autoDeleteR2Files: external_exports.coerce.boolean().optional(),
  allowMultipleFileRef: external_exports.coerce.boolean().optional(),
  allowWildcard: external_exports.coerce.boolean().optional(),
  fields: external_exports.array(tableFieldDataSchema),
  indexes: external_exports.array(zSQLIndex).optional(),
  triggers: external_exports.array(zSQLTrigger).optional(),
  autoSetUid: external_exports.coerce.boolean().optional(),
  extensions: external_exports.array(external_exports.record(external_exports.any()).and(external_exports.object({ name: external_exports.string() }))),
  lastName: tableColumnNameSchema.optional(),
  fullTextSearch: external_exports.object({
    enabled: external_exports.coerce.boolean().optional(),
    fields: external_exports.array(tableColumnNameSchema),
    tokenize: external_exports.string().optional(),
    prefix: external_exports.string().optional(),
    // content: z.string().optional(),
    migrateTableQuery: external_exports.coerce.boolean().default(true),
    content_rowid: external_exports.string().optional(),
    columnsize: external_exports.literal(0).or(external_exports.literal(1)).optional(),
    detail: external_exports.enum(["full", "column", "none"]).optional()
  }).optional()
});

// node_modules/teenybase/dist/types/zod/emailTemplatePropsSchema.js
var baseTemplatePropsSchema = external_exports.object({
  company_name: external_exports.string(),
  company_url: external_exports.string(),
  company_address: external_exports.string(),
  company_copyright: external_exports.string(),
  support_email: external_exports.string()
});

// node_modules/teenybase/dist/types/zod/mailgunBindingsSchema.js
var mailgunBindingsSchema = external_exports.object({
  MAILGUN_API_KEY: external_exports.string(),
  MAILGUN_API_SERVER: external_exports.string(),
  MAILGUN_API_URL: external_exports.string().optional(),
  MAILGUN_WEBHOOK_SIGNING_KEY: external_exports.string().optional(),
  DISCORD_MAILGUN_NOTIFY_WEBHOOK: external_exports.string().optional(),
  EMAIL_BLOCKLIST: external_exports.string().optional()
});

// node_modules/teenybase/dist/types/zod/resendBindingsSchema.js
var resendBindingsSchema = external_exports.object({
  RESEND_API_KEY: external_exports.string(),
  RESEND_API_URL: external_exports.string().optional(),
  RESEND_WEBHOOK_SECRET: external_exports.string().optional(),
  MAILGUN_WEBHOOK_ID: external_exports.string().optional(),
  DISCORD_RESEND_NOTIFY_WEBHOOK: external_exports.string().optional(),
  EMAIL_BLOCKLIST: external_exports.string().optional()
});

// node_modules/teenybase/dist/types/zod/databaseSettingsSchema.js
var databaseSettingsSchema = external_exports.object({
  tables: external_exports.array(tableDataSchema),
  jwtSecret: external_exports.string(),
  jwtIssuer: external_exports.string().optional(),
  jwtAlgorithm: external_exports.string().optional(),
  version: external_exports.number().optional(),
  appName: external_exports.string().optional(),
  appUrl: external_exports.string(),
  procedures: external_exports.array(zSQLProcedure).optional(),
  email: external_exports.object({
    from: external_exports.string(),
    variables: baseTemplatePropsSchema,
    tags: external_exports.array(external_exports.string()).optional(),
    mailgun: mailgunBindingsSchema.optional(),
    resend: resendBindingsSchema.optional()
  }).optional(),
  _kvTableName: external_exports.string().startsWith("_", { message: "Internal table name must start with _ (underscore)" }).optional(),
  disableTablesEdit: external_exports.coerce.boolean().optional()
});

// node_modules/teenybase/dist/worker/migrationHelper.js
var zDBMigration = external_exports.object({
  name: external_exports.string().max(255),
  sql: external_exports.string().max(65535),
  sql_revert: external_exports.string().max(65535).optional()
});
var MigrationHelper = class extends $DBExtension {
  tableName;
  kv;
  constructor(db, tableName = "_db_migrations", kv) {
    super(db);
    this.tableName = tableName;
    this.kv = kv;
  }
  async setup(version2) {
    if (!this.db.auth.superadmin)
      throw new HTTPException(403, { message: "Forbidden" });
    if (version2 >= 0) {
      const sql = `
            CREATE TABLE IF NOT EXISTS "${this.tableName}" (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE,
                sql TEXT NOT NULL,
                sql_revert TEXT DEFAULT NULL,
                applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
            )`.split("\n").map((l) => l.trim()).join(" ");
      await this.db.rawSQL({ q: sql, v: [] }).run();
    }
  }
  async list() {
    if (!this.db.auth.superadmin)
      throw new HTTPException(403, { message: "Forbidden" });
    const q = `SELECT id, name, sql, sql_revert FROM ${this.tableName}`;
    const migrations = await this.db.rawSQL({ q, v: [] }).run() || [];
    const settings = await this.kv.get("$settings");
    return { migrations, settings: settings ? JSON.parse(settings) : this.db.settings };
  }
  async apply(migrations, settings) {
    if (!this.db.auth.superadmin)
      throw new HTTPException(403, { message: "Forbidden" });
    const last = await this.list();
    const names = [];
    const prepared = external_exports.array(zDBMigration).parse(migrations).flatMap((m) => {
      let last1 = last.migrations.find((r) => r.name === m.name);
      if (last1) {
        if (last1.sql !== m.sql)
          throw new Error(`Migration ${m.name} already applied but sql mismatch`);
        if ((last1.sql_revert || null) !== (m.sql_revert || null))
          throw new Error(`Migration ${m.name} already applied but sql_revert mismatch`);
        return void 0;
      }
      if (names.includes(m.name))
        throw new Error(`Duplicate migration name ${m.name}`);
      names.push(m.name);
      const qs = splitSqlQuery(m.sql).map((sql) => sql ? { q: sql, v: [] } : void 0).filter((q) => !!q);
      if (!qs.length)
        throw new Error(`Empty migration ${m.name}`);
      return [
        ...qs,
        {
          q: `INSERT INTO ${this.tableName} (name, sql, sql_revert, applied_at) VALUES (?, ?, ?, CURRENT_TIMESTAMP)`,
          v: [m.name, m.sql, m.sql_revert ?? null]
        }
      ];
    }).filter((q) => !!q);
    const settings1 = JSON.stringify(settings);
    prepared.push(this.kv.setQuery("$settings", settings1));
    prepared.push(this.kv.setQuery("$settings_" + Date.now(), settings1));
    prepared.push(this.kv.setQuery("$settings_version", settings.version?.toString() ?? "0"));
    if (!prepared.length)
      return [];
    try {
      await this.db.rawSQLTransaction(prepared).run();
    } catch (e) {
      throw e ?? new Error("Failed to apply migrations");
    }
    return names;
  }
  routes = [{
    path: "/migrations",
    method: "get",
    handler: async () => {
      const res = await this.list();
      return res;
    },
    zod: () => ({
      description: "List all migrations",
      request: { headers: external_exports.object({ authorization: external_exports.string().min(1).max(255) }).describe("Admin Auth token with superadmin role") },
      responses: {
        "200": {
          description: "Success",
          content: {
            "application/json": {
              schema: external_exports.object({
                settings: databaseSettingsSchema,
                migrations: external_exports.array(zDBMigration)
              })
            }
          }
        }
      }
    })
  }, {
    path: "/migrations",
    method: "post",
    handler: async (data) => {
      const migrations = await this.apply(data.migrations, data.settings);
      if (!migrations)
        throw new HTTPException(500, { message: "Unable to apply migrations" });
      return { applied: migrations };
    },
    zod: () => ({
      description: "Apply migrations",
      request: {
        headers: external_exports.object({ authorization: external_exports.string().min(1).max(255) }).describe("Admin Auth token with superadmin role"),
        body: {
          description: "All migrations and new DB settings. New migrations will be applied and old migrations will be checked for db match",
          content: {
            "application/json": {
              schema: external_exports.object({
                settings: databaseSettingsSchema,
                migrations: external_exports.array(zDBMigration)
              })
            }
          },
          required: true
        }
      },
      responses: {
        "200": {
          description: "Success",
          content: {
            "application/json": {
              schema: external_exports.object({
                applied: external_exports.array(external_exports.string())
              })
            }
          }
        }
      }
    })
  }];
};
__name(MigrationHelper, "MigrationHelper");

// node_modules/teenybase/dist/worker/util/parseRequestBody.js
var MultipartJsonKey = "@jsonPayload";
var MultipartFilesKey = "@filePayload";
async function parseRequestBody(req) {
  return (req.bodyCache.parsedBody ??= await _parseRequestBody(req)) ?? null;
}
__name(parseRequestBody, "parseRequestBody");
async function _parseRequestBody(req) {
  if (req.method === "GET")
    return req.query();
  const cType = req.header("Content-Type")?.split(";")[0];
  if (cType === void 0) {
    throw new HTTPException(400, { message: "Content-Type header required" });
    return void 0;
  }
  if (cType === "application/json") {
    const body = await req.text();
    if (!body)
      return void 0;
    return parseJson(body);
  }
  if (cType === "multipart/form-data" || cType === "application/x-www-form-urlencoded") {
    const body = await parseFormData2(req, { all: true, dot: true });
    if (body[MultipartJsonKey]) {
      let json = body[MultipartJsonKey];
      delete body[MultipartJsonKey];
      let files = body[MultipartFilesKey];
      delete body[MultipartFilesKey];
      if (!Array.isArray(json))
        json = [json];
      if (files && (typeof files === "string" || files.size !== void 0) && !Array.isArray(files))
        files = [files];
      for (const str of json) {
        deepMergeFormData(body, parseJson(str));
      }
      if (files) {
        replaceFileReferences(body, files);
      }
    }
    return body;
  }
  return void 0;
}
__name(_parseRequestBody, "_parseRequestBody");
function parseJson(body) {
  try {
    return JSON.parse(body);
  } catch (e) {
    throw new HTTPException(400, { message: "Invalid JSON body" });
  }
}
__name(parseJson, "parseJson");
function deepMergeFormData(formData, json) {
  for (const key in json) {
    const val = json[key];
    const isObject = typeof val === "object" && val !== null;
    const isArray = Array.isArray(val);
    if (isObject || isArray) {
      if (formData[key] === void 0) {
        formData[key] = val;
      } else if (isArray) {
        if (!Array.isArray(formData[key])) {
          formData[key] = [formData[key]];
        }
        formData[key].push(...val);
      } else {
        deepMergeFormData(formData[key], val);
      }
    } else {
      formData[key] = val;
    }
  }
}
__name(deepMergeFormData, "deepMergeFormData");
function replaceFileReferences(data, files) {
  for (const key1 in data) {
    const val = data[key1];
    if (typeof val === "object") {
      replaceFileReferences(val, files);
      continue;
    }
    if (files && typeof val === "string" && val.startsWith(MultipartFilesKey)) {
      let key = val.slice(MultipartFilesKey.length);
      if (!key.length)
        key = ".0";
      if (key[0] === ".") {
        key = key.slice(1);
        const file = files[key];
        if (file) {
          data[key1] = file;
          continue;
        }
      }
    }
  }
}
__name(replaceFileReferences, "replaceFileReferences");
async function parseFormData2(request, options) {
  const formData = await request.formData();
  if (formData) {
    return convertFormDataToBodyData2(formData, options);
  }
  return {};
}
__name(parseFormData2, "parseFormData");
function convertFormDataToBodyData2(formData, options) {
  const form = /* @__PURE__ */ Object.create(null);
  formData.forEach((value, key) => {
    const shouldParseAllValues = options.all || key.endsWith("[]");
    if (!shouldParseAllValues) {
      form[key] = value;
    } else {
      handleParsingAllValues2(form, key, value);
    }
  });
  if (options.dot) {
    Object.entries(form).forEach(([key, value]) => {
      const shouldParseDotValues = key.includes(".");
      if (shouldParseDotValues) {
        handleParsingNestedValues2(form, key, value);
        delete form[key];
      }
    });
  }
  return form;
}
__name(convertFormDataToBodyData2, "convertFormDataToBodyData");
var handleParsingAllValues2 = /* @__PURE__ */ __name((form, key, value) => {
  if (form[key] !== void 0) {
    if (Array.isArray(form[key])) {
      ;
      form[key].push(value);
    } else {
      form[key] = [form[key], value];
    }
  } else {
    if (!key.endsWith("[]")) {
      form[key] = value;
    } else {
      form[key] = [value];
    }
  }
}, "handleParsingAllValues");
var handleParsingNestedValues2 = /* @__PURE__ */ __name((form, key, value) => {
  let nestedForm = form;
  const keys = key.split(".");
  keys.forEach((key2, index) => {
    if (index === keys.length - 1) {
      nestedForm[key2] = value;
    } else {
      if (!nestedForm[key2] || typeof nestedForm[key2] !== "object" || Array.isArray(nestedForm[key2]) || nestedForm[key2] instanceof File) {
        nestedForm[key2] = /* @__PURE__ */ Object.create(null);
      }
      nestedForm = nestedForm[key2];
    }
  });
}, "handleParsingNestedValues");

// node_modules/teenybase/dist/sql/build/delete.js
function buildDeleteQuery(query, simplify = true, allowAllWhere = true) {
  const p = { ...query.params };
  let q = `DELETE FROM ${query.table} `;
  if (query.where) {
    const where = buildSelectWhere(query.where, simplify);
    if (where === null || !where.q && !allowAllWhere)
      return { q: "" };
    q += " WHERE " + where.q;
    Object.assign(p, where.p);
  } else if (!allowAllWhere) {
    return { q: "" };
  } else {
    q += " WHERE 1";
  }
  if (query.returning?.length) {
    q += " RETURNING " + joinReturning(query.returning, p);
  }
  q += ";\n";
  return { q, p };
}
__name(buildDeleteQuery, "buildDeleteQuery");

// node_modules/teenybase/dist/sql/build/insert.js
function buildInsertQuery(query, simplify = true, allowAllWhere = true) {
  const p = { ...query.params };
  let q = "INSERT";
  if (query.or)
    q += ` OR ${query.or}`;
  q += ` INTO ${query.table}`;
  const values = Array.isArray(query.values) ? query.values : [query.values];
  if (!values.length)
    throw new Error("No values provided");
  const keys = Object.keys(values[0]);
  const valueSql = [];
  for (let j = 0; j < values.length; j++) {
    const value = values[j];
    const vals = [];
    const setKeys = Object.keys(value);
    if (setKeys.length !== keys.length)
      throw new Error("All values must have the same keys");
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      if (setKeys[i] !== key)
        throw new Error("All values must have the same keys");
      const set = literalToQuery(value[key]);
      vals.push(set.q);
      Object.assign(p, set.p);
    }
    valueSql.push(`${vals.join(", ")}`);
  }
  const keysSql = keys.map((k) => columnify(k)).join(", ");
  const where = query.where ? buildSelectWhere(query.where, simplify) : void 0;
  if (where === null)
    return { q: "" };
  if (!where || !where.q && !allowAllWhere) {
    q += ` (${keysSql}) VALUES (${valueSql.join("), (")})`;
  } else {
    const selectVals = valueSql.map((v) => `SELECT ${v}`).join(" UNION ALL ");
    const cteName = UPDATE_NEW_COL_ID;
    q = `WITH ${cteName} (${keysSql}) AS (${selectVals}) ${q} (${keysSql}) `;
    q += `SELECT ${keysSql} FROM ${cteName} WHERE ${where.q || "1"}`;
    Object.assign(p, where.p);
  }
  if (query.returning?.length) {
    q += " RETURNING " + joinReturning(query.returning, p);
  }
  q += ";\n";
  return { q, p };
}
__name(buildInsertQuery, "buildInsertQuery");

// node_modules/teenybase/dist/types/config/sqlUtils.js
function sqlRaw(q, p) {
  return { q, p };
}
__name(sqlRaw, "sqlRaw");

// node_modules/teenybase/dist/sql/schema/tableInfo.js
function tableInfoStmt(name) {
  return `SELECT
    pti.*,
    fkl.id AS fk_id,
    fkl."table" AS fk_table,
    fkl."to" AS fk_column,
    fkl."on_update" AS fk_on_update,
    fkl."on_delete" AS fk_on_delete,
    fkl."match" AS fk_match
FROM
    pragma_table_info('${name}') pti
LEFT JOIN
    pragma_foreign_key_list('${name}') fkl ON pti.name = fkl."from"
`;
}
__name(tableInfoStmt, "tableInfoStmt");
async function getTableInfo(db, collections) {
  const res = await db.rawSQLTransaction(collections.map((col) => ({ q: tableInfoStmt(col.name), v: [] }))).run();
  if (!res)
    throw new HTTPException(500, { message: "Error - Unable to get table info" });
  return res.map((r1, i) => {
    const results = r1;
    let logs = [];
    return {
      name: collections[i].name,
      system: collections[i].name.startsWith("_") || collections[i].name.startsWith("sqlite_"),
      // ...collections[i],
      logs,
      fields: results.map((field) => {
        if (!field.name) {
          logs.push(`Unknown field with no name`);
          return null;
        }
        const oldField = collections[i].fields?.find((f) => f.name === field.name);
        const type = field.type.toLowerCase();
        let defType = oldField?.type && supportedTypesForSql[sqlDataTypeAliases[type]].includes(TableFieldDataType[oldField.type]) ? oldField.type : sqlDataTypeToDataTypeDefaults[type];
        if (!defType) {
          logs.push(`Unknown type ${type} for field ${field.name}`);
          return null;
        }
        const relation = field.fk_column && field.fk_table ? {
          table: field.fk_table,
          column: field.fk_column,
          onUpdate: field.fk_on_update?.toUpperCase() || void 0,
          onDelete: field.fk_on_delete?.toUpperCase() || void 0
          // match: field.fk_match?.toUpperCase() || undefined, // todo
        } : void 0;
        if (relation) {
          defType = "relation";
        }
        if (oldField?.foreignKey) {
        }
        return {
          ...oldField,
          id: field.name,
          sqlType: type,
          type: defType,
          primary: !!field.pk,
          default: field.dflt_value ? sqlRaw(field.dflt_value) : void 0,
          notNull: !!field.notnull,
          name: field.name,
          foreignKey: relation
        };
      }).filter((v) => v)
    };
  });
}
__name(getTableInfo, "getTableInfo");
async function getSQLiteSchema(db) {
  if (!db.auth.admin)
    throw new HTTPException(db.auth.uid ? 403 : 401, { message: "Unauthorized" });
  const schema = await db.rawSQL({ q: `SELECT * from sqlite_schema`, v: [] }).run() ?? [];
  const tableCheck = /* @__PURE__ */ __name((r) => {
    return r.type === "table" && !r.name.startsWith("_cf") && !r.name.startsWith("sqlite_");
  }, "tableCheck");
  const tables = await getTableInfo(db, schema.filter(tableCheck).map((r) => ({
    name: r.tbl_name,
    sql: r.sql
    // fields: todo existing fields
  })));
  return tables.map((t) => ({
    name: t.name,
    fields: t.fields,
    extensions: [{
      name: "rules",
      listRule: null,
      viewRule: null,
      createRule: null,
      deleteRule: null,
      updateRule: null
    }],
    // r2Base: t.name,
    autoSetUid: false
    // todo if pk is text and not autoincrement etc
  }));
}
__name(getSQLiteSchema, "getSQLiteSchema");

// node_modules/teenybase/dist/worker/util/sql.js
var D1RunEvent = class extends Event {
  input;
  result;
  constructor(init) {
    super("run_sql", init);
    this.input = init.input;
    this.result = init.result;
  }
};
__name(D1RunEvent, "D1RunEvent");
var D1RunFailEvent = class extends Event {
  input;
  error;
  constructor(init) {
    super("run_sql_fail", init);
    this.input = init.input;
    this.error = init.error;
  }
};
__name(D1RunFailEvent, "D1RunFailEvent");

// node_modules/teenybase/dist/security/encryption.js
async function aesGcmDecrypt(ciphertext, password, ivLen = 5) {
  const pwUtf8 = typeof password === "string" ? new TextEncoder().encode(password) : password;
  const pwHash = await crypto.subtle.digest("SHA-256", pwUtf8);
  const ivStr = ciphertext.slice(0, ivLen);
  const iv = typeof ivStr === "string" ? new Uint8Array(Array.from(ivStr).map((ch) => ch.charCodeAt(0))) : ivStr;
  const alg = { name: "AES-GCM", iv };
  const key = await crypto.subtle.importKey("raw", pwHash, alg, false, ["decrypt"]);
  const ctStr = ciphertext.slice(ivLen);
  const ctUint8 = typeof ctStr === "string" ? new Uint8Array(Array.from(ctStr).map((ch) => ch.charCodeAt(0))) : ctStr;
  try {
    const plainBuffer = await crypto.subtle.decrypt(alg, key, ctUint8);
    return typeof ciphertext === "string" ? new TextDecoder().decode(plainBuffer) : new Uint8Array(plainBuffer);
  } catch (e) {
    throw new Error("Decrypt failed");
  }
}
__name(aesGcmDecrypt, "aesGcmDecrypt");

// node_modules/teenybase/dist/worker/secretResolver.js
var SecretResolver = class {
  env;
  encKeyEnv;
  constructor(env2, encKeyEnv) {
    this.env = env2;
    this.encKeyEnv = encKeyEnv;
  }
  resolver(secret, required = false, message) {
    return async () => this.resolve(secret, required, message);
  }
  async resolve(secret, required = false, message) {
    const env2 = this.env();
    const encKey = this.encKeyEnv ? env2[this.encKeyEnv] : void 0;
    const name = secret && secret[0] === "$" ? secret.slice(1) : void 0;
    const res = name ? env2[name] || "" : secret;
    const result = typeof encKey === "string" && name && res ? await aesGcmDecrypt(atob(res), encKey + name, 5) : res || "";
    if (required && !result) {
      throw new HTTPException(500, { message: `Invalid configuration, missing secret, ${message}, ${secret}` });
    }
    return result;
  }
};
__name(SecretResolver, "SecretResolver");
__publicField(SecretResolver, "DEFAULT_KEY_ENV", "TEENY_SECRET_ENCRYPTION_KEY");

// node_modules/teenybase/dist/worker/$Database.js
var $Database = class extends EventTarget {
  tables = {};
  settings;
  auth = {
    jwt: {},
    verified: false,
    admin: false,
    uid: null,
    sid: null,
    role: null,
    email: null,
    meta: {},
    cid: null,
    superadmin: false
  };
  queryLog = [];
  email;
  // readonly notify: NotifyClient
  jwt;
  kv;
  extensions = [];
  c;
  secretResolver;
  dryRunMode = false;
  readOnlyMode = false;
  adminJwtSecret;
  constructor(c, settings, database, storage) {
    super();
    this.c = c;
    if (c.env.IS_VITEST) {
      const h = c.req.header("$DB_TEST_DATABASE_SETTINGS");
      if (h)
        settings = JSON.parse(h);
    }
    this.settings = databaseSettingsSchema.parse(settings ?? JSON.parse(c.env.DATABASE_SETTINGS || ""));
    if (!database)
      throw new HTTPException(500, { message: "Invalid configuration - database not set" });
    this.database = database;
    this.storage = storage;
    this.kv = new InternalKV(this, this.settings._kvTableName);
    this.extensions.push(new MigrationHelper(this, void 0, this.kv));
    this.secretResolver = new SecretResolver(() => c.env, SecretResolver.DEFAULT_KEY_ENV);
    const sv = c.req.header("DDB_SETTINGS_VERSION");
    if (sv && parseInt(sv) !== this.settings.version) {
      throw new HTTPException(500, { message: "DDB_SETTINGS_VERSION_MISMATCH" });
    }
    c.set("settings", this.settings);
    if (this.c.get("auth"))
      this.auth = this.c.get("auth");
    else
      c.set("auth", this.auth);
    this.email = this.settings.email ? new EmailSendClient(this, {
      from: this.settings.email.from || void 0,
      variables: this.settings.email.variables,
      tags: this.settings.email.tags || []
    }, this.settings.email.mailgun ? {
      ...this.settings.email.mailgun,
      MAILGUN_API_KEY: this.secretResolver.resolver(this.settings.email?.mailgun?.MAILGUN_API_KEY, false),
      MAILGUN_WEBHOOK_SIGNING_KEY: this.secretResolver.resolver(this.settings.email?.mailgun?.MAILGUN_WEBHOOK_SIGNING_KEY, false)
    } : void 0, this.settings.email.resend ? {
      ...this.settings.email.resend,
      RESEND_API_KEY: this.secretResolver.resolver(this.settings.email?.resend?.RESEND_API_KEY, false),
      RESEND_WEBHOOK_SECRET: this.secretResolver.resolver(this.settings.email?.resend?.RESEND_WEBHOOK_SECRET, false)
    } : void 0) : null;
    if (this.email)
      this.extensions.push(this.email);
    const jwtSecret = this.secretResolver.resolver(this.settings.jwtSecret, true, "JWT_SECRET for the database");
    this.adminJwtSecret = this.c.env.ADMIN_JWT_SECRET ? this.secretResolver.resolver("$ADMIN_JWT_SECRET", false) : async () => "";
    this.jwt = new JWTTokenHelper(jwtSecret, this.settings.jwtIssuer, this.settings.jwtAlgorithm, [
      // todo
      "https://accounts.google.com"
    ]);
  }
  // setup db etc
  async setup() {
    if (!this.auth.superadmin)
      throw new HTTPException(this.auth.uid ? 403 : 401, { message: "Unauthorized, only superadmin can setup database" });
    const version2 = 0;
    if (version2 >= 0) {
    }
    await Promise.all([
      this.kv.setup(version2),
      ...this.extensions.map((e) => e.setup && e.setup(version2)),
      ...this.settings.tables.map((t) => this.table(t.name).setup(version2))
    ]);
    const settings = await this.kv.get("$settings");
    let message = "Success";
    if (!settings) {
      message = "Migrations not run yet - $settings not found - Run migrations to update $settings in the db";
    } else {
      const settings2 = JSON.parse(settings);
      if (settings2.version !== this.settings.version)
        message = `Settings version mismatch - ${settings2.version} !== ${this.settings.version} - deploy the worker again with the latest settings`;
    }
    return message;
  }
  // region auth
  async initAuth(tok) {
    if (this.c.get("auth")?.uid) {
      return;
    }
    if (!tok) {
      if (!tok) {
        const auth = this.c.req.header("Authorization") ?? this.c.req.header("X-Authorization");
        const isBearer = auth && auth.startsWith("Bearer ");
        tok = auth ? isBearer ? auth.slice(7) : auth : "";
      }
      if (!tok) {
        for (const extension of this.extensions) {
          if (extension.getAuthToken)
            tok = await extension.getAuthToken();
          if (tok)
            break;
        }
      }
      if (!tok)
        return;
    }
    let jwtSecret = this.adminJwtSecret;
    const adminToken = await this.secretResolver.resolve("$ADMIN_SERVICE_TOKEN");
    if (adminToken && tok === adminToken) {
      tok = await this.generateAdminToken("superadmin", tok);
    }
    let payload = null;
    try {
      payload = typeof tok === "string" ? decode(tok).payload : null;
    } catch (e) {
    }
    if (!payload)
      return;
    if (payload.cid) {
      const table3 = this.settings.tables.find((t) => t.name === payload.cid);
      if (!table3)
        throw new HTTPException(400, { message: "Invalid auth table" });
      const auth = table3.extensions.find((e) => e.name === "auth");
      jwtSecret = this.secretResolver.resolver(auth.jwtSecret, true, `JWT_SECRET for ${table3.name}`);
    }
    const secret = await jwtSecret();
    if (!secret?.length)
      throw new HTTPException(401, { message: "Invalid jwt" });
    payload = await this.jwt.decodeAuth(tok, secret, false, void 0, payload).catch((e) => {
      console.error(e);
      return null;
    });
    if (!payload)
      return;
    const aud = Array.isArray(payload.aud) ? payload.aud.length === 1 ? payload.aud[0] : payload.aud : payload.aud;
    this.auth = {
      uid: payload.id ?? null,
      cid: payload.cid,
      // table id
      sid: payload.sid ?? null,
      // session id
      email: payload.verified ? payload.sub : "",
      jwt: payload,
      role: aud ?? null,
      verified: Boolean(payload.verified ?? false),
      meta: payload.meta ?? {},
      admin: Boolean(payload.admin ?? false),
      superadmin: false
    };
    if (this.auth.cid && this.auth.admin) {
      throw new HTTPException(401, { message: "Unauthorized" });
    }
    if (this.auth.admin) {
      const role = Array.isArray(this.auth.role) ? this.auth.role : [this.auth.role];
      const viewer = role.includes("viewer");
      const editor = role.includes("editor") || role.includes("admin");
      const superadmin = role.includes("superadmin");
      if (!editor && !superadmin)
        this.readOnlyMode = true;
      if (!viewer && !editor && !superadmin)
        this.dryRunMode = true;
      if (superadmin)
        this.auth.superadmin = true;
    }
    this.c.set("auth", this.auth);
  }
  async generateAdminToken(role, tok) {
    if (tok !== await this.secretResolver.resolve("$ADMIN_SERVICE_TOKEN") && !this.auth.superadmin)
      throw new HTTPException(401, { message: "Unauthorized" });
    const adminJwtSecret = await this.adminJwtSecret();
    if (!adminJwtSecret)
      throw new HTTPException(500, { message: "Invalid configuration - ADMIN_JWT_SECRET not set" });
    const tokenDuration = 3 * 60 * 60;
    const data = {
      sub: role + "@" + this.settings.appUrl.trim().replace(/^https?:\/\//, ""),
      id: generateUid(),
      meta: {},
      aud: role,
      verified: true,
      admin: true
    };
    return await this.jwt.createJwtToken(data, adminJwtSecret, tokenDuration);
  }
  // endregion auth
  // region table
  table(name) {
    if (this.tables[name])
      return this.tables[name];
    const tableData = this.settings.tables.find((t) => t.name === name);
    if (!tableData)
      throw new HTTPException(404, { message: `Table not found - ${name}` });
    const globals = honoToJsep(this.c.req, this.auth);
    const jc = createJsepContext(tableData.name, this.settings.tables, globals, [tableData.name]);
    const table3 = new $Table(tableData, jc, this).initialize();
    this.tables[name] = table3;
    return table3;
  }
  allTables() {
    const keys = this.settings.tables.map((t) => t.name);
    return keys.map((k) => this.table(k));
  }
  // endregion table
  // region route
  _apiBase = "/api";
  apiBase = this._apiBase + "/v1";
  apiTableSuffix = "/table";
  apiTableBase = this.apiBase + this.apiTableSuffix;
  // routePath: string | null = null
  async route(path) {
    if (!path.startsWith(this._apiBase + "/"))
      return void 0;
    await this.initAuth();
    let res;
    if (path.startsWith(this.apiTableBase + "/")) {
      const p = path.replace(this.apiTableBase, "").split("/");
      const table3 = this.table(p[1]);
      res = await table3.route("/" + p.slice(2).join("/"));
    } else if (path.startsWith(this.apiBase))
      res = await this._route(path.replace(this.apiBase, ""));
    else
      res = void 0;
    if (res && res.headers) {
      const fsStats = Object.entries(this._fsStats);
      const uploaded = fsStats.filter((f) => f[1] !== null).map((f) => [f[0], f[1]]);
      const deleted = fsStats.filter((f) => f[1] === null).map((f) => f[0]);
      if (uploaded.length)
        res.headers.set("x-uploaded-files", JSON.stringify(Object.fromEntries(uploaded)));
      if (deleted.length)
        res.headers.set("x-deleted-files", JSON.stringify(deleted));
    }
    return res;
  }
  get requestMethod() {
    return this.c.req.method;
  }
  requestBody;
  async getRequestBody() {
    if (this.requestBody === void 0)
      this.requestBody = await parseRequestBody(this.c.req);
    return this.requestBody;
  }
  rawRouteHandler(route) {
    return async (params, path) => {
      if (typeof route.handler === "function") {
        const data = await this.getRequestBody();
        const res = await route.handler(data ?? {}, params, path);
        if (!res)
          throw new ProcessError("Not found", 404);
        if (typeof res === "string")
          return this.c.render(res);
        return this.c.json(res);
      } else {
        return route.handler.raw(params, path);
      }
    };
  }
  getRoutes() {
    this._initRoutes();
    return this.routes;
  }
  // endregion route
  // region crud
  rawDelete(table3, query, fileFields, then) {
    if (this.readOnlyMode)
      throw new ProcessError("DELETE not allowed in read only mode");
    if (query.table && query.table !== table3.jc.tableName && columnify(query.table) !== table3.jc.tableName)
      throw new ProcessError("Invalid table");
    const ret = this._fileFieldsToReturning(table3, fileFields, true);
    if (ret.length) {
      if (!query.returning)
        query.returning = [];
      query.returning.push(...ret);
    }
    const deleteQuery = { ...query, table: table3.jc.tableName };
    const sql = buildDeleteQuery(deleteQuery, table3.jc.autoSimplifyExpr);
    return this.prepare({
      table: table3,
      type: "delete",
      crudQuery: deleteQuery,
      query: sql,
      errorMessage: "Failed to run delete query",
      onRun: async () => {
      },
      onError: async (e) => {
        return e;
      },
      onSuccess: async (r) => {
        await this._cleanupFilesToUpload(r.results, void 0, table3);
      },
      then
    });
  }
  rawInsert(table3, query, filesToUpload, filesToRef, fileFields, then) {
    if (this.readOnlyMode)
      throw new ProcessError("INSERT not allowed in read only mode");
    if (query.table && query.table !== table3.jc.tableName && columnify(query.table) !== table3.jc.tableName)
      throw new ProcessError("Invalid table");
    const ret = this._fileFieldsToReturning(table3, fileFields, false);
    if (ret.length) {
      if (!query.returning)
        query.returning = [];
      query.returning.push(...ret);
    }
    if (fileFields?.length && query.or?.trim().toUpperCase().includes("REPLACE")) {
      throw new ProcessError("Cannot use file fields with INSERT OR REPLACE at the moment", 400);
    }
    const sqlQs = [];
    if (Array.isArray(query.values)) {
      const batchSize = 5;
      for (let i = 0; i < query.values.length; i += batchSize) {
        const batch = query.values.slice(i, i + batchSize);
        const insertQuery = { ...query, values: batch, table: table3.jc.tableName };
        const sql = buildInsertQuery(insertQuery, table3.jc.autoSimplifyExpr);
        sqlQs.push([insertQuery, sql]);
      }
    } else {
      const insertQuery = { ...query, table: table3.jc.tableName };
      const sql = buildInsertQuery(insertQuery, table3.jc.autoSimplifyExpr);
      sqlQs.push([insertQuery, sql]);
    }
    const onRun = /* @__PURE__ */ __name(async () => {
      filesToRef && await this._refCheckFiles(filesToRef, table3);
      filesToUpload && await this._uploadFiles(filesToUpload, table3);
    }, "onRun");
    const onError = /* @__PURE__ */ __name(async (e) => {
      if (filesToUpload)
        await this._deleteFiles(Object.keys(filesToUpload), table3);
      return e;
    }, "onError");
    const onSuccess = /* @__PURE__ */ __name(async (r) => {
      if (filesToUpload)
        await this._cleanupFilesToUpload(r, filesToUpload, table3);
    }, "onSuccess");
    if (sqlQs.length === 1) {
      return this.prepare({
        table: table3,
        type: "insert",
        crudQuery: sqlQs[0][0],
        query: sqlQs[0][1],
        errorMessage: "Failed to run insert query",
        onRun,
        onError,
        onSuccess: async (r) => onSuccess(r.results),
        then
      });
    } else {
      return this.transaction({
        table: table3,
        type: sqlQs.map((_) => "insert"),
        crudQuery: sqlQs.map((q) => q[0]),
        query: sqlQs.map((q) => q[1]),
        errorMessage: "Failed to run insert query",
        onRun,
        onError,
        onSuccess: async (r) => onSuccess(r.flat()),
        // @ts-ignore
        then: async (r) => then ? then(r.flat()) : r.flat()
      });
    }
  }
  rawUpdate(table3, query, filesToUpload, filesToRef, filesToDelete, fileFields, then) {
    if (this.readOnlyMode)
      throw new ProcessError("UPDATE not allowed in read only mode");
    if (query.table && query.table !== table3.jc.tableName && columnify(query.table) !== table3.jc.tableName)
      throw new ProcessError("Invalid table");
    const ret = this._fileFieldsToReturning(table3, fileFields, false);
    if (ret.length) {
      if (!query.returning)
        query.returning = [];
      query.returning.push(...ret);
    }
    const oldReturning = this._fileFieldsToReturning(table3, fileFields, true);
    const selectQuery = {
      where: query.where,
      from: table3.jc.tableName,
      selects: oldReturning,
      params: query.params
    };
    const sqlSelect = oldReturning.length ? buildSelectQuery(selectQuery, table3.jc.autoSimplifyExpr) : null;
    const updateQuery = { ...query, table: table3.jc.tableName };
    const sql = buildUpdateQuery(
      updateQuery,
      table3.jc.autoSimplifyExpr,
      true
      /*, oldReturning*/
    );
    const onRun = /* @__PURE__ */ __name(async () => {
      filesToRef && await this._refCheckFiles(filesToRef, table3);
      filesToUpload && await this._uploadFiles(filesToUpload, table3);
    }, "onRun");
    const onError = /* @__PURE__ */ __name(async (e) => {
      if (filesToUpload)
        await this._deleteFiles(Object.keys(filesToUpload), table3);
      return e;
    }, "onError");
    const onSuccess = /* @__PURE__ */ __name(async (r, old) => {
      await this._cleanupFilesToUpload(r, filesToUpload, table3, old);
    }, "onSuccess");
    return !sqlSelect ? this.prepare({
      table: table3,
      type: "update",
      crudQuery: updateQuery,
      query: sql,
      errorMessage: "Failed to run update query",
      onRun,
      onError,
      onSuccess: (r) => onSuccess(r.results),
      then
    }) : this.transaction({
      table: table3,
      type: ["update", "select"],
      crudQuery: [selectQuery, updateQuery],
      query: [sqlSelect, sql],
      errorMessage: "Failed to run update query",
      onRun,
      onError,
      onSuccess: async (r) => {
        return onSuccess(r[1], r[0]);
      },
      then: async (r) => {
        const res = r[1];
        return then ? then(res) : res;
      }
    });
  }
  rawSelect(table3, query, countTotal) {
    let qFrom = query.from;
    if (qFrom && (typeof qFrom !== "string" || qFrom !== table3.jc.tableName && columnify(qFrom) !== table3.jc.tableName))
      throw new ProcessError("Invalid from table");
    const selectQuery = { ...query, from: table3.jc.tableName };
    const sql = buildSelectQuery(selectQuery, table3.jc.autoSimplifyExpr);
    if (!countTotal || typeof countTotal === "function") {
      return countTotal === void 0 || typeof countTotal === "function" ? this.prepare({
        table: table3,
        type: "select",
        crudQuery: selectQuery,
        query: sql,
        errorMessage: "Failed to run select query",
        then: countTotal
      }) : this.prepare({
        table: table3,
        type: "select",
        crudQuery: selectQuery,
        query: sql,
        errorMessage: "Failed to run select query",
        then: async (res) => ({ items: res, total: -1 })
      });
    }
    const countField = table3.mapping.uid ? ident(table3.mapping.uid, table3.jc) : "*";
    const countSelectQuery = {
      ...query,
      from: table3.jc.tableName,
      selects: [`count(${countField}) as total`],
      limit: void 0,
      offset: void 0,
      orderBy: void 0,
      groupBy: void 0,
      distinct: false
    };
    const countQuery = buildSelectQuery(countSelectQuery, table3.jc.autoSimplifyExpr);
    return this.transaction({
      table: table3,
      type: ["select", "select"],
      crudQuery: [selectQuery, countSelectQuery],
      query: [sql, countQuery],
      errorMessage: "Failed to run select query",
      then: async (r) => ({ items: r[0], total: r[1][0]?.total ?? -1 })
    });
  }
  // endregion crud
  // region sql
  rawSQL(d1Expr, c) {
    return this._prepareD1Query(d1Expr, false, c);
  }
  rawSQLTransaction(d1Expr, c) {
    return this._prepareD1Transaction(d1Expr, false, c);
  }
  // async sql<T>(d1Expr: D1Query, c?: SQLRunContext) {
  //     return await this.rawSQL<T>(d1Expr, c).run()
  // }
  // async sqlTransaction<T>(d1Expr: D1Query[], c?: SQLRunTransactionContext) {
  //     return await this.rawSQLTransaction<T>(d1Expr, c).run()
  // }
  // todo
  async _rawProcedure(name, body) {
    const procedure = this.settings.procedures?.find((p) => p.name === name);
    if (!procedure)
      throw new ProcessError(`Procedure not found - ${name}`, 404);
    if (this.dryRunMode || this.c.env.RESPOND_WITH_QUERY_LOG)
      this.queryLog.push("PROCEDURE: " + procedure.name);
    if (this.dryRunMode)
      return;
    const statements = Array.isArray(procedure.statement) ? procedure.statement : procedure.statement ? [procedure.statement] : [];
    const queries = Array.isArray(procedure.query) ? procedure.query : procedure.query ? [procedure.query] : [];
    if (!statements.length && !queries.length)
      throw new ProcessError(`Invalid procedure ${procedure.name}, missing statements or queries`, 500);
    if (statements.length && queries.length)
      throw new ProcessError(`Invalid procedure ${procedure.name}, cannot have both statements and queries`, 500);
    const paramsBody = {};
    const params = procedure.params ?? [];
    for (const param of params) {
      if (!param)
        throw new ProcessError(`Invalid procedure ${procedure.name}, missing parameter`, 500);
      const val = body[param];
      if (val === void 0)
        throw new ProcessError(`Procedure ${procedure.name}, missing required parameter ${param}`, 400);
      paramsBody[param] = val;
    }
    const rule = procedure.rule ?? true;
    const prepared = [];
    if (queries.length) {
      if (rule)
        throw new ProcessError(`Invalid procedure ${procedure.name}, cannot have raw queries with rule`);
      for (const query1 of queries) {
        if (!query1)
          continue;
        const query = structuredClone(query1);
        query.params = {
          ...query.params,
          ...paramsBody
        };
        let prep;
        if (query.type === "SELECT") {
          if (Array.isArray(query.from))
            throw new ProcessError(`Invalid procedure ${procedure.name}, cannot have multiple tables in select query`, 500);
          if (!query.from)
            throw new ProcessError(`Invalid procedure ${procedure.name}, missing from table in select query`, 500);
          prep = this.rawSelect(this.table(query.from), query);
        } else if (query.type === "UPDATE") {
          prep = this.rawUpdate(this.table(query.table), query);
        } else if (query.type === "INSERT") {
          prep = this.rawInsert(this.table(query.table), query);
        } else if (query.type === "DELETE") {
          prep = this.rawDelete(this.table(query.table), query);
        }
        if (!prep)
          continue;
        prepared.push(prep);
      }
    }
    if (statements.length) {
      if (!rule)
        throw new ProcessError(`Invalid procedure ${procedure.name}, cannot have statements without rule, not supported yet`, 500);
      for (const statement of statements) {
        if (!statement)
          continue;
        const table3 = this.table(statement.table);
        const globals = table3.jc.globals.params;
        table3.jc.globals.params = {
          ...table3.jc.globals.params,
          ...paramsBody
        };
        let prep;
        if (statement.type === "SELECT") {
          prep = await table3.rawSelect(statement);
        } else if (statement.type === "UPDATE") {
          prep = await table3.rawUpdate(statement);
        } else if (statement.type === "INSERT") {
          prep = await table3.rawInsert(statement);
        } else if (statement.type === "DELETE") {
          prep = await table3.rawDelete(statement);
        }
        table3.jc.globals.params = globals;
        if (!prep)
          continue;
        prepared.push(prep);
      }
    }
    if (!prepared.length)
      return;
    const res = {
      prepared,
      c: void 0,
      run: async () => this._execBatch(res)
    };
    return res;
  }
  // endregion sql
  // region r2/s3 helpers, todo make private?
  _fsStats = {};
  // key is the uploaded file name, value is the source file name if uploaded or null if deleted
  async headFileObject(key) {
    if (this.dryRunMode || this.c.env.RESPOND_WITH_QUERY_LOG)
      this.queryLog.push("STORAGE: headFileObject: " + key);
    if (this.dryRunMode)
      throw new Error("headFile not supported in dry run mode");
    return this.bucket.head(key);
  }
  async getFileObject(key, options) {
    if (this.dryRunMode || this.c.env.RESPOND_WITH_QUERY_LOG)
      this.queryLog.push("STORAGE: getFileObject: " + key);
    if (this.dryRunMode)
      throw new Error("getFile not supported in dry run mode");
    return this.bucket.get(key, options);
  }
  async putFileObject(key, value, options) {
    if (this.dryRunMode || this.c.env.RESPOND_WITH_QUERY_LOG)
      this.queryLog.push("STORAGE: putFileObject: " + key);
    if (this.dryRunMode)
      return { dummy: true };
    if (this.readOnlyMode)
      throw new Error("putFile not allowed in read only mode");
    return this.bucket.put(key, value, options).then((r) => {
      const id = !value ? "empty" : typeof value === "string" ? value.substring(0, 10) : value.name ? value.name : value instanceof ArrayBuffer ? "arraybuffer" : typeof value === "object" && "getReader" in value && "locked" in value ? "stream" : "data";
      this._fsStats[key] = id;
      return r;
    });
  }
  async deleteFileObject(keys) {
    if (this.dryRunMode || this.c.env.RESPOND_WITH_QUERY_LOG)
      this.queryLog.push("STORAGE: deleteFileObject: " + keys);
    if (this.dryRunMode)
      return;
    if (this.readOnlyMode)
      throw new Error("deleteFile not allowed in read only mode");
    return this.bucket.delete(keys).then((r) => {
      const keys1 = Array.isArray(keys) ? keys : [keys];
      for (const key of keys1) {
        if (typeof this._fsStats[key] === "string")
          delete this._fsStats[key];
        else
          this._fsStats[key] = null;
      }
      return r;
    });
  }
  // endregion r2/s3
  // region private sql
  database;
  prepare(c) {
    const q = c.query;
    if (this.dryRunMode || this.c.env.RESPOND_WITH_QUERY_LOG) {
      this.queryLog.push(logSQLQuery(q));
    }
    const d1Expr = sqlQueryToD1Query(q);
    if (this.dryRunMode)
      return null;
    return this._prepareD1Query(d1Expr, q._readOnly, c);
  }
  transaction(c) {
    const q = c.query;
    if (this.dryRunMode || this.c.env.RESPOND_WITH_QUERY_LOG) {
      this.queryLog.push(q.map((q1) => logSQLQuery(q1)).join(";\n"));
    }
    const d1Expr = q.map(sqlQueryToD1Query);
    if (this.dryRunMode)
      return null;
    return this._prepareD1Transaction(d1Expr, q.every((q1) => q1._readOnly), c);
  }
  // private async _rawSQL<T>(d1Expr: D1Query, onErr?: (er: any) => any, readOnly = false, c?: SQLRunContext) {
  //     return this._prepareD1Query(d1Expr, onErr, readOnly, c)
  // }
  onRunSQL = [];
  onRunFailSQL = [];
  _prepareD1Query(d1Expr, readOnly = true, c) {
    if (this.readOnlyMode && !readOnly)
      throw new ProcessError("Running raw SQL is not allowed in read only mode.");
    if (this.dryRunMode)
      throw new ProcessError("Running raw SQL is not allowed in dry run.");
    const prep = {
      prepared: d1Expr.q ? this.database.prepare(d1Expr.q).bind(...d1Expr.v) : null,
      c,
      onError: async (er) => {
        const msg = er.message ? er.message.replace(/D1_ERROR: /g, "") : "Unknown error";
        const e = new D1Error(prep.c?.errorMessage || "Unknown SQL Error", msg, er, prep.c?.query ? logSQLQuery(prep.c.query) : "");
        const error4 = prep.c?.table?.parseD1Error(e) ?? e;
        const event = new D1RunFailEvent({ input: { ...prep.c, d1Expr }, error: er });
        for (const listener of this.onRunFailSQL)
          await listener(event);
        return c?.onError ? c.onError(error4) : error4;
      },
      onSuccess: async (res) => {
        if (!res)
          throw new Error("Unknown error - No result");
        else if (!res.success)
          throw new Error(res.error);
        else {
          const event = new D1RunEvent({ input: { ...prep.c, d1Expr }, result: res });
          for (const listener of this.onRunSQL)
            await listener(event);
          c?.onSuccess && await c.onSuccess(res);
          return res.results;
        }
      },
      run: async () => {
        if (this.c.env.IS_VITEST) {
          console.log("Executing SQL:", d1Expr);
        }
        return this._exec(prep);
      }
    };
    return prep;
  }
  _prepareD1Transaction(d1Exprs, readOnly = false, c) {
    const prepared = d1Exprs.map((query, i) => {
      return this._prepareD1Query(query, readOnly, c ? {
        ...c,
        query: c.query[i],
        crudQuery: c.crudQuery[i],
        type: c.type[i],
        onError: void 0,
        onSuccess: void 0,
        onRun: void 0,
        then: void 0
      } : void 0);
    });
    const prep = {
      prepared,
      c,
      run: async () => {
        if (this.c.env.IS_VITEST) {
          console.log("Executing SQL Transaction:", d1Exprs);
        }
        return this._execBatch(prep);
      }
    };
    return prep;
  }
  async _exec(prep) {
    let res;
    try {
      prep.c?.onRun && await prep.c.onRun();
      res = await prep.prepared?.run();
    } catch (e) {
      throw await prep.onError(e);
    }
    let ret;
    try {
      ret = await prep.onSuccess(res ?? { success: true, results: [] });
    } catch (e) {
      console.error("Unknown error in onSuccess", res, e);
      ret = res?.results || [];
    }
    try {
      return prep.c?.then ? await prep.c.then(ret) : ret;
    } catch (e) {
      console.error("Unknown error in then, ignored", ret, e);
      return null;
    }
  }
  async _execBatch(transaction) {
    const statements = [];
    const onRuns = [];
    const onErrors = [];
    function collect(t) {
      t.c?.onRun && onRuns.push(t.c.onRun);
      t.c?.onError && onErrors.push(t.c.onError);
      for (const prep of t.prepared) {
        if (Array.isArray(prep.prepared)) {
          collect(prep);
        } else if (prep.prepared) {
          const prep1 = prep;
          prep.c?.onRun && onRuns.push(prep.c.onRun);
          prep1.onError && onErrors.push(prep1.onError);
          statements.push(prep.prepared);
        }
      }
    }
    __name(collect, "collect");
    collect(transaction);
    let res;
    try {
      for (const onRun of onRuns) {
        await onRun();
      }
      res = statements.length ? await this.database.batch(statements) : [];
    } catch (e) {
      for (const onError of onErrors) {
        try {
          e = await onError(e);
        } catch (e1) {
          console.error("Unknown error in onError", e1);
          e = e1;
        }
      }
      throw e;
    }
    let i = 0;
    async function collectResults(t) {
      let res2 = [];
      for (const prep1 of t.prepared) {
        if (Array.isArray(prep1.prepared)) {
          const prep = prep1;
          const res3 = await collectResults(prep);
          if (Array.isArray(res3)) {
            res2.push(...res3);
          } else {
            console.error("Invalid result in nested transaction, expected array, ignored", res3);
          }
        } else {
          const prep = prep1;
          const r = prep.prepared ? res[i++] : { success: true, results: [] };
          let ret;
          try {
            ret = await prep.onSuccess(r);
          } catch (e) {
            console.error("Unknown error in onSuccess, ignored", r, e);
            ret = r?.results || [];
          }
          try {
            res2.push(prep.c?.then ? await prep.c.then(ret) : ret);
          } catch (e) {
            console.error("Unknown error in then, ignored", ret, e);
          }
        }
      }
      try {
        t.c?.onSuccess && await t.c.onSuccess(res2);
      } catch (e) {
        console.error("Unknown error in onSuccess, ignored", res, e);
      }
      try {
        return t.c?.then ? await t.c.then(res2) : res2;
      } catch (e) {
        console.error("Unknown error in then, ignored", res2, e);
        return null;
      }
    }
    __name(collectResults, "collectResults");
    return await collectResults(transaction);
  }
  // endregion private sql
  // region private r2/s3
  storage;
  get bucket() {
    if (!this.storage)
      throw new HTTPException(500, { message: "No bucket provided" });
    return this.storage;
  }
  /**
   * Checks that all files referenced in a query exist
   * @param files
   * @param table
   * @protected
   */
  async _refCheckFiles(files, table3) {
    if (!files.length)
      return;
    if (!table3.allowMultipleFileRef)
      throw new ProcessError("Multiple file references shouldn't be allowed");
    if (this.c.req.header("x-check-file-references") === "false")
      return;
    if (files.length > 500)
      throw new ProcessError("Too many files to check, set x-check-file-references to false to disable.");
    const promises = files.map(async (key) => {
      const res2 = await this.headFileObject(table3.fileKey(key)).catch((e) => {
        console.error("Failed to check file", e);
        return void 0;
      });
      if (res2 === void 0)
        throw new ProcessError("Failed to check file " + key);
      return res2;
    });
    const res = await Promise.allSettled(promises);
    const hasError = res.some((r) => r.status === "rejected");
    const successful = res.filter((r) => r.status === "fulfilled").map((r) => r.value);
    if (!successful.length || hasError) {
      throw new ProcessError("Failed to check files");
    }
    if (successful.includes(null)) {
      throw new ProcessError("File not found " + files[successful.indexOf(null)]);
    }
  }
  async _uploadFiles(files, table3) {
    const keys = Object.keys(files);
    if (!keys.length)
      return;
    console.log("Uploading files", keys, files);
    const promises = keys.map(async (key) => {
      const file = files[key];
      const fileKey = table3.fileKey(key);
      const res2 = await this.putFileObject(fileKey, file, {
        httpMetadata: {
          contentType: file.type || "application/octet-stream",
          cacheControl: "public, max-age=31536000"
          // 1 year
        }
      }).catch((e) => {
        console.error("Failed to upload file", e);
        return null;
      });
      if (!res2)
        throw new ProcessError("Failed to upload file " + key + " " + file.name);
      return res2;
    });
    const res = await Promise.allSettled(promises);
    const hasError = res.some((r) => r.status === "rejected");
    const successful = res.filter((r) => r.status === "fulfilled").map((r) => r.value);
    if (hasError) {
      const errors2 = res.filter((r) => r.status === "rejected").map((r) => r.reason);
      console.error(errors2);
      console.log("Deleting uploaded files", successful);
      await this.deleteFileObject(successful.map((r) => r.key)).catch((e) => {
        console.error("Unable to delete some files after upload error", e);
      });
      throw new ProcessError("Failed to upload files");
    }
  }
  async _deleteFiles(files, table3) {
    const keys = files.map((f) => table3.fileKey(f));
    if (!keys.length)
      return;
    console.log("Deleting files", keys);
    return await this.deleteFileObject(keys).catch((e) => {
      console.error("Failed to delete files", keys, e);
      throw new Error("Failed to delete files");
    });
  }
  // todo remove old?
  _fileFieldsToReturning(table3, fileFields, old = false) {
    let r = [];
    if (fileFields)
      for (const key of fileFields) {
        const id = (old ? "_0f_" : "_1f_") + Math.random().toString(36).substring(2, 15);
        r.push({ q: ident(key, table3.jc), as: id });
      }
    return r;
  }
  async _cleanupFilesToUpload(r, filesToUpload, table3, oldSelect) {
    const filesSuccess = [];
    const filesOld = [];
    for (const row of r) {
      const keys = Object.keys(row);
      for (const key of keys) {
        if (key.startsWith("_1f_")) {
          const v = row[key];
          if (v)
            filesSuccess.push(v);
          delete row[key];
        }
      }
      for (const key of keys) {
        if (key.startsWith("_0f_")) {
          const v = row[key];
          if (v && !filesSuccess.includes(v))
            filesOld.push(v);
          delete row[key];
        }
      }
    }
    for (const row of oldSelect || []) {
      const keys = Object.keys(row);
      for (const key of keys) {
        if (key.startsWith("_0f_")) {
          const v = row[key];
          if (v && !filesSuccess.includes(v))
            filesOld.push(v);
          delete row[key];
        }
      }
    }
    const failedFiles = !filesToUpload ? [] : Object.keys(filesToUpload).filter((f) => !filesSuccess.includes(f));
    const filesToDelete = [...failedFiles];
    if (table3.autoDeleteR2Files)
      filesToDelete.push(...filesOld);
    if (failedFiles.length)
      console.error(`Failed to insert files: ${failedFiles.join(", ")}`);
    if (filesToDelete.length) {
      await this._deleteFiles(filesToDelete, table3).catch(() => {
        if (failedFiles.length)
          console.error(`Failed to delete files that were not inserted: ${failedFiles.join(", ")}`);
        if (filesOld.length)
          console.error(`Failed to delete files old files in db: ${filesOld.join(", ")}`);
      });
    }
  }
  // endregion private r2/s3
  // region routing
  // todo write tests for these routes
  routes = [{
    path: "/health",
    method: "get",
    handler: async () => {
      return {
        status: "ok",
        timestamp: Date.now(),
        version: this.settings.version
      };
    },
    zod: () => ({
      description: "Health check endpoint to verify the server is running",
      request: {},
      responses: {
        "200": {
          description: "Server is healthy",
          content: { "application/json": {
            schema: external_exports.object({
              status: external_exports.literal("ok"),
              timestamp: external_exports.number(),
              version: external_exports.number()
            })
          } }
        }
      }
    })
  }, {
    path: "/setup-db",
    method: "post",
    handler: async () => {
      const message = await this.setup();
      return {
        message,
        settings: this.settings
      };
    },
    zod: () => ({
      description: "Setup database and get settings (create metadata tables etc)",
      request: { headers: external_exports.object({ authorization: external_exports.string().min(1).max(255) }).describe("Admin Auth token with superadmin role") },
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": {
            schema: databaseSettingsSchema
          } }
        }
      }
    })
  }, {
    path: "/settings",
    method: "get",
    handler: async () => {
      if (!this.auth.admin)
        throw new HTTPException(this.auth.uid ? 403 : 401, { message: "Unauthorized" });
      const isRaw = this.c.req.query("raw");
      if (isRaw !== void 0 && (isRaw === "" || external_exports.coerce.boolean().parse(isRaw)))
        return { tables: await getSQLiteSchema(this), jwtSecret: this.settings.jwtSecret, appUrl: this.settings.appUrl, version: 1 };
      return this.settings;
    },
    zod: () => ({
      description: "Get database settings",
      request: {
        query: external_exports.object({ raw: external_exports.boolean().optional().describe("Get raw sqlite schema (tableInfo)") }),
        headers: external_exports.object({ authorization: external_exports.string().min(1).max(255) }).describe("Admin Auth token")
      },
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": {
            schema: databaseSettingsSchema
          } }
        }
      }
    })
  }, {
    path: "/files/:table/:rid/:path{.+}",
    method: "get",
    handler: { raw: async (params) => {
      const path = external_exports.string().min(1).max(255).regex(/^[a-zA-Z0-9_\-\/.*+=#]+$/).parse(params.path);
      const rid = external_exports.string().min(1).max(255).parse(params.rid);
      const table3 = this.table(params.table);
      const object = await table3.getFile(path, rid);
      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set("etag", object.httpEtag);
      object.customMetadata && Object.entries(object.customMetadata).map(([k, v]) => headers.set("DDB-" + k, v));
      return this.c.newResponse(object.body, { headers });
    } },
    zod: () => ({
      description: "Get file from bucket that is referenced inside a record in a table",
      request: {
        params: external_exports.object({ table: external_exports.string().min(1).max(255), rid: external_exports.string().min(1).max(255).describe("Record id"), path: external_exports.string().min(1).max(255).describe("File name/path") })
        // query: z.object({token: z.string().min(1).max(255).optional().describe('Auth token')}),
      },
      responses: {
        "200": { description: "Success" },
        "404": { description: "Not found" }
      }
    })
  }, {
    path: "/rpc/:fn_name",
    method: "post",
    handler: async (body, params) => {
      if (!body || typeof body !== "object" || Array.isArray(body))
        throw new HTTPException(400, { message: "Invalid request body" });
      const fn_name = external_exports.string().min(1).max(255).describe("Name of the stored procedure").parse(params.fn_name, { path: ["fn_name"] });
      const res = await (await this._rawProcedure(fn_name, body))?.run();
      return res ?? [];
    },
    zod: () => ({
      description: "Run a stored procedure",
      request: {
        params: external_exports.object({ fn_name: external_exports.string().min(1).max(255).describe("Function name") }),
        headers: external_exports.object({ authorization: external_exports.string().min(1).max(255).optional() }).describe("Auth token"),
        body: {
          description: "Function parameters",
          content: { "application/json": { schema: external_exports.record(external_exports.any()).describe("Function parameters") } },
          required: false
        }
      },
      responses: {
        "200": { description: "Success" },
        "404": { description: "Not found" },
        "400": { description: "Invalid Arguments/Bad request" }
      }
    })
  }, {
    method: "get",
    path: "/explain/*",
    handler: {
      raw: async (_params, path) => {
        if (!this.auth.admin || !this.c.env.RESPOND_WITH_QUERY_LOG)
          throw new HTTPException(this.auth.uid ? 403 : 401, { message: "Forbidden" });
        this.dryRunMode = true;
        path = path.replace("/explain", "");
        if (path.startsWith("/explain"))
          throw new Error("Cannot explain explain");
        if (!path.startsWith(this.apiTableSuffix))
          throw new Error("Not supported for this path");
        const res = await this.route(this.apiBase + path);
        const logs = this.queryLog;
        if (!res)
          return this.c.notFound();
        const resBody = await res.text().catch((e) => ({ error: e }));
        const resHeaders = {};
        res.headers.forEach((v, k) => resHeaders[k] = v);
        return this.c.json({ logs, result: res ? {
          status: res.status,
          body: resBody,
          headers: resHeaders
        } : null });
      }
    },
    zod: () => ({
      description: "Explain route. Returns the list of sql statements and storage actions that will be executed",
      request: {
        params: external_exports.object({ route: external_exports.string().min(1).max(255) }),
        headers: external_exports.object({ authorization: external_exports.string().min(1).max(255) }).describe("Admin Auth token")
      },
      responses: {
        "200": {
          description: "Success",
          content: { "application/json": { schema: external_exports.object({
            logs: external_exports.array(external_exports.string()),
            result: external_exports.object({ status: external_exports.number(), body: external_exports.string(), headers: external_exports.record(external_exports.string()) }).optional()
          }) } }
        }
      }
    })
  }];
  router;
  _routesInit = false;
  _initRoutes() {
    if (!this.router)
      this.router = new LinearRouter();
    if (this._routesInit)
      return this.router;
    this.routes.push(...this.extensions.flatMap((e) => e.routes));
    for (const route of this.routes) {
      this.router.add(route.method.toUpperCase(), route.path, this.rawRouteHandler(route));
    }
    this._routesInit = true;
    return this.router;
  }
  async _route(path) {
    const router = this._initRoutes();
    const match = router.match(this.requestMethod, path);
    const [handler, params] = match[0]?.[0] ?? [void 0];
    if (!handler)
      return void 0;
    return await handler(params, path);
  }
};
__name($Database, "$Database");

// node_modules/hono/dist/helper/html/index.js
var html = /* @__PURE__ */ __name((strings, ...values) => {
  const buffer = [""];
  for (let i = 0, len = strings.length - 1; i < len; i++) {
    buffer[0] += strings[i];
    const children = Array.isArray(values[i]) ? values[i].flat(Infinity) : [values[i]];
    for (let i2 = 0, len2 = children.length; i2 < len2; i2++) {
      const child = children[i2];
      if (typeof child === "string") {
        escapeToBuffer(child, buffer);
      } else if (typeof child === "number") {
        ;
        buffer[0] += child;
      } else if (typeof child === "boolean" || child === null || child === void 0) {
        continue;
      } else if (typeof child === "object" && child.isEscaped) {
        if (child.callbacks) {
          buffer.unshift("", child);
        } else {
          const tmp = child.toString();
          if (tmp instanceof Promise) {
            buffer.unshift("", tmp);
          } else {
            buffer[0] += tmp;
          }
        }
      } else if (child instanceof Promise) {
        buffer.unshift("", child);
      } else {
        escapeToBuffer(child.toString(), buffer);
      }
    }
  }
  buffer[0] += strings[strings.length - 1];
  return buffer.length === 1 ? "callbacks" in buffer ? raw(resolveCallbackSync(raw(buffer[0], buffer.callbacks))) : raw(buffer[0]) : stringBufferToString(buffer, buffer.callbacks);
}, "html");

// node_modules/@hono/swagger-ui/dist/index.js
var RENDER_TYPE = {
  STRING_ARRAY: "string_array",
  STRING: "string",
  JSON_STRING: "json_string",
  RAW: "raw"
};
var RENDER_TYPE_MAP = {
  configUrl: RENDER_TYPE.STRING,
  deepLinking: RENDER_TYPE.RAW,
  presets: RENDER_TYPE.STRING_ARRAY,
  plugins: RENDER_TYPE.STRING_ARRAY,
  spec: RENDER_TYPE.JSON_STRING,
  url: RENDER_TYPE.STRING,
  urls: RENDER_TYPE.JSON_STRING,
  layout: RENDER_TYPE.STRING,
  docExpansion: RENDER_TYPE.STRING,
  maxDisplayedTags: RENDER_TYPE.RAW,
  operationsSorter: RENDER_TYPE.RAW,
  requestInterceptor: RENDER_TYPE.RAW,
  responseInterceptor: RENDER_TYPE.RAW,
  persistAuthorization: RENDER_TYPE.RAW,
  defaultModelsExpandDepth: RENDER_TYPE.RAW,
  defaultModelExpandDepth: RENDER_TYPE.RAW,
  defaultModelRendering: RENDER_TYPE.STRING,
  displayRequestDuration: RENDER_TYPE.RAW,
  filter: RENDER_TYPE.RAW,
  showExtensions: RENDER_TYPE.RAW,
  showCommonExtensions: RENDER_TYPE.RAW,
  queryConfigEnabled: RENDER_TYPE.RAW,
  displayOperationId: RENDER_TYPE.RAW,
  tagsSorter: RENDER_TYPE.RAW,
  onComplete: RENDER_TYPE.RAW,
  syntaxHighlight: RENDER_TYPE.JSON_STRING,
  tryItOutEnabled: RENDER_TYPE.RAW,
  requestSnippetsEnabled: RENDER_TYPE.RAW,
  requestSnippets: RENDER_TYPE.JSON_STRING,
  oauth2RedirectUrl: RENDER_TYPE.STRING,
  showMutabledRequest: RENDER_TYPE.RAW,
  request: RENDER_TYPE.JSON_STRING,
  supportedSubmitMethods: RENDER_TYPE.JSON_STRING,
  validatorUrl: RENDER_TYPE.STRING,
  withCredentials: RENDER_TYPE.RAW,
  modelPropertyMacro: RENDER_TYPE.RAW,
  parameterMacro: RENDER_TYPE.RAW
};
var renderSwaggerUIOptions = /* @__PURE__ */ __name((options) => {
  const optionsStrings = Object.entries(options).map(([k, v]) => {
    const key = k;
    if (RENDER_TYPE_MAP[key] === RENDER_TYPE.STRING) {
      return `${key}: '${v}'`;
    }
    if (RENDER_TYPE_MAP[key] === RENDER_TYPE.STRING_ARRAY) {
      if (!Array.isArray(v)) {
        return "";
      }
      return `${key}: [${v.map((ve) => `${ve}`).join(",")}]`;
    }
    if (RENDER_TYPE_MAP[key] === RENDER_TYPE.JSON_STRING) {
      return `${key}: ${JSON.stringify(v)}`;
    }
    if (RENDER_TYPE_MAP[key] === RENDER_TYPE.RAW) {
      return `${key}: ${v}`;
    }
    return "";
  }).join(",");
  return optionsStrings;
}, "renderSwaggerUIOptions");
var remoteAssets = /* @__PURE__ */ __name(({ version: version2 }) => {
  const url = `https://cdn.jsdelivr.net/npm/swagger-ui-dist${version2 !== void 0 ? `@${version2}` : ""}`;
  return {
    css: [`${url}/swagger-ui.css`],
    js: [`${url}/swagger-ui-bundle.js`]
  };
}, "remoteAssets");
var _a;
var SwaggerUI = /* @__PURE__ */ __name((options) => {
  const asset = remoteAssets({ version: options?.version });
  delete options.version;
  if (options.manuallySwaggerUIHtml) {
    return options.manuallySwaggerUIHtml(asset);
  }
  const optionsStrings = renderSwaggerUIOptions(options);
  return `
    <div>
      <div id="swagger-ui"></div>
      ${asset.css.map((url) => html`<link rel="stylesheet" href="${url}" />`)}
      ${asset.js.map((url) => html(_a || (_a = __template(['<script src="', '" crossorigin="anonymous"><\/script>'])), url))}
      <script>
        window.onload = () => {
          window.ui = SwaggerUIBundle({
            dom_id: '#swagger-ui',${optionsStrings},
          })
        }
      <\/script>
    </div>
  `;
}, "SwaggerUI");
var middleware = /* @__PURE__ */ __name((options) => async (c) => {
  return c.html(
    /* html */
    `
      <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <meta name="description" content="SwaggerUI" />
          <title>SwaggerUI</title>
        </head>
        <body>
          ${SwaggerUI(options)}
        </body>
      </html>
    `
  );
}, "middleware");

// node_modules/teenybase/dist/worker/util/openapi.js
var OpenApiExtension = class extends $DBExtension {
  constructor(db, swagger = true) {
    super(db);
    extendZodWithOpenApi(external_exports);
    this.routes.push({
      path: "/doc",
      method: "get",
      handler: { raw: async () => {
        return db.c.json(this.getDoc());
      } },
      zod: () => ({
        description: "OpenAPI documentation",
        request: {},
        responses: {
          "200": {
            description: "Success",
            content: { "application/json": {
              schema: external_exports.record(external_exports.unknown())
            } }
          }
        }
      })
    });
    if (swagger) {
      this.routes.push({
        path: "/doc/ui",
        method: "get",
        handler: { raw: async () => {
          const res = await middleware({ url: this.db.apiBase + "/doc" })(db.c, async () => {
            return;
          });
          return res ? res : void 0;
        } },
        zod: () => ({
          description: "Swagger UI",
          request: {},
          responses: {
            "200": {
              description: "Success",
              content: { "text/html": {
                schema: external_exports.string()
              } }
            }
          }
        })
      });
    }
  }
  getDoc() {
    const registry = new OpenAPIRegistry();
    this.getApiRoutes(this.db.getRoutes(), this.db.apiBase).forEach((route) => registry.registerPath(route));
    this.db.allTables().forEach((table3) => this.getApiRoutes(table3.getRoutes(), this.db.apiTableBase + "/" + table3.name).forEach((route) => registry.registerPath(route)));
    const generator = new OpenApiGeneratorV31(registry.definitions);
    const doc = generator.generateDocument({
      openapi: "3.1.0",
      info: {
        version: "1.0.0",
        title: "Teenybase API"
        // description: '',
        // contact: {},
        // license: {},
        // termsOfService: '',
      }
    });
    return doc;
  }
  getApiRoutes(routes, prefix = "") {
    let apiRoutes = [];
    for (const route of routes) {
      const zod = route.zod();
      if (!zod.request.headers)
        zod.request.headers = external_exports.object({ authorization: external_exports.string().min(1).max(255).optional() });
      apiRoutes.push({
        path: prefix + route.path,
        method: route.method.toLowerCase(),
        ...zod
      });
    }
    return apiRoutes;
  }
};
__name(OpenApiExtension, "OpenApiExtension");

// node_modules/teenybase/dist/worker/util/pocketui.js
var cookieName = "teeny-pocket-ui-access-token";
var cookieNameRec = "teeny-pocket-ui-user-data";
var PocketUIExtension = class extends $DBExtension {
  async getAuthToken() {
    return await getSignedCookie(this.db.c, this.db.c.env.ADMIN_SERVICE_TOKEN || "admin", cookieName) || void 0;
  }
  // private async _initAuth(){
  //     const tok= await this._getAuthToken()
  //     if(tok) return this.db.initAuth(tok)
  // }
  uiVersion = "latest";
  baseUrl = "https://cdn.jsdelivr.net/npm/@teenybase/pocket-ui@POCKET_UI_VERSION/dist/";
  // baseUrl = 'http://localhost:4173/'
  constructor(db, baseUrl, uiVersion) {
    super(db);
    if (baseUrl)
      this.baseUrl = baseUrl;
    if (uiVersion)
      this.uiVersion = uiVersion;
    this.routes.push({
      path: "/pocket/logout",
      method: "get",
      handler: {
        raw: async () => {
          deleteCookie(this.db.c, cookieName);
          deleteCookie(this.db.c, cookieNameRec);
          return this.db.c.redirect("./");
        }
      },
      zod: () => ({
        description: "Logout of Pocket UI",
        request: {},
        responses: {
          "302": {
            description: "Redirect to login"
          }
        }
      })
    });
    this.routes.push({
      path: "/pocket/login",
      method: "get",
      handler: {
        raw: async () => {
          if (this.db.auth.uid)
            return this.db.c.redirect("./");
          return this.loginPage();
        }
      },
      zod: () => ({
        description: "Login for Pocket UI",
        request: {},
        responses: {
          "200": {
            description: "Success",
            content: {
              "text/html": {
                schema: external_exports.string()
              }
            }
          }
        }
      })
    });
    this.routes.push({
      // login as viewer/editor/superadmin,
      // user should pass POCKET_UI_VIEWER_PASSWORD, POCKET_UI_EDITOR_PASSWORD, or ADMIN_SERVICE_TOKEN
      path: "/pocket/login",
      method: "post",
      handler: {
        raw: async () => {
          if (this.db.auth.uid)
            return this.db.c.redirect("./");
          let { username, password } = await this.db.getRequestBody() ?? {};
          if (!password)
            return this.loginPage("Password required", 400);
          if (username === "viewer" && password === this.db.c.env["POCKET_UI_VIEWER_PASSWORD"])
            password = this.db.c.env["ADMIN_SERVICE_TOKEN"];
          if (username === "editor" && password === this.db.c.env["POCKET_UI_EDITOR_PASSWORD"])
            password = this.db.c.env["ADMIN_SERVICE_TOKEN"];
          let err = "Invalid password";
          let token = null;
          try {
            await this.db.initAuth(password);
            token = await this.db.generateAdminToken(username || "viewer");
          } catch (e) {
            if (this.db.c.env.RESPOND_WITH_ERRORS && e?.message)
              err = "Unable to login - " + e.message;
            token = null;
          }
          if (!token)
            return this.loginPage(err, 400);
          const data = decode(token).payload;
          data.email = data.sub;
          await setSignedCookie(this.db.c, cookieName, token, this.db.c.env.ADMIN_SERVICE_TOKEN || "admin", {
            httpOnly: true,
            secure: this.db.c.req.raw.url.startsWith("https://"),
            sameSite: "Strict",
            maxAge: 60 * 60
          });
          setCookie(this.db.c, cookieNameRec, btoa(JSON.stringify(data)), {
            httpOnly: false,
            secure: this.db.c.req.raw.url.startsWith("https://"),
            sameSite: "Strict",
            maxAge: 60 * 60
          });
          return this.db.c.redirect("./");
        }
      },
      zod: () => ({
        description: "Login for Pocket UI",
        request: {
          body: {
            description: "Login as admin with role viewer/editor/superadmin",
            content: {
              "application/json": {
                schema: external_exports.object({
                  username: external_exports.string().min(1).max(255).default("viewer").describe("Role for logging in"),
                  password: external_exports.string().min(1).max(255).describe("POCKET_UI_VIEWER_PASSWORD, POCKET_UI_EDITOR_PASSWORD, or ADMIN_SERVICE_TOKEN")
                })
              }
            },
            required: true
          }
        },
        responses: {
          "302": { description: "Login success" },
          "400": {
            description: "Invalid password/Bad request",
            content: {
              "text/html": {
                schema: external_exports.string()
              }
            }
          }
        }
      })
    });
    this.routes.push({
      path: "/pocket/*",
      method: "get",
      handler: {
        raw: async (_params, path) => {
          const base2 = (this.baseUrl || "").replace(/POCKET_UI_VERSION/g, this.uiVersion);
          path = path.replace("/pocket/", "").replace("/pocket", "") || "index.html";
          const res = await fetch(base2 + path);
          if (path.endsWith(".html")) {
            const html2 = await res.text();
            return this.db.c.html(html2);
          }
          return res;
        }
      },
      zod: () => ({
        description: "Pocket UI for teenybase",
        request: {},
        responses: {
          "302": { description: "Not logged in" },
          "200": {
            description: "UI",
            content: {
              "text/html": {
                schema: external_exports.string()
              }
            }
          }
        }
      })
    });
  }
  // minimal login page, but a proper one is used in pocket-ui
  loginPage = (msg, code = 200) => this.db.c.html(`
  <!DOCTYPE html>
    <html lang="en" data-theme="light">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css"/>
      <title>Login</title>
    </head>
    <body style="margin: 3rem;">
    <article style="max-width: 600px; margin: auto; padding: 30px;">
          <h1>Pocket UI Login</h1>
          ${msg ? `<p style="color:red">${msg}</p>` : ""}
      <form action="login" method="post" style="display: flex; flex-direction: column; gap: 10px;">
          <input type="text" name="username" value="viewer" required>
          <input type="password" name="password" placeholder="ADMIN_SERVICE_TOKEN" required autofocus>
          <button class="contrast" type="submit">Login</button>
      </form>
      </article>
    </body>
    </html>
  `, code);
};
__name(PocketUIExtension, "PocketUIExtension");

// migrations/config.json
var config_default = {
  "//": "Config generated by teenybase on 2026-03-22T13:28:06.738Z. Do not modify this file.",
  tables: [
    {
      name: "users",
      fields: [
        {
          name: "id",
          sqlType: "text",
          type: "text",
          usage: "record_uid",
          primary: true,
          notNull: true,
          noUpdate: true
        },
        {
          name: "created",
          sqlType: "timestamp",
          type: "date",
          usage: "record_created",
          notNull: true,
          default: {
            q: "CURRENT_TIMESTAMP"
          },
          noUpdate: true,
          noInsert: true
        },
        {
          name: "updated",
          sqlType: "timestamp",
          type: "date",
          usage: "record_updated",
          notNull: true,
          default: {
            q: "CURRENT_TIMESTAMP"
          },
          noUpdate: true,
          noInsert: true
        },
        {
          name: "username",
          sqlType: "text",
          type: "text",
          usage: "auth_username",
          unique: true,
          notNull: true
        },
        {
          name: "email",
          sqlType: "text",
          type: "text",
          usage: "auth_email",
          unique: true,
          notNull: true,
          noUpdate: true
        },
        {
          name: "email_verified",
          sqlType: "boolean",
          type: "bool",
          usage: "auth_email_verified",
          notNull: true,
          default: {
            l: false
          },
          noUpdate: true,
          noInsert: true
        },
        {
          name: "password",
          sqlType: "text",
          type: "text",
          usage: "auth_password",
          notNull: true,
          noSelect: true
        },
        {
          name: "password_salt",
          sqlType: "text",
          type: "text",
          usage: "auth_password_salt",
          notNull: true,
          noUpdate: true,
          noInsert: true,
          noSelect: true
        },
        {
          name: "name",
          sqlType: "text",
          type: "text",
          usage: "auth_name",
          notNull: true
        },
        {
          name: "avatar",
          sqlType: "text",
          type: "file",
          usage: "auth_avatar"
        },
        {
          name: "role",
          sqlType: "text",
          type: "text",
          usage: "auth_audience"
        },
        {
          name: "meta",
          sqlType: "json",
          type: "json",
          usage: "auth_metadata"
        }
      ],
      indexes: [
        {
          fields: "role COLLATE NOCASE"
        }
      ],
      triggers: [
        {
          name: "raise_on_created_update",
          event: "UPDATE",
          seq: "BEFORE",
          updateOf: [
            "created"
          ],
          body: {
            q: "SELECT RAISE(FAIL, 'Cannot update created column') WHERE OLD.created != NEW.created"
          }
        }
      ],
      autoSetUid: true,
      extensions: [
        {
          name: "rules",
          listRule: "(auth.uid == id) | auth.role ~ '%admin' | meta->>'$.pvt'!=true",
          viewRule: "(auth.uid == id) | auth.role ~ '%admin'",
          createRule: "(auth.uid == null & role == 'guest') | (auth.role ~ '%admin' & role != 'superadmin')",
          updateRule: "(auth.uid == id & role == new.role & meta == new.meta) | (auth.role ~ '%admin' & new.role != 'superadmin' & (role != 'superadmin' | auth.role = 'superadmin'))",
          deleteRule: "auth.role ~ '%admin' & role !~ '%admin'"
        },
        {
          name: "auth",
          passwordType: "sha256",
          passwordCurrentSuffix: "Current",
          passwordConfirmSuffix: "Confirm",
          jwtSecret: "$JWT_SECRET_USERS",
          jwtTokenDuration: 10800,
          maxTokenRefresh: 4,
          emailTemplates: {
            verification: {
              variables: {
                message_title: "Email Verification",
                message_description: "Welcome to {{APP_NAME}}. Click the button below to verify your email address.",
                message_footer: "If you did not request this, please ignore this email.",
                action_text: "Verify Email",
                action_link: "{{APP_URL}}#/verify-email/{{TOKEN}}"
              }
            },
            passwordReset: {
              variables: {
                message_title: "Password Reset",
                message_description: "Click the button below to reset the password for your {{APP_NAME}} account.",
                message_footer: "If you did not request this, you can safely ignore this email.",
                action_text: "Reset Password",
                action_link: "{{APP_URL}}#/reset-password/{{TOKEN}}"
              }
            }
          }
        }
      ]
    },
    {
      name: "notes",
      fields: [
        {
          name: "id",
          sqlType: "text",
          type: "text",
          usage: "record_uid",
          primary: true,
          notNull: true,
          noUpdate: true
        },
        {
          name: "created",
          sqlType: "timestamp",
          type: "date",
          usage: "record_created",
          notNull: true,
          default: {
            q: "CURRENT_TIMESTAMP"
          },
          noUpdate: true,
          noInsert: true
        },
        {
          name: "updated",
          sqlType: "timestamp",
          type: "date",
          usage: "record_updated",
          notNull: true,
          default: {
            q: "CURRENT_TIMESTAMP"
          },
          noUpdate: true,
          noInsert: true
        },
        {
          name: "owner_id",
          sqlType: "text",
          type: "relation",
          notNull: true,
          foreignKey: {
            table: "users",
            column: "id"
          }
        },
        {
          name: "title",
          sqlType: "text",
          type: "text",
          notNull: true
        },
        {
          name: "content",
          sqlType: "text",
          type: "editor",
          notNull: true
        },
        {
          name: "is_public",
          sqlType: "boolean",
          type: "bool",
          notNull: true,
          default: {
            l: false
          }
        },
        {
          name: "slug",
          sqlType: "text",
          type: "text",
          unique: true,
          notNull: true,
          noUpdate: true
        },
        {
          name: "tags",
          sqlType: "text",
          type: "text"
        },
        {
          name: "meta",
          sqlType: "json",
          type: "json"
        },
        {
          name: "cover",
          sqlType: "text",
          type: "file"
        },
        {
          name: "views",
          sqlType: "integer",
          type: "number",
          default: {
            l: 0
          },
          noUpdate: true,
          noInsert: true
        },
        {
          name: "archived",
          sqlType: "boolean",
          type: "bool",
          default: {
            l: false
          },
          noInsert: true
        },
        {
          name: "deleted_at",
          sqlType: "timestamp",
          type: "date",
          default: {
            l: null
          },
          noInsert: true
        }
      ],
      indexes: [
        {
          fields: "owner_id"
        },
        {
          fields: "tags COLLATE NOCASE"
        },
        {
          fields: "is_public"
        },
        {
          fields: "archived"
        },
        {
          fields: "deleted_at"
        }
      ],
      triggers: [
        {
          name: "raise_on_created_update",
          event: "UPDATE",
          seq: "BEFORE",
          updateOf: [
            "created"
          ],
          body: {
            q: "SELECT RAISE(FAIL, 'Cannot update created column') WHERE OLD.created != NEW.created"
          }
        }
      ],
      autoSetUid: true,
      extensions: [
        {
          name: "rules",
          viewRule: "(is_public = true & !deleted_at & !archived) | auth.role ~ '%admin' | (auth.uid != null & owner_id == auth.uid)",
          listRule: "(is_public & !deleted_at & !archived) | auth.role ~ '%admin' | (auth.uid != null & owner_id == auth.uid)",
          createRule: "auth.uid != null & owner_id == auth.uid",
          updateRule: "auth.uid != null & owner_id == auth.uid & owner_id = new.owner_id",
          deleteRule: "auth.role ~ '%admin' | (auth.uid != null & owner_id == auth.uid)"
        }
      ],
      fullTextSearch: {
        fields: [
          "title",
          "content",
          "tags"
        ],
        tokenize: "trigram",
        migrateTableQuery: true
      }
    },
    {
      name: "kv_store",
      fields: [
        {
          name: "key",
          sqlType: "text",
          type: "text",
          primary: true,
          notNull: true
        },
        {
          name: "value",
          sqlType: "json",
          type: "json",
          notNull: true
        },
        {
          name: "expire",
          sqlType: "timestamp",
          type: "date"
        }
      ],
      autoSetUid: false,
      extensions: []
    }
  ],
  jwtSecret: "$JWT_SECRET_MAIN",
  appName: "Sample app",
  appUrl: "https://sample.example.com",
  email: {
    from: "Sender Name <noreply@example.com>",
    variables: {
      company_name: "Company",
      company_url: "https://example.com",
      company_address: "Company address",
      company_copyright: "Company",
      support_email: "support@example.com"
    },
    tags: [
      "tag-1"
    ],
    mailgun: {
      MAILGUN_API_KEY: "$MAILGUN_API_KEY",
      MAILGUN_API_SERVER: "mail.example.com",
      MAILGUN_WEBHOOK_SIGNING_KEY: "$MAILGUN_WEBHOOK_SIGNING_KEY",
      DISCORD_MAILGUN_NOTIFY_WEBHOOK: "xxxxxxxxx"
    }
  },
  version: 0
};

// src-backend/worker.ts
var app = teenyHono(async (c) => {
  const db = new $Database(c, config_default, c.env.PRIMARY_DB, c.env.PRIMARY_R2);
  db.extensions.push(new OpenApiExtension(db, true));
  db.extensions.push(new PocketUIExtension(db));
  return db;
}, void 0, {
  logger: false,
  cors: true
});
app.get("/", (c) => {
  return c.json({ message: "Hello Hono" });
});
app.get("/api/counter", async (c) => {
  const db = c.env.PRIMARY_DB;
  const row = await db.prepare("SELECT * FROM counter WHERE id = 1").first();
  if (!row) {
    return c.json({ total_walks: 0, total_distance_km: 0, total_meditation_min: 0, total_talk_min: 0, last_walk_at: null });
  }
  return c.json(row, 200, {
    "Cache-Control": "public, max-age=10800"
  });
});
app.post("/api/counter", async (c) => {
  const token = c.req.header("X-Device-Token");
  if (!token || token.length < 8) {
    return c.json({ error: "missing token" }, 401);
  }
  const db = c.env.PRIMARY_DB;
  const recent = await db.prepare(
    "SELECT 1 FROM counter_rate_limit WHERE token = ? AND created_at > datetime('now', '-1 hour')"
  ).bind(token).first();
  if (recent) {
    return c.json({ error: "rate limited" }, 429);
  }
  const body = await c.req.json();
  const walks = Math.min(10, Math.max(0, Math.floor(body.walks ?? 0)));
  const distanceKm = Math.min(200, Math.max(0, body.distance_km ?? 0));
  const meditationMin = Math.min(480, Math.max(0, Math.floor(body.meditation_min ?? 0)));
  const talkMin = Math.min(480, Math.max(0, Math.floor(body.talk_min ?? 0)));
  if (walks === 0 && distanceKm === 0) {
    return c.json({ error: "nothing to count" }, 400);
  }
  await db.batch([
    db.prepare(
      `UPDATE counter SET
        total_walks = total_walks + ?,
        total_distance_km = total_distance_km + ?,
        total_meditation_min = total_meditation_min + ?,
        total_talk_min = total_talk_min + ?,
        last_walk_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      WHERE id = 1`
    ).bind(walks, distanceKm, meditationMin, talkMin),
    db.prepare(
      "INSERT INTO counter_rate_limit (token, created_at) VALUES (?, datetime('now'))"
    ).bind(token),
    db.prepare(
      "DELETE FROM counter_rate_limit WHERE created_at < datetime('now', '-2 hours')"
    )
  ]);
  return c.json({ ok: true });
});
var worker_default = app;

// node_modules/wrangler/templates/middleware/middleware-ensure-req-body-drained.ts
var drainBody = /* @__PURE__ */ __name(async (request, env2, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env2);
  } finally {
    try {
      if (request.body !== null && !request.bodyUsed) {
        const reader = request.body.getReader();
        while (!(await reader.read()).done) {
        }
      }
    } catch (e) {
      console.error("Failed to drain the unused request body.", e);
    }
  }
}, "drainBody");
var middleware_ensure_req_body_drained_default = drainBody;

// node_modules/wrangler/templates/middleware/middleware-miniflare3-json-error.ts
function reduceError(e) {
  return {
    name: e?.name,
    message: e?.message ?? String(e),
    stack: e?.stack,
    cause: e?.cause === void 0 ? void 0 : reduceError(e.cause)
  };
}
__name(reduceError, "reduceError");
var jsonError = /* @__PURE__ */ __name(async (request, env2, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env2);
  } catch (e) {
    const error4 = reduceError(e);
    return Response.json(error4, {
      status: 500,
      headers: { "MF-Experimental-Error-Stack": "true" }
    });
  }
}, "jsonError");
var middleware_miniflare3_json_error_default = jsonError;

// .wrangler/tmp/bundle-6Fy5QV/middleware-insertion-facade.js
var __INTERNAL_WRANGLER_MIDDLEWARE__ = [
  middleware_ensure_req_body_drained_default,
  middleware_miniflare3_json_error_default
];
var middleware_insertion_facade_default = worker_default;

// node_modules/wrangler/templates/middleware/common.ts
var __facade_middleware__ = [];
function __facade_register__(...args) {
  __facade_middleware__.push(...args.flat());
}
__name(__facade_register__, "__facade_register__");
function __facade_invokeChain__(request, env2, ctx, dispatch, middlewareChain) {
  const [head, ...tail] = middlewareChain;
  const middlewareCtx = {
    dispatch,
    next(newRequest, newEnv) {
      return __facade_invokeChain__(newRequest, newEnv, ctx, dispatch, tail);
    }
  };
  return head(request, env2, ctx, middlewareCtx);
}
__name(__facade_invokeChain__, "__facade_invokeChain__");
function __facade_invoke__(request, env2, ctx, dispatch, finalMiddleware) {
  return __facade_invokeChain__(request, env2, ctx, dispatch, [
    ...__facade_middleware__,
    finalMiddleware
  ]);
}
__name(__facade_invoke__, "__facade_invoke__");

// .wrangler/tmp/bundle-6Fy5QV/middleware-loader.entry.ts
var __Facade_ScheduledController__ = class {
  constructor(scheduledTime, cron, noRetry) {
    this.scheduledTime = scheduledTime;
    this.cron = cron;
    this.#noRetry = noRetry;
  }
  #noRetry;
  noRetry() {
    if (!(this instanceof __Facade_ScheduledController__)) {
      throw new TypeError("Illegal invocation");
    }
    this.#noRetry();
  }
};
__name(__Facade_ScheduledController__, "__Facade_ScheduledController__");
function wrapExportedHandler(worker) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return worker;
  }
  for (const middleware2 of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware2);
  }
  const fetchDispatcher = /* @__PURE__ */ __name(function(request, env2, ctx) {
    if (worker.fetch === void 0) {
      throw new Error("Handler does not export a fetch() function.");
    }
    return worker.fetch(request, env2, ctx);
  }, "fetchDispatcher");
  return {
    ...worker,
    fetch(request, env2, ctx) {
      const dispatcher = /* @__PURE__ */ __name(function(type, init) {
        if (type === "scheduled" && worker.scheduled !== void 0) {
          const controller = new __Facade_ScheduledController__(
            Date.now(),
            init.cron ?? "",
            () => {
            }
          );
          return worker.scheduled(controller, env2, ctx);
        }
      }, "dispatcher");
      return __facade_invoke__(request, env2, ctx, dispatcher, fetchDispatcher);
    }
  };
}
__name(wrapExportedHandler, "wrapExportedHandler");
function wrapWorkerEntrypoint(klass) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return klass;
  }
  for (const middleware2 of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware2);
  }
  return class extends klass {
    #fetchDispatcher = (request, env2, ctx) => {
      this.env = env2;
      this.ctx = ctx;
      if (super.fetch === void 0) {
        throw new Error("Entrypoint class does not define a fetch() function.");
      }
      return super.fetch(request);
    };
    #dispatcher = (type, init) => {
      if (type === "scheduled" && super.scheduled !== void 0) {
        const controller = new __Facade_ScheduledController__(
          Date.now(),
          init.cron ?? "",
          () => {
          }
        );
        return super.scheduled(controller);
      }
    };
    fetch(request) {
      return __facade_invoke__(
        request,
        this.env,
        this.ctx,
        this.#dispatcher,
        this.#fetchDispatcher
      );
    }
  };
}
__name(wrapWorkerEntrypoint, "wrapWorkerEntrypoint");
var WRAPPED_ENTRY;
if (typeof middleware_insertion_facade_default === "object") {
  WRAPPED_ENTRY = wrapExportedHandler(middleware_insertion_facade_default);
} else if (typeof middleware_insertion_facade_default === "function") {
  WRAPPED_ENTRY = wrapWorkerEntrypoint(middleware_insertion_facade_default);
}
var middleware_loader_entry_default = WRAPPED_ENTRY;
export {
  __INTERNAL_WRANGLER_MIDDLEWARE__,
  middleware_loader_entry_default as default
};
//# sourceMappingURL=worker.js.map
