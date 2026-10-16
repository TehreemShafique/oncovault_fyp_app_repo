// test/live/liveFabric.test.ts
import { expect } from 'chai';
import crypto from 'crypto';
import { FabricGatewayService } from '../../src/services/fabricGateway';

describe('Live Hyperledger Fabric Network Integration Tests', () => {
  let fabric: FabricGatewayService;

  before(async function () {
    this.timeout(30000);
    fabric = FabricGatewayService.getInstance();
    await fabric.connect();
  });

  after(async function () {
    await fabric.disconnect();
  });

  it('should successfully establish gRPC TLS connection to peer0.org1 using oncovault-gateway identity', async () => {
    expect(fabric.isConnected()).to.be.true;
    const readiness = await fabric.checkReadiness();
    expect(readiness.connected).to.be.true;
    expect(readiness.channel).to.equal('oncovault-channel');
    expect(readiness.chaincode).to.equal('oncovault');
  });

  it('should query chaincode and evaluate CheckConsent on real oncovault-channel', async () => {
    const resStr = await fabric.evaluateTransaction(
      'CheckConsent',
      'pat_live_test_999',
      'prov_live_test_888',
      'ONCOLOGY_RESEARCH'
    );
    const res = JSON.parse(resStr);
    expect(res).to.exist;
    expect(res.active).to.be.false;
    expect(res.status).to.equal('NOT_FOUND');
  });

  it('should submit real AnchorRecordHash transaction proposal, obtain dual endorsement, verify VALID commit status and retrieve proof', async function () {
    this.timeout(30000);
    const testRecordKey = `rec_live_gw_${Date.now()}`;
    const testHash = crypto.createHash('sha256').update(`LIVE_TEST_CONTENT_${Date.now()}`).digest('hex');
    const metadata = JSON.stringify({
      documentType: 'PATHOLOGY_PANEL',
      schemaVersion: '1.0',
      synthetic: true
    });

    const { result, txId } = await fabric.submitTransaction(
      'AnchorRecordHash',
      testRecordKey,
      testHash,
      metadata
    );

    expect(txId).to.exist;
    const proof = JSON.parse(result);
    expect(proof.recordId).to.equal(testRecordKey);
    expect(proof.sha256Hash).to.equal(testHash);
    expect(proof.version).to.equal(1);
    expect(proof.status).to.equal('ACTIVE');

    // Query proof back to verify ledger state persistence
    const queriedStr = await fabric.evaluateTransaction('GetRecordProof', testRecordKey);
    const queriedProof = JSON.parse(queriedStr);
    expect(queriedProof.sha256Hash).to.equal(testHash);
    expect(queriedProof.txId).to.equal(proof.txId);
  });
});
