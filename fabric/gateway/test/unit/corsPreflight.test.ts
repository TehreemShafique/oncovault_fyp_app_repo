// test/unit/corsPreflight.test.ts
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';

import { expect } from 'chai';
import request from 'supertest';
import { app } from '../../src/app';

describe('CORS Preflight & Header Authorization Regression Tests', function () {
  this.timeout(10000);

  const CHROME_ORIGIN = 'http://localhost:3000';

  it('1. should respond with 204 to OPTIONS preflight for /api/v1/records/anchor with x-idempotency-key', async () => {
    const res = await request(app)
      .options('/api/v1/records/anchor')
      .set('Origin', CHROME_ORIGIN)
      .set('Access-Control-Request-Method', 'POST')
      .set('Access-Control-Request-Headers', 'authorization,content-type,x-idempotency-key');

    expect(res.status).to.equal(204);

    const allowOrigin = res.headers['access-control-allow-origin'];
    expect(allowOrigin).to.satisfy((val: string) => val === '*' || val === CHROME_ORIGIN);

    const allowMethods = res.headers['access-control-allow-methods'];
    expect(allowMethods).to.be.a('string');
    expect(allowMethods).to.include('POST');
    expect(allowMethods).to.include('OPTIONS');

    const allowHeaders = (res.headers['access-control-allow-headers'] || '').toLowerCase();
    expect(allowHeaders).to.include('x-idempotency-key');
    expect(allowHeaders).to.include('authorization');
    expect(allowHeaders).to.include('content-type');
  });

  it('2. should permit capitalized X-Idempotency-Key and standard headers in preflight', async () => {
    const res = await request(app)
      .options('/api/v1/records/anchor')
      .set('Origin', CHROME_ORIGIN)
      .set('Access-Control-Request-Method', 'POST')
      .set('Access-Control-Request-Headers', 'Authorization, Content-Type, X-Idempotency-Key');

    expect(res.status).to.equal(204);

    const allowHeaders = (res.headers['access-control-allow-headers'] || '').toLowerCase();
    expect(allowHeaders).to.include('x-idempotency-key');
    expect(allowHeaders).to.include('authorization');
    expect(allowHeaders).to.include('content-type');
  });

  it('3. should handle OPTIONS preflight without triggering 401 unauthenticated error', async () => {
    // Verifies preflight is evaluated before auth middleware rejects the request
    const res = await request(app)
      .options('/api/v1/records/anchor')
      .set('Origin', CHROME_ORIGIN)
      .set('Access-Control-Request-Method', 'POST')
      .set('Access-Control-Request-Headers', 'authorization,content-type,x-idempotency-key');

    expect(res.status).to.equal(204);
    expect(res.body).to.deep.equal({});
  });

  it('4. should keep authenticated anchoring endpoint protected against unauthenticated POST', async () => {
    // Ensures CORS preflight allowance did not accidentally open up the endpoint without auth
    const res = await request(app)
      .post('/api/v1/records/anchor')
      .set('Origin', CHROME_ORIGIN)
      .set('x-idempotency-key', 'test-key-123')
      .send({ recordId: 'test-rec-001' });

    expect(res.status).to.equal(401);
    expect(res.body.error.code).to.equal('UNAUTHENTICATED');
  });
});
