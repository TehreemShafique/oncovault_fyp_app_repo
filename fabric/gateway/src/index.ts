// src/index.ts
import { app } from './app';
import { config } from './config/env';
import { FabricGatewayService } from './services/fabricGateway';

async function bootstrap(): Promise<void> {
  const { host, port } = config;

  // Enforce loopback binding check
  if (host !== '127.0.0.1' && host !== 'localhost') {
    console.warn(`[SECURITY WARNING] Host is set to '${host}'. Gateway must default to loopback (127.0.0.1) for secure token handling.`);
  }

  // Attempt initial Fabric connection
  try {
    const fabric = FabricGatewayService.getInstance();
    await fabric.connect();
    console.info(`[+] Connected to Hyperledger Fabric: Channel '${config.fabric.channelName}', Chaincode '${config.fabric.chaincodeName}' via '${config.fabric.peerEndpoint}'`);
  } catch (err: any) {
    console.warn(`[!] Initial Fabric Gateway connection deferred: ${err.message}`);
  }

  const server = app.listen(port, host, () => {
    console.info(`========================================================`);
    console.info(`OncoVault Trusted Fabric Gateway listening on http://${host}:${port}`);
    console.info(`Environment: ${config.nodeEnv}`);
    console.info(`Live Consent Mutations Enabled: ${config.enableLiveConsentMutations}`);
    console.info(`========================================================`);
  });

  const shutdown = async (signal: string) => {
    console.info(`\nReceived ${signal}. Shutting down gracefully...`);
    server.close(async () => {
      try {
        await FabricGatewayService.getInstance().disconnect();
        console.info('[+] Fabric Gateway disconnected.');
      } catch (err) {
        console.error('Error disconnecting Fabric Gateway:', err);
      }
      process.exit(0);
    });
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

if (require.main === module) {
  bootstrap().catch((err) => {
    console.error('Fatal startup error:', err);
    process.exit(1);
  });
}
