import { AsyncLocalStorage } from 'node:async_hooks';
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';
import { formatWithOptions } from 'node:util';

// Keep console text separate from SDK commands, even when it contains JSON.
// Install before importing the extension so module-level logs are captured too.
for (const level of ['log', 'info', 'debug', 'warn', 'error']) {
  console[level] = (...args) => {
    process.stdout.write(`${JSON.stringify({
      protocol: 'talos',
      version: 1,
      method: 'console',
      parameters: { level, message: formatWithOptions({ colors: false }, ...args) },
    })}\n`);
  };
}

const [entrypoint, ...preferredLanguages] = process.argv.slice(2);
// Swift supplies the same ordered macOS language preferences used by native windows.
Object.defineProperty(globalThis, '__talosPreferredLanguages', {
  value: preferredLanguages.length ? preferredLanguages : ['en'],
});

if (!entrypoint) {
  throw new Error('Talos did not provide an extension entrypoint');
}

let nextRequestID = 0;
const pendingDialogRequests = new Map();
const pendingModelRequests = new Map();
const activations = new Map();

// Signals are local process objects, never part of the JSON sent to a window.
function scopedContext(context, signal) {
  return Object.defineProperty({ ...context }, 'signal', { value: signal });
}
function finishModelRequest(requestID, pending, error) {
  pendingModelRequests.delete(requestID);
  pending.cleanup();
  pending.finished = true;
  pending.error = error;
  pending.reject?.(error);
  pending.waiting?.();
}
function stopPendingRequests() {
  for (const [id, pending] of pendingModelRequests) {
    finishModelRequest(id, pending, new Error('Talos closed during model generation'));
  }
  for (const [id, pending] of pendingDialogRequests) {
    pendingDialogRequests.delete(id);
    pending.cleanup();
    pending.reject(new Error('Talos closed before the dialog received a response'));
  }
}
Object.defineProperty(globalThis, Symbol.for('talos.modelRequest'), {
  value: (prompt, options = []) => {
    const settings = Array.isArray(options) ? { tools: options } : options;
    const tools = settings.tools ?? [];
    const stream = settings.stream === true;
    const requestID = `${process.pid}-${++nextRequestID}`;
    const context = activationContext.getStore();
    const signal = context?.signal && settings.signal
      ? AbortSignal.any([context.signal, settings.signal]) : context?.signal ?? settings.signal;
    const pending = { context, tools: new Map(tools.map(tool => [tool.name, tool])),
      stream, latest: undefined, last: undefined, waiting: undefined, finished: false, error: undefined };
    const send = (method) => process.stdout.write(`${JSON.stringify({ protocol: 'talos', version: 1,
      method, requestID, parameters: method === 'modelRequest' ? {
        prompt, tools: tools.map(({ name, description }) => ({ name, description })),
        instructions: settings.instructions, temperature: settings.temperature,
        maximumResponseTokens: settings.maximumResponseTokens, useCase: settings.useCase, stream,
      } : {} })}\n`);
    const cancel = () => {
      if (!pendingModelRequests.delete(requestID)) return;
      signal?.removeEventListener('abort', cancel);
      pending.finished = true;
      pending.error = new DOMException('The request was aborted', 'AbortError');
      pending.reject?.(pending.error);
      pending.waiting?.();
      send('modelCancel');
    };
    pending.cleanup = () => signal?.removeEventListener('abort', cancel);
    if (signal?.aborted) {
      if (!stream) return Promise.reject(new DOMException('The request was aborted', 'AbortError'));
      return (async function* () { throw new DOMException('The request was aborted', 'AbortError'); })();
    }
    pendingModelRequests.set(requestID, pending);
    signal?.addEventListener('abort', cancel, { once: true });
    send('modelRequest');
    if (!stream) return new Promise((resolve, reject) => { pending.resolve = resolve; pending.reject = reject; });
    return (async function* () {
      try {
        while (true) {
          if (pending.latest !== undefined) {
            const snapshot = pending.latest;
            pending.latest = undefined;
            pending.last = snapshot;
            yield snapshot;
            continue;
          }
          if (pending.error) throw pending.error;
          if (pending.finished) return;
          await new Promise(resolve => { pending.waiting = resolve; });
          pending.waiting = undefined;
        }
      } finally { cancel(); }
    })();
  },
});
function modelToolReply(requestID, parameters) {
  process.stdout.write(`${JSON.stringify({ protocol: 'talos', version: 1,
    method: 'modelToolResponse', requestID, parameters })}\n`);
}
async function invokeModelTool(command) {
  const pending = pendingModelRequests.get(command.modelRequestID);
  const tool = pending?.tools.get(command.toolName);
  try {
    if (!pending || !tool) throw new Error('Unknown model tool');
    if (typeof command.input !== 'string' || Buffer.byteLength(command.input) > 8192) {
      throw new Error('Invalid model tool input');
    }
    const result = await activationContext.run(pending.context, () => tool.call(command.input));
    if (typeof result !== 'string' || Buffer.byteLength(result) > 8192) {
      throw new Error('Model tool must return at most 8 KB of text');
    }
    modelToolReply(command.requestID, { result });
  } catch (error) {
    modelToolReply(command.requestID, { error: String(error?.message ?? error).slice(0, 2048) });
  }
}

