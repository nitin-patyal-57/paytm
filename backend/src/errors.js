/** Structured HTTP errors used across routes and services. */
export class HttpError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.code = code;
    if (details) this.details = details;
  }
}

export const errors = {
  notFound: (what = 'Transaction') => new HttpError(404, 'NOT_FOUND', `${what} not found`),
  conflict: (code, message) => new HttpError(409, code, message),
  badRequest: (code, message, details) => new HttpError(400, code, message, details),
  notImplemented: (message) => new HttpError(501, 'NOT_IMPLEMENTED', message)
};
