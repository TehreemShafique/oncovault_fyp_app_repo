// src/config/env.ts
import dotenv from 'dotenv';
import path from 'path';

dotenv.config();

export interface AppConfig {
  host: string;
  port: number;
  nodeEnv: string;

  fabric: {
    channelName: string;
    chaincodeName: string;
    mspId: string;
    peerEndpoint: string;
    peerHostOverride: string;
    tlsCertPath: string;
    gatewayCertPath: string;
    gatewayKeyDir: string;
  };

  pseudonymHmacSecret: string;
  enableLiveConsentMutations: boolean;
  enableBackgroundAnchoring: boolean;

  firebase: {
    projectId: string;
    storageBucket: string;
    serviceAccountPath?: string;
  };
}

const DEFAULT_FABRIC_BASE = process.env.FABRIC_SAMPLES_PATH || '/home/oncovault/oncovault-fabric/fabric-samples/test-network';

export const config: AppConfig = {
  host: process.env.HOST || '127.0.0.1',
  port: parseInt(process.env.PORT || '5001', 10),
  nodeEnv: process.env.NODE_ENV || 'development',

  fabric: {
    channelName: process.env.FABRIC_CHANNEL_NAME || 'oncovault-channel',
    chaincodeName: process.env.FABRIC_CHAINCODE_NAME || 'oncovault',
    mspId: process.env.FABRIC_MSP_ID || 'Org1MSP',
    peerEndpoint: process.env.FABRIC_PEER_ENDPOINT || 'localhost:7051',
    peerHostOverride: process.env.FABRIC_PEER_HOST_OVERRIDE || 'peer0.org1.example.com',
    tlsCertPath: process.env.FABRIC_TLS_CERT_PATH || path.join(
      DEFAULT_FABRIC_BASE,
      'organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem'
    ),
    gatewayCertPath: process.env.FABRIC_GATEWAY_CERT_PATH || path.join(
      DEFAULT_FABRIC_BASE,
      'organizations/peerOrganizations/org1.example.com/users/oncovault-gateway@org1.example.com/msp/signcerts/cert.pem'
    ),
    gatewayKeyDir: process.env.FABRIC_GATEWAY_KEY_DIR || path.join(
      DEFAULT_FABRIC_BASE,
      'organizations/peerOrganizations/org1.example.com/users/oncovault-gateway@org1.example.com/msp/keystore'
    )
  },

  pseudonymHmacSecret: process.env.PSEUDONYM_HMAC_SECRET || 'oncovault_default_local_hmac_secret_for_domain_sep_32_bytes!',
  enableLiveConsentMutations: process.env.ENABLE_LIVE_CONSENT_MUTATIONS === 'true',
  enableBackgroundAnchoring: process.env.ENABLE_BACKGROUND_ANCHORING !== 'false',

  firebase: {
    projectId: process.env.FIREBASE_PROJECT_ID || 'oncovault-8cbbc',
    storageBucket: process.env.FIREBASE_STORAGE_BUCKET || 'oncovault-8cbbc.firebasestorage.app',
    serviceAccountPath: process.env.FIREBASE_SERVICE_ACCOUNT_PATH
  }
};
