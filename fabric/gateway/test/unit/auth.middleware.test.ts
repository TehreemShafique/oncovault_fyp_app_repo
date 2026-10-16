// test/unit/auth.middleware.test.ts
import { expect } from 'chai';
import express from 'express';
import sinon from 'sinon';
import request from 'supertest';
import { authenticate } from '../../src/middleware/auth';

describe('Auth Middleware Unit Tests', () => {
  let app: express.Application;
  let mockFirebaseAdmin: any;

  beforeEach(() => {
    mockFirebaseAdmin = {
      verifyIdToken: sinon.stub(),
      getAuthoritativeUser: sinon.stub()
    };

    app = express();
    app.use(express.json());
    app.get('/protected', authenticate(mockFirebaseAdmin), (req, res) => {
      res.status(200).json({ success: true, user: (req as any).user });
    });
  });

  it('should reject request missing Authorization header with 401', async () => {
    const res = await request(app).get('/protected');
    expect(res.status).to.equal(401);
    expect(res.body.success).to.be.false;
    expect(res.body.error.code).to.equal('UNAUTHENTICATED');
    expect(res.body.error.message).to.include('Missing or malformed Authorization header');
  });

  it('should reject request with non-Bearer Authorization header with 401', async () => {
    const res = await request(app)
      .get('/protected')
      .set('Authorization', 'Basic dXNlcjpwYXNz');
    expect(res.status).to.equal(401);
    expect(res.body.error.code).to.equal('UNAUTHENTICATED');
  });

  it('should reject invalid or expired Firebase ID token with 401', async () => {
    mockFirebaseAdmin.verifyIdToken.rejects(new Error('Firebase ID token has expired.'));

    const res = await request(app)
      .get('/protected')
      .set('Authorization', 'Bearer expired-or-invalid-token');

    expect(res.status).to.equal(401);
    expect(res.body.error.code).to.equal('UNAUTHENTICATED');
    expect(res.body.error.message).to.include('Firebase ID token has expired');
  });

  it('should reject revoked Firebase ID token with 401', async () => {
    mockFirebaseAdmin.verifyIdToken.rejects(new Error('Firebase ID token has been revoked.'));

    const res = await request(app)
      .get('/protected')
      .set('Authorization', 'Bearer revoked-token');

    expect(res.status).to.equal(401);
    expect(res.body.error.code).to.equal('UNAUTHENTICATED');
    expect(res.body.error.message).to.include('revoked');
  });

  it('should load authoritative role from Firestore and prevent role spoofing', async () => {
    mockFirebaseAdmin.verifyIdToken.resolves({
      uid: 'user-spoof-1',
      email: 'patient@example.com',
      role: 'admin' // Spoofed token claim
    });

    mockFirebaseAdmin.getAuthoritativeUser.resolves({
      uid: 'user-spoof-1',
      email: 'patient@example.com',
      role: 'patient', // Authoritative role in Firestore
      name: 'John Doe'
    });

    const res = await request(app)
      .get('/protected')
      .set('Authorization', 'Bearer valid-token-with-spoofed-role');

    expect(res.status).to.equal(200);
    expect(res.body.user.role).to.equal('patient'); // Enforced authoritative role!
  });
});
