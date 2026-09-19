// Lexical stand-ins, never aliases for an embedding host's global objects.
export const window = Object.freeze({});
export const console = Object.freeze({ log() {}, warn() {} });
