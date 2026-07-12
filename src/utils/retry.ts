export interface RetryOptions {
  attempts?: number;
  baseDelayMs?: number;
  onRetry?: (error: unknown, attempt: number) => void;
}

/**
 * Retry com backoff exponencial + jitter. Usado em ações de navegador
 * (que podem falhar por lentidão de render) e em chamadas de webhook.
 */
export async function withRetry<T>(fn: () => Promise<T>, options: RetryOptions = {}): Promise<T> {
  const { attempts = 3, baseDelayMs = 1000, onRetry } = options;
  let lastError: unknown;

  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      onRetry?.(error, attempt);
      if (attempt < attempts) {
        const jitter = Math.random() * 300;
        const delay = baseDelayMs * 2 ** (attempt - 1) + jitter;
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  throw lastError;
}

