// Structured JSON logging for Edge Functions
// Provides consistent log format with request ID, function name, and timing.
// All logs are JSON-structured for easy parsing by monitoring tools (Sentry, Datadog, etc.)
//
// Per doc 21 security checklist: "Structured JSON logging with request ID"
// Per doc 20 monitoring: Logs should include request ID, function name, duration, status

export interface LogContext {
  requestId: string;
  functionName: string;
  userId?: string;
  [key: string]: unknown;
}

/**
 * Create a logger bound to a specific request context.
 *
 * Usage:
 *   const log = createLogger({ requestId: crypto.randomUUID(), functionName: 'place-order' });
 *   log.info('Order placed', { orderId: '...' });
 *   log.error('Payment failed', { error: err.message });
 */
export function createLogger(context: LogContext) {
  const base = { ...context, timestamp: '' };

  function formatMessage(level: string, message: string, data?: Record<string, unknown>) {
    return JSON.stringify({
      ...base,
      timestamp: new Date().toISOString(),
      level,
      message,
      ...data,
    });
  }

  return {
    info(message: string, data?: Record<string, unknown>) {
      console.log(formatMessage('INFO', message, data));
    },
    warn(message: string, data?: Record<string, unknown>) {
      console.warn(formatMessage('WARN', message, data));
    },
    error(message: string, data?: Record<string, unknown>) {
      console.error(formatMessage('ERROR', message, data));
    },
    debug(message: string, data?: Record<string, unknown>) {
      if (Deno.env.get('LOG_LEVEL') === 'DEBUG') {
        console.log(formatMessage('DEBUG', message, data));
      }
    },
  };
}

/**
 * Generate a short request ID for correlation across logs.
 */
export function generateRequestId(): string {
  return crypto.randomUUID().slice(0, 8);
}

/**
 * Measure execution time of an async operation.
 */
export async function measure<T>(
  label: string,
  fn: () => Promise<T>,
  log?: ReturnType<typeof createLogger>,
): Promise<T> {
  const start = performance.now();
  try {
    const result = await fn();
    const duration = Math.round(performance.now() - start);
    log?.debug(`${label} completed`, { durationMs: duration });
    return result;
  } catch (err) {
    const duration = Math.round(performance.now() - start);
    log?.error(`${label} failed`, {
      durationMs: duration,
      error: err instanceof Error ? err.message : String(err),
    });
    throw err;
  }
}
