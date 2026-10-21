// src/middleware/errorHandler.ts
import { NextFunction, Request, Response } from 'express';
import { ERROR_CODES } from '../config/constants';
import { ApiResponse } from '../types';

export function errorHandler(
  err: any,
  req: Request,
  res: Response,
  next: NextFunction
): void {
  const message = err.message || 'An unexpected internal error occurred.';
  let statusCode = 500;
  let code: string = ERROR_CODES.INTERNAL_ERROR;

  if (message.startsWith('CONSENT_PENDING:')) {
    statusCode = 409;
    code = 'CONSENT_PENDING';
  } else if (message.startsWith('CONSENT_REJECTED:')) {
    statusCode = 422;
    code = 'CONSENT_REJECTED';
  } else if (message.includes('Unauthenticated') || message.includes('token') || message.includes('Bearer')) {
    statusCode = 401;
    code = ERROR_CODES.UNAUTHENTICATED;
  } else if (message.includes('Access Denied') || message.includes('Unauthorized') || message.includes('Forbidden')) {
    statusCode = 403;
    code = ERROR_CODES.FORBIDDEN;
  } else if (message.includes('FEATURE_DISABLED') || message.includes('Feature Disabled')) {
    statusCode = 403;
    code = ERROR_CODES.FEATURE_DISABLED;
  } else if (message.includes('not found') || message.includes('Not found')) {
    statusCode = 404;
    code = ERROR_CODES.NOT_FOUND;
  } else if (message.includes('Conflict') || message.includes('in progress')) {
    statusCode = 409;
    code = ERROR_CODES.CONFLICT;
  } else if (message.includes('Invalid') || message.includes('missing') || message.includes('required')) {
    statusCode = 400;
    code = ERROR_CODES.BAD_REQUEST;
  } else if (message.includes('unavailable') || message.includes('not configured')) {
    statusCode = 503;
    code = ERROR_CODES.SERVICE_UNAVAILABLE;
  }

  const response: ApiResponse = {
    success: false,
    error: {
      code,
      message
    }
  };

  res.status(statusCode).json(response);
}
