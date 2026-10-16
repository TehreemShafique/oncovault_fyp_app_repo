// src/routes/index.ts
import { Router } from 'express';
import consentRoutes from './consent';
import healthRoutes from './health';
import recordRoutes from './records';

const router = Router();

router.use('/', healthRoutes);
router.use('/api/v1/records', recordRoutes);
router.use('/api/v1/consent', consentRoutes);

export default router;
