// src/routes/health.ts
import { Request, Response, Router } from 'express';
import { FabricGatewayService } from '../services/fabricGateway';
import { FirebaseAdminService } from '../services/firebaseAdmin';

const router = Router();

/**
 * Basic liveness check.
 */
router.get('/health', (req: Request, res: Response) => {
  res.status(200).json({
    status: 'UP',
    timestamp: new Date().toISOString(),
    service: 'oncovault-fabric-gateway'
  });
});

/**
 * Readiness check inspecting dependency health without leaking secrets.
 */
router.get('/ready', async (req: Request, res: Response) => {
  const fabricService = FabricGatewayService.getInstance();
  const firebaseService = FirebaseAdminService.getInstance();

  const fabricStatus = await fabricService.checkReadiness();
  const firebaseStatus = firebaseService.checkReadiness();

  const isReady = fabricStatus.connected;
  const statusCode = isReady ? 200 : 503;

  res.status(statusCode).json({
    status: isReady ? 'READY' : 'DEGRADED',
    timestamp: new Date().toISOString(),
    dependencies: {
      fabric: {
        connected: fabricStatus.connected,
        channel: fabricStatus.channel,
        chaincode: fabricStatus.chaincode,
        error: fabricStatus.error
      },
      firebase: {
        configured: firebaseStatus.configured,
        projectId: firebaseStatus.projectId,
        error: firebaseStatus.error
      }
    }
  });
});

export default router;
