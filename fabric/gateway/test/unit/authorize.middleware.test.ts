// test/unit/authorize.middleware.test.ts
import { expect } from 'chai';
import express from 'express';
import request from 'supertest';
import { assertPatientOwnership, requireRole } from '../../src/middleware/authorize';

describe('Authorize Middleware Unit Tests (Anti-IDOR & Role Gates)', () => {
  let app: express.Application;

  beforeEach(() => {
    app = express();
    app.use(express.json());

    // Route requiring clinician role
    app.post('/clinician-only', (req, res, next) => {
      // simulate authenticated user attached by auth middleware
      (req as any).user = req.body._simulatedUser;
      next();
    }, requireRole('doctor', 'nurse'), (req, res) => {
      res.status(200).json({ success: true, message: 'Welcome Clinician' });
    });

    // Route enforcing patient ownership
    app.get('/patient/:patientId/data', (req, res, next) => {
      (req as any).user = (req.query as any)._simulatedUser ? JSON.parse((req.query as any)._simulatedUser) : undefined;
      next();
    }, assertPatientOwnership, (req, res) => {
      res.status(200).json({ success: true, data: `Data for ${req.params.patientId}` });
    });
  });

  it('should reject patient attempting to access doctor-only endpoint with 403', async () => {
    const res = await request(app)
      .post('/clinician-only')
      .send({
        _simulatedUser: { uid: 'pat-1', role: 'patient' }
      });

    expect(res.status).to.equal(403);
    expect(res.body.error.code).to.equal('FORBIDDEN');
    expect(res.body.error.message).to.include("Role 'patient' is not authorized");
  });

  it('should permit doctor accessing doctor-only endpoint', async () => {
    const res = await request(app)
      .post('/clinician-only')
      .send({
        _simulatedUser: { uid: 'doc-1', role: 'doctor' }
      });

    expect(res.status).to.equal(200);
    expect(res.body.success).to.be.true;
  });

  it('should prevent cross-patient IDOR when Patient A attempts to access Patient B data with 403', async () => {
    const simulatedUser = JSON.stringify({ uid: 'patient-A', role: 'patient' });

    const res = await request(app)
      .get('/patient/patient-B/data')
      .query({ _simulatedUser: simulatedUser });

    expect(res.status).to.equal(403);
    expect(res.body.error.code).to.equal('FORBIDDEN');
    expect(res.body.error.message).to.include('Patients may only perform operations on their own');
  });

  it('should permit Patient A accessing their own data', async () => {
    const simulatedUser = JSON.stringify({ uid: 'patient-A', role: 'patient' });

    const res = await request(app)
      .get('/patient/patient-A/data')
      .query({ _simulatedUser: simulatedUser });

    expect(res.status).to.equal(200);
    expect(res.body.success).to.be.true;
  });
});
