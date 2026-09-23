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

function requestDialog(kind, message) {
  const requestID = `${process.pid}-${++nextRequestID}`;

  return new Promise((resolve, reject) => {
    pendingDialogRequests.set(requestID, { resolve, reject });
    process.stdout.write(
      `${JSON.stringify({
        protocol: 'talos',
        version: 1,
        method: 'dialog',
        requestID,
        parameters: {
          kind,
          message: message === undefined ? '' : String(message),
        },
      })}\n`,
    );
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
    const result = await activationContext.run(window.context,
      () => window.handler(method, JSON.parse(payloadJSON), window.context, controller.signal));
    const resultJSON = JSON.stringify(result ?? null);
    if (Buffer.byteLength(resultJSON) > 32768) throw new Error('Window response exceeds 32 KB');
    if (!controller.signal.aborted) windowReply(requestID, { resultJSON });
  } catch (error) {
    if (!controller.signal.aborted) windowReply(requestID, { error: String(error?.message ?? error).slice(0, 4096) });
  } finally { windowRequests.delete(requestID); }
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
  for (const id of windows.keys()) closeWindow(id);
  if (!extensionPromise) return;
  // A failed import was already reported by activation; there is nothing to tear down.
  const extension = await extensionPromise.catch(() => undefined);
  await extension?.deactivate();
}

const commands = createInterface({ input: process.stdin, crlfDelay: Infinity });
let activationQueue = Promise.resolve();

for await (const line of commands) {
  if (!line.trim()) continue;

  try {
    const command = JSON.parse(line);

    if (command.type === 'windowRequest') { void invokeWindow(command); continue; }
    if (command.type === 'windowClosed') { closeWindow(command.windowID); continue; }
    if (command.type === 'cancelWindowRequest') {
      windowRequests.get(command.requestID)?.controller.abort();
      windowRequests.delete(command.requestID);
      continue;
    }
    if (command.type === 'response') {
      const pendingRequest = pendingDialogRequests.get(command.requestID);
      if (!pendingRequest) {
        throw new Error(`Unknown Talos response: ${command.requestID}`);
      }

      pendingDialogRequests.delete(command.requestID);
      pendingRequest.resolve(command.value);
      continue;
    }

    if (command.type === 'activate') {
      const context = command.context;
      if (!context || typeof context.action !== 'string' || !context.config ||
          typeof context.config !== 'object' || Array.isArray(context.config) || !Array.isArray(context.files)) {
        throw new Error('Talos provided an invalid activation context');
      }

      activationQueue = activationQueue.then(async () => {
        if (deactivated) return;
        try {
          const extension = await loadExtension();
          await activationContext.run(context, () => extension.activate(context));
        } catch (error) {
          console.error(error instanceof Error ? error.stack ?? error.message : String(error));
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

for (const { reject } of pendingDialogRequests.values()) {
  reject(new Error('Talos closed before the dialog received a response'));
}
pendingDialogRequests.clear();
await deactivate();
await activationQueue;