function requestDialog(kind, message) {
  const requestID = `${process.pid}-${++nextRequestID}`;
  const signal = activationContext.getStore()?.signal;
  return new Promise((resolve, reject) => {
    const cancel = () => {
      if (!pendingDialogRequests.delete(requestID)) return;
      cleanup();
      reject(new DOMException('The dialog was aborted', 'AbortError'));
    };
    const cleanup = () => signal?.removeEventListener('abort', cancel);
    if (signal?.aborted) { reject(new DOMException('The dialog was aborted', 'AbortError')); return; }
    pendingDialogRequests.set(requestID, { resolve, reject, cleanup });
    signal?.addEventListener('abort', cancel, { once: true });
    process.stdout.write(`${JSON.stringify({ protocol: 'talos', version: 1,
      method: 'dialog', requestID, parameters: { kind, message: message === undefined ? '' : String(message) },
    })}\n`);
  });
}

globalThis.alert = async (message) => {
  await requestDialog('alert', message);
};

globalThis.confirm = async (message) => {
  return Boolean(await requestDialog('confirm', message));
};

// Keep each invocation attached to its own async work, including timers and promises.
// The SDK reads this accessor so separately bundled copies share the host's scope.
const activationContext = new AsyncLocalStorage();
Object.defineProperty(globalThis, Symbol.for('talos.activationContext'), {
  value: () => activationContext.getStore(),
});

// Each window keeps its own activation, even when later drops reuse this process.
const windows = new Map();
const windowRequests = new Map();
Object.defineProperty(globalThis, Symbol.for('talos.registerWindow'), {
  value: (id, context, handler) => windows.set(id, { context, handler }),
});
function closeWindow(id) {
  windows.delete(id);
  for (const [requestID, request] of windowRequests) {
    if (request.windowID === id) { request.controller.abort(); windowRequests.delete(requestID); }
  }
}
function windowReply(requestID, parameters) {
  process.stdout.write(`${JSON.stringify({ protocol: 'talos', version: 1,
    method: 'windowReply', requestID, parameters })}\n`);
}
async function invokeWindow(command) {
  const { requestID, windowID, method, payloadJSON } = command;
  const window = windows.get(windowID);
  const controller = new AbortController();
  windowRequests.set(requestID, { windowID, controller });
  try {
    if (!window || typeof window.handler !== 'function') throw new Error('Window has no request handler');
    if (typeof method !== 'string' || method.length > 128 || typeof payloadJSON !== 'string' || Buffer.byteLength(payloadJSON) > 32768) {
      throw new Error('Invalid window request');
    }
    const context = scopedContext(window.context, controller.signal);
    const result = await activationContext.run(context,
      () => window.handler(method, JSON.parse(payloadJSON), context, controller.signal));
    const resultJSON = JSON.stringify(result ?? null);
    if (!controller.signal.aborted) windowReply(requestID, { resultJSON });
  } catch (error) {
    if (!controller.signal.aborted) windowReply(requestID, { error: String(error?.message ?? error).slice(0, 4096) });
  } finally { windowRequests.delete(requestID); controller.abort(); }
}

// A hover may start this host before a drop. Do not execute extension code until activation.
let extensionPromise;
function loadExtension() {
  return extensionPromise ??= import(pathToFileURL(entrypoint)).then((extension) => {
    if (typeof extension.activate !== 'function') {
      throw new Error('The extension must export an activate function');
    }
    if (typeof extension.deactivate !== 'function') {
      throw new Error('The extension must export a deactivate function');
    }
    return extension;
  });
}

