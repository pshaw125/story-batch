export class PromptError extends Error {
  constructor(message: string, public readonly line = 1, public readonly column = 1) {
    super(`Line ${line}, column ${column}: ${message}`);
    this.name = 'PromptError';
  }
}
export function requireThat(test: unknown, message: string): asserts test {
  if (!test) throw new PromptError(message);
}
export function deepFreeze<T>(value: T): Readonly<T> {
  if (value && typeof value === 'object') {
    for (const item of Object.values(value)) deepFreeze(item);
    Object.freeze(value);
  }
  return value;
}
