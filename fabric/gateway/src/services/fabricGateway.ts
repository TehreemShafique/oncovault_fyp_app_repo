// src/services/fabricGateway.ts
import * as grpc from '@grpc/grpc-js';
import { connect, Contract, Gateway, Identity, Signer, signers } from '@hyperledger/fabric-gateway';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import { config } from '../config/env';

export class FabricGatewayService {
  private static instance: FabricGatewayService | null = null;
  private gateway: Gateway | null = null;
  private client: grpc.Client | null = null;
  private contract: Contract | null = null;
  private connected: boolean = false;

  private constructor() {}

  public static getInstance(): FabricGatewayService {
    if (!FabricGatewayService.instance) {
      FabricGatewayService.instance = new FabricGatewayService();
    }
    return FabricGatewayService.instance;
  }

  public async connect(): Promise<void> {
    if (this.connected && this.contract) {
      return;
    }

    try {
      const {
        tlsCertPath,
        gatewayCertPath,
        gatewayKeyDir,
        peerEndpoint,
        peerHostOverride,
        mspId,
        channelName,
        chaincodeName
      } = config.fabric;

      // 1. Verify existence of required credential files
      if (!fs.existsSync(tlsCertPath)) {
        throw new Error(`Fabric TLS CA certificate not found at: ${tlsCertPath}`);
      }
      if (!fs.existsSync(gatewayCertPath)) {
        throw new Error(`Fabric Gateway client certificate not found at: ${gatewayCertPath}`);
      }
      if (!fs.existsSync(gatewayKeyDir)) {
        throw new Error(`Fabric Gateway private key directory not found at: ${gatewayKeyDir}`);
      }

      // 2. Discover private key in keystore directory
      const keyFiles = fs.readdirSync(gatewayKeyDir).filter(f => f.endsWith('_sk') || f.endsWith('.pem') || f.endsWith('.key'));
      if (keyFiles.length === 0) {
        throw new Error(`No private key file found in Fabric keystore directory: ${gatewayKeyDir}`);
      }
      const keyPath = path.join(gatewayKeyDir, keyFiles[0]);

      // 3. Read certificates and keys with safe in-memory handling
      const tlsRootCert = fs.readFileSync(tlsCertPath);
      const certificate = fs.readFileSync(gatewayCertPath);
      const privateKeyPem = fs.readFileSync(keyPath);

      // 4. Construct Fabric Identity and Signer
      const identity: Identity = {
        mspId,
        credentials: certificate
      };
      const privateKey = crypto.createPrivateKey(privateKeyPem);
      const signer: Signer = signers.newPrivateKeySigner(privateKey);

      // 5. Establish TLS gRPC Connection
      const tlsCredentials = grpc.credentials.createSsl(tlsRootCert);
      this.client = new grpc.Client(peerEndpoint, tlsCredentials, {
        'grpc.ssl_target_name_override': peerHostOverride
      });

      // 6. Connect to Fabric Gateway
      this.gateway = connect({
        client: this.client,
        identity,
        signer,
        evaluateOptions: () => ({ deadline: Date.now() + 5000 }),
        endorseOptions: () => ({ deadline: Date.now() + 15000 }),
        submitOptions: () => ({ deadline: Date.now() + 15000 }),
        commitStatusOptions: () => ({ deadline: Date.now() + 60000 })
      });

      const network = this.gateway.getNetwork(channelName);
      this.contract = network.getContract(chaincodeName);
      this.connected = true;
    } catch (err: any) {
      this.connected = false;
      this.gateway = null;
      this.contract = null;
      throw new Error(`Failed to initialize Fabric Gateway connection: ${err.message}`);
    }
  }

  public getContract(): Contract {
    if (!this.contract || !this.connected) {
      throw new Error('Fabric Gateway is not connected. Call connect() first.');
    }
    return this.contract;
  }

  /**
   * Evaluates a transaction query on the ledger (read-only, does not commit).
   */
  public async evaluateTransaction(name: string, ...args: string[]): Promise<string> {
    const contract = this.getContract();
    const resultBytes = await contract.evaluateTransaction(name, ...args);
    return Buffer.from(resultBytes).toString('utf8');
  }

  /**
   * Submits a transaction proposal, obtains endorsements, submits to orderer,
   * and verifies commit status across endorsing peers.
   */
  public async submitTransaction(name: string, ...args: string[]): Promise<{ result: string; txId?: string }> {
    const contract = this.getContract();
    // Use contract.newProposal to capture the proposed transaction ID
    const proposal = contract.newProposal(name, { arguments: args });
    const txId = proposal.getTransactionId();
    const transaction = await proposal.endorse();
    const commit = await transaction.submit();
    const status = await commit.getStatus();

    if (!status.successful) {
      throw new Error(`Fabric transaction [${txId}] commit failed with status code: ${status.code}`);
    }

    const result = Buffer.from(transaction.getResult()).toString('utf8');
    return { result, txId };
  }

  public isConnected(): boolean {
    return this.connected;
  }

  public async disconnect(): Promise<void> {
    if (this.gateway) {
      this.gateway.close();
      this.gateway = null;
    }
    if (this.client) {
      this.client.close();
      this.client = null;
    }
    this.contract = null;
    this.connected = false;
  }

  public async checkReadiness(): Promise<{ connected: boolean; channel: string; chaincode: string; error?: string }> {
    try {
      if (!this.connected) {
        await this.connect();
      }
      // Query chaincode contract ping or metadata check
      return {
        connected: this.connected,
        channel: config.fabric.channelName,
        chaincode: config.fabric.chaincodeName
      };
    } catch (err: any) {
      return {
        connected: false,
        channel: config.fabric.channelName,
        chaincode: config.fabric.chaincodeName,
        error: err.message
      };
    }
  }
}