let deactivated = false;

async function deactivate() {
  if (deactivated) return;
  deactivated = true;
  for (const activation of activations.values()) activation.controller.abort();
  stopPendingRequests();
  for (const id of windows.keys()) closeWindow(id);
  if (!extensionPromise) return;
  // A failed import was already reported by activation; there is nothing to tear down.
  const extension = await extensionPromise.catch(() => undefined);
  await extension?.deactivate();
}

const commands = createInterface({ input: process.stdin, crlfDelay: Infinity });
let activationQueue = Promise.resolve();
// Native teardown closes the pipes and sends SIGTERM; give scoped helpers time to clean up.
process.once('SIGTERM', () => { void deactivate(); commands.close(); });
process.stdout.on('error', (error) => {
  if (error.code !== 'EPIPE') throw error;
  void deactivate();
  commands.close();
});

for await (const line of commands) {
  if (!line.trim()) continue;

  try {
    const command = JSON.parse(line);

    if (command.type === 'cancelActivation') {
      activations.get(command.requestID)?.controller.abort();
      continue;
    }
    if (command.type === 'windowRequest') { void invokeWindow(command); continue; }
    if (command.type === 'windowClosed') { closeWindow(command.windowID); continue; }
    if (command.type === 'cancelWindowRequest') {
      windowRequests.get(command.requestID)?.controller.abort();
      windowRequests.delete(command.requestID);
      continue;
    }
    if (command.type === 'modelToolRequest') { void invokeModelTool(command); continue; }
    if (command.type === 'modelSnapshot') {
      const pending = pendingModelRequests.get(command.requestID);
      if (pending?.stream) { pending.latest = command.result; pending.waiting?.(); }
      continue;
    }
    if (command.type === 'modelResponse') {
      const pending = pendingModelRequests.get(command.requestID);
      if (!pending) continue;
      pendingModelRequests.delete(command.requestID);
      pending.cleanup();
      pending.finished = true;
      if (command.error) pending.error = new Error(command.error);
      else if (pending.stream && pending.latest !== command.result && pending.last !== command.result) {
        pending.latest = command.result;
      }
      if (pending.stream) pending.waiting?.();
      else if (pending.error) pending.reject(pending.error);
      else pending.resolve(command.result);
      continue;
    }
    if (command.type === 'response') {
      const pendingRequest = pendingDialogRequests.get(command.requestID);
      if (!pendingRequest) continue; // A reply may arrive after cancellation.

      pendingDialogRequests.delete(command.requestID);
      pendingRequest.cleanup();
      pendingRequest.resolve(command.value);
      continue;
    }

    if (command.type === 'activate') {
      const context = command.context;
      if (!context || typeof context.action !== 'string' || !context.config ||
          typeof context.config !== 'object' || Array.isArray(context.config) || !Array.isArray(context.files)) {
        throw new Error('Talos provided an invalid activation context');
      }

      const requestID = command.requestID ?? `${process.pid}-activation-${++nextRequestID}`;
      const controller = new AbortController();
      const scoped = scopedContext(context, controller.signal);
      activations.set(requestID, { controller });
      activationQueue = activationQueue.then(async () => {
        let errorMessage;
        try {
          if (deactivated) throw new Error('The extension stopped before the action ran.');
          controller.signal.throwIfAborted();
          const extension = await loadExtension();
          controller.signal.throwIfAborted();
          await activationContext.run(scoped, () => extension.activate(scoped));
        } catch (error) {
          errorMessage = error instanceof Error ? error.message : String(error);
          if (!controller.signal.aborted) console.error(error instanceof Error ? error.stack ?? error.message : String(error));
        } finally {
          // Fire-and-forget work must not outlive its handler. Windows get their own request scopes.
          activations.delete(requestID);
          controller.abort();
          if (command.requestID) process.stdout.write(`${JSON.stringify({
            protocol: 'talos', version: 1, method: 'activationComplete', requestID,
            parameters: { error: errorMessage },
          })}\n`);
        }
      });
      continue;
    }

    if (command.type === 'deactivate') {
      await deactivate();
      await activationQueue;
      commands.close();
      break;
    }

    throw new Error(`Unknown Talos runtime command: ${command.type}`);
  } catch (error) {
    console.error(error instanceof Error ? error.stack ?? error.message : String(error));
  }
}

await deactivate();
await activationQueue;
activationContext.disable();
