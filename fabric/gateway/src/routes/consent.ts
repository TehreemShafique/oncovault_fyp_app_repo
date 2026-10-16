/// <reference path="../types/express.d.ts" />
import { NextFunction, Request, Response, Router } from 'express';
import { z } from 'zod';
import { authenticate } from '../middleware/auth';
import { requireRole } from '../middleware/authorize';
import { ConsentService } from '../services/consentService';

const router = Router();
const consentService = new ConsentService();

const grantSchema = z.object({
  providerId: z.string().min(3).max(128),
  scope: z.string().min(3).max(64),
  expirationTimestamp: z.string().optional()
});

const revokeSchema = z.object({
  providerId: z.string().min(3).max(128),
  scope: z.string().min(3).max(64)
});

const querySchema = z.object({
  patientId: z.string().min(3).max(128),
  providerId: z.string().min(3).max(128),
  scope: z.string().min(3).max(64)
});

/**
 * POST /api/v1/consent/grant
 * Patient grants consent to a provider on Hyperledger Fabric.
 * Gated by configuration until Phase 3 migration.
 */
router.post(
  '/grant',
  authenticate(),
  requireRole('patient'),
  async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const parseResult = grantSchema.safeParse(req.body);
      if (!parseResult.success) {
        res.status(400).json({
          success: false,
          error: {
            code: 'BAD_REQUEST',
            message: 'Invalid request payload',
            details: parseResult.error.format()
          }
        });
        return;
      }

      const { providerId, scope, expirationTimestamp } = parseResult.data;
      const result = await consentService.grantConsent(
        req.user!,
        providerId,
        scope,
        expirationTimestamp || 'NEVER',
        req.idempotencyKey
      );

      res.status(200).json({
        success: true,
        data: result
      });
    } catch (err) {
      next(err);
    }
  }
);

/**
 * POST /api/v1/consent/revoke
 * Patient revokes previously granted consent on Hyperledger Fabric.
 * Gated by configuration until Phase 3 migration.
 */
router.post(
  '/revoke',
  authenticate(),
  requireRole('patient'),
  async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const parseResult = revokeSchema.safeParse(req.body);
      if (!parseResult.success) {
        res.status(400).json({
          success: false,
          error: {
            code: 'BAD_REQUEST',
            message: 'Invalid request payload',
            details: parseResult.error.format()
          }
        });
        return;
      }

      const { providerId, scope } = parseResult.data;
      const result = await consentService.revokeConsent(
        req.user!,
        providerId,
        scope,
        req.idempotencyKey
      );

      res.status(200).json({
        success: true,
        data: result
      });
    } catch (err) {
      next(err);
    }
  }
);

/**
 * GET /api/v1/consent/check
 * Evaluates active consent status on the Fabric ledger.
 */
router.get(
  '/check',
  authenticate(),
  async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const parseResult = querySchema.safeParse(req.query);
      if (!parseResult.success) {
        res.status(400).json({
          success: false,
          error: {
            code: 'BAD_REQUEST',
            message: 'Invalid query parameters: patientId, providerId, and scope are required.',
            details: parseResult.error.format()
          }
        });
        return;
      }

      const { patientId, providerId, scope } = parseResult.data;
      const result = await consentService.checkConsent(req.user!, patientId, providerId, scope);

      res.status(200).json({
        success: true,
        data: result
      });
    } catch (err) {
      next(err);
    }
  }
);

/**
 * GET /api/v1/consent/history
 * Evaluates full consent audit lifecycle history from the Fabric ledger.
 */
router.get(
  '/history',
  authenticate(),
  async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const parseResult = querySchema.safeParse(req.query);
      if (!parseResult.success) {
        res.status(400).json({
          success: false,
          error: {
            code: 'BAD_REQUEST',
            message: 'Invalid query parameters: patientId, providerId, and scope are required.',
            details: parseResult.error.format()
          }
        });
        return;
      }

      const { patientId, providerId, scope } = parseResult.data;
      const history = await consentService.getConsentHistory(req.user!, patientId, providerId, scope);

      res.status(200).json({
        success: true,
        data: { history }
      });
    } catch (err) {
      next(err);
    }
  }
);

export default router;
