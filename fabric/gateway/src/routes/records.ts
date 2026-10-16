/// <reference path="../types/express.d.ts" />
import { NextFunction, Request, Response, Router } from 'express';
import { z } from 'zod';
import { authenticate } from '../middleware/auth';
import { RecordService } from '../services/recordService';

const router = Router();
const recordService = new RecordService();

const anchorSchema = z.object({
  recordId: z.string().min(3).max(128),
  patientId: z.string().optional(),
  metadata: z.record(z.any()).optional()
});

const verifySchema = z.object({
  recordId: z.string().min(3).max(128),
  patientId: z.string().optional(),
  expectedHash: z.string().regex(/^[a-fA-F0-9]{64}$/, 'Expected hash must be a 64-character SHA-256 hexadecimal string').optional()
});

/**
 * POST /api/v1/records/anchor
 * Anchors a verified medical record on the Hyperledger Fabric ledger.
 */
router.post('/anchor', authenticate(), async (req: Request, res: Response, next: NextFunction): Promise<void> => {
  try {
    const parseResult = anchorSchema.safeParse(req.body);
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

    const { recordId, patientId, metadata } = parseResult.data;
    const result = await recordService.anchorRecord(req.user!, recordId, metadata, req.idempotencyKey, patientId);

    res.status(200).json({
      success: true,
      data: result
    });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/v1/records/verify
 * Verifies record hash against immutable ledger proof.
 */
router.post('/verify', authenticate(), async (req: Request, res: Response, next: NextFunction): Promise<void> => {
  try {
    const parseResult = verifySchema.safeParse(req.body);
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

    const { recordId, patientId, expectedHash } = parseResult.data;
    const result = await recordService.verifyRecord(req.user!, recordId, expectedHash, patientId);

    res.status(200).json({
      success: true,
      data: result
    });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/v1/records/:recordId/proof
 * Retrieves current Fabric ledger proof for a medical record.
 */
router.get('/:recordId/proof', authenticate(), async (req: Request, res: Response, next: NextFunction): Promise<void> => {
  try {
    const { recordId } = req.params;
    const patientId = req.query.patientId as string | undefined;
    const proof = await recordService.getRecordProof(req.user!, recordId, patientId);

    res.status(200).json({
      success: true,
      data: { proof }
    });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/v1/records/:recordId/history
 * Retrieves full ledger audit history for a medical record.
 */
router.get('/:recordId/history', authenticate(), async (req: Request, res: Response, next: NextFunction): Promise<void> => {
  try {
    const { recordId } = req.params;
    const patientId = req.query.patientId as string | undefined;
    const history = await recordService.getRecordHistory(req.user!, recordId, patientId);

    res.status(200).json({
      success: true,
      data: { history }
    });
  } catch (err) {
    next(err);
  }
});

export default router;
