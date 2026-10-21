// src/app.ts
import express, { Application } from 'express';
import { errorHandler } from './middleware/errorHandler';
import { requestLogger } from './middleware/requestLogger';
import routes from './routes';

export function createApp(): Application {
  const app: Application = express();

  // Basic security and parsing middleware
  app.disable('x-powered-by');

  // CORS support for Flutter Web client access
  app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Private-Network', 'true');
    res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.header(
      'Access-Control-Allow-Headers',
      'Origin, X-Requested-With, Content-Type, Accept, Authorization, X-Request-ID, X-Idempotency-Key, x-idempotency-key, Idempotency-Key, idempotency-key'
    );
    if (req.method === 'OPTIONS') {
      res.sendStatus(204);
      return;
    }
    next();
  });

  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true }));

  // Sanitize request logging
  app.use(requestLogger);

  // Mount API routes
  app.use(routes);

  // Global error handler
  app.use(errorHandler);

  return app;
}

export const app = createApp();
