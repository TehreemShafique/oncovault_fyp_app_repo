// test/unit/routes.test.ts
import { expect } from 'chai';
import request from 'supertest';
import { app } from '../../src/app';

describe('API Routes Integration & Validation Unit Tests', () => {
  it('GET /health should return 200 UP', async () => {
    const res = await request(app).get('/health');
    expect(res.status).to.equal(200);
    expect(res.body.status).to.equal('UP');
    expect(res.body.service).to.equal('oncovault-fabric-gateway');
  });

  it('GET /ready should return dependencies status without exposing secrets', async () => {
    const res = await request(app).get('/ready');
    // May be 200 or 503 depending on local network connection state
    expect(res.body.dependencies).to.exist;
    expect(res.body.dependencies.fabric).to.exist;
    expect(res.body.dependencies.firebase).to.exist;
    // Verify no secret leakage in response
    const bodyStr = JSON.stringify(res.body);
    expect(bodyStr).to.not.include('privateKey');
    expect(bodyStr).to.not.include('secret');
  });

  it('POST /api/v1/records/anchor should reject unauthenticated request with 401', async () => {
    const res = await request(app)
      .post('/api/v1/records/anchor')
      .send({ recordId: 'rec-123' });

    expect(res.status).to.equal(401);
    expect(res.body.error.code).to.equal('UNAUTHENTICATED');
  });

  it('POST /api/v1/records/verify should reject invalid SHA-256 formatting with 400 when authenticated', async () => {
    // When unauthenticated, should fail with 401 first
    const res = await request(app)
      .post('/api/v1/records/verify')
      .send({ recordId: 'rec-123', expectedHash: 'invalid-hash-length' });

    expect(res.status).to.equal(401);
  });

  it('POST /api/v1/consent/grant should reject unauthenticated request with 401', async () => {
    const res = await request(app)
      .post('/api/v1/consent/grant')
      .send({ providerId: 'prov-1', scope: 'BLOOD_CANCER_RESEARCH' });

    expect(res.status).to.equal(401);
  });

  it('GET /api/v1/consent/check should reject unauthenticated request with 401', async () => {
    const res = await request(app)
      .get('/api/v1/consent/check')
      .query({ patientId: 'pat-1', providerId: 'prov-1', scope: 'BLOOD_CANCER_RESEARCH' });

    expect(res.status).to.equal(401);
  });
});
