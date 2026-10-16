// src/middleware/requestLogger.ts
import { NextFunction, Request, Response } from 'express';

export function requestLogger(req: Request, res: Response, next: NextFunction): void {
  const start = Date.now();
  const { method, originalUrl, ip } = req;

  res.on('finish', () => {
    const duration = Date.now() - start;
    const statusCode = res.statusCode;
    const userUid = (req as any).user?.uid ? `[user:${(req as any).user.uid}]` : '[anon]';
    const role = (req as any).user?.role ? `[role:${(req as any).user.role}]` : '';

    console.info(`${new Date().toISOString()} ${method} ${originalUrl} ${statusCode} ${duration}ms ${ip} ${userUid}${role}`);
  });

  next();
}
