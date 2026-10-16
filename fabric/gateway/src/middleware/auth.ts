// src/middleware/auth.ts
import { NextFunction, Request, Response } from 'express';
import { FirebaseAdminService } from '../services/firebaseAdmin';
import { AuthenticatedUser } from '../types';

export function authenticate(injectedAdmin?: FirebaseAdminService) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const firebaseAdmin = injectedAdmin || FirebaseAdminService.getInstance();
    try {
      const authHeader = req.headers.authorization;
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        res.status(401).json({
          success: false,
          error: {
            code: 'UNAUTHENTICATED',
            message: 'Unauthenticated: Missing or malformed Authorization header with Bearer token.'
          }
        });
        return;
      }

      const idToken = authHeader.split('Bearer ')[1].trim();
      if (!idToken) {
        res.status(401).json({
          success: false,
          error: {
            code: 'UNAUTHENTICATED',
            message: 'Unauthenticated: Empty Bearer token provided.'
          }
        });
        return;
      }

      // Verify token with Firebase Admin SDK (checkRevoked = true)
      let decodedToken;
      try {
        decodedToken = await firebaseAdmin.verifyIdToken(idToken);
      } catch (err: any) {
        res.status(401).json({
          success: false,
          error: {
            code: 'UNAUTHENTICATED',
            message: `Unauthenticated: ${err.message || 'Invalid, expired, or revoked Firebase ID token.'}`
          }
        });
        return;
      }

      const uid = decodedToken.uid;
      if (!uid) {
        res.status(401).json({
          success: false,
          error: {
            code: 'UNAUTHENTICATED',
            message: 'Unauthenticated: Token does not contain a valid user identity (UID).'
          }
        });
        return;
      }

      // Read authoritative user record and role from Firestore `users/{uid}`
      // Never trust client-supplied headers or body parameters for identity or role
      let userRecord = await firebaseAdmin.getAuthoritativeUser(uid);
      if (!userRecord) {
        // Fallback to minimal token info with default patient role if firestore user doc is not initialized
        userRecord = {
          uid,
          email: decodedToken.email,
          role: (decodedToken.role || 'patient').toLowerCase(),
          name: decodedToken.name || ''
        };
      }

      (req as any).user = userRecord;

      // Extract optional Idempotency-Key header
      const idempotencyKey = req.headers['idempotency-key'] as string;
      if (idempotencyKey) {
        (req as any).idempotencyKey = idempotencyKey.trim();
      }

      next();
    } catch (err: any) {
      res.status(500).json({
        success: false,
        error: {
          code: 'AUTH_ERROR',
          message: `Authentication error: ${err.message}`
        }
      });
    }
  };
}
