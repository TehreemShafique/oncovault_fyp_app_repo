// src/app.ts
import express, { Application } from 'express';
import { errorHandler } from './middleware/errorHandler';
import { requestLogger } from './middleware/requestLogger';
import routes from './routes';

export function createApp(): Application {
  const app: Application = express();

  // Basic security and parsing middleware
  app.disable('x-powered-by');
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
