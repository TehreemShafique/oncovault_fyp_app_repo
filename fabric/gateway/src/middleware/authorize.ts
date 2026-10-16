/// <reference path="../types/express.d.ts" />
import { NextFunction, Request, Response } from 'express';
import { UserRole } from '../types';

/**
 * Ensures the authenticated user possesses one of the allowed authoritative roles.
 */
export function requireRole(...allowedRoles: UserRole[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({
        success: false,
        error: {
          code: 'UNAUTHENTICATED',
          message: 'Authentication required.'
        }
      });
      return;
    }

    if (!allowedRoles.includes(req.user.role)) {
      res.status(403).json({
        success: false,
        error: {
          code: 'FORBIDDEN',
          message: `Access Denied: Role '${req.user.role}' is not authorized for this operation. Required: ${allowedRoles.join(', ')}.`
        }
      });
      return;
    }

    next();
  };
}

/**
 * Prevents IDOR (Insecure Direct Object Reference) for patient-specific requests.
 */
export function assertPatientOwnership(req: Request, res: Response, next: NextFunction): void {
  if (!req.user) {
    res.status(401).json({ success: false, error: { code: 'UNAUTHENTICATED', message: 'Authentication required.' } });
    return;
  }

  // Admins can bypass direct ownership
  if (req.user.role === 'admin') {
    return next();
  }

  const targetPatientId = req.params.patientId || req.body.patientId;
  if (req.user.role === 'patient' && targetPatientId && targetPatientId !== req.user.uid) {
    res.status(403).json({
      success: false,
      error: {
        code: 'FORBIDDEN',
        message: 'Access Denied: Patients may only perform operations on their own profile and records.'
      }
    });
    return;
  }

  next();
}
