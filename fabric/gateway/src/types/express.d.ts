// src/types/express.d.ts
import { AuthenticatedUser } from './index';

declare global {
  namespace Express {
    interface Request {
      user?: AuthenticatedUser;
      idempotencyKey?: string;
    }
  }
}

export {};
