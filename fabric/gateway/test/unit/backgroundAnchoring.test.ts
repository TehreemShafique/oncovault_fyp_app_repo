import { expect } from 'chai';
import sinon from 'sinon';
import fs from 'fs';
import path from 'path';
import vm from 'vm';
import ts from 'typescript';
import { bootstrap } from '../../src/index';
import { app } from '../../src/app';
import { config } from '../../src/config/env';
import { FabricGatewayService } from '../../src/services/fabricGateway';
import { ReconciliationWorker } from '../../src/services/reconciliationWorker';

describe('Background anchoring configuration (isolated environment)', () => {
  for (const [value, expected] of [[undefined, true], ['true', true], ['false', false]] as const) {
    it(`uses ${expected} when ENABLE_BACKGROUND_ANCHORING is ${String(value)}`, () => {
      const filename = path.resolve(__dirname, '../../src/config/env.ts');
      const source = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
        compilerOptions: { module: ts.ModuleKind.CommonJS, esModuleInterop: true }
      }).outputText;
      const exports: any = {};
      // No dotenv file, real credentials or shared process environment in this VM.
      vm.runInNewContext(source, {
        exports,
        process: { env: value === undefined ? {} : { ENABLE_BACKGROUND_ANCHORING: value } },
        require: (name: string) => {
          if (name === 'dotenv') return { config: () => undefined };
          if (name === 'path') return path;
          throw new Error(`Unexpected dependency: ${name}`);
        }
      });
      expect(exports.config.enableBackgroundAnchoring).to.equal(expected);
      expect(exports.config.enableLiveConsentMutations).to.equal(false);
    });
  }
});

describe('Gateway background anchoring startup (mock Fabric and API)', () => {
  let originalFlag: boolean;
  let clock: sinon.SinonFakeTimers;
  let worker: ReconciliationWorker;
  let connect: sinon.SinonStub;
  let submit: sinon.SinonStub;
  let notes: sinon.SinonStub;
  let treatments: sinon.SinonStub;
  let listen: sinon.SinonStub;

  beforeEach(() => {
    originalFlag = config.enableBackgroundAnchoring;
    clock = sinon.useFakeTimers();
    connect = sinon.stub().resolves();
    submit = sinon.stub().rejects(new Error('No Fabric submission allowed in startup tests'));
    sinon.stub(FabricGatewayService, 'getInstance').returns({
      connect, submitTransaction: submit, submitConsentTransaction: submit
    } as any);
    worker = new ReconciliationWorker();
    sinon.stub(ReconciliationWorker, 'getInstance').returns(worker);
    notes = sinon.stub(worker, 'reconcilePendingClinicalNotes').resolves({ processed: 0, committed: 0, failed: 0 });
    treatments = sinon.stub(worker, 'reconcilePendingTreatmentOperations').resolves({ processed: 0, committed: 0, failed: 0 });
    listen = sinon.stub(app, 'listen').returns({ close: sinon.stub() } as any);
    sinon.stub(process, 'on');
    sinon.stub(console, 'info');
    sinon.stub(console, 'warn');
  });

  afterEach(() => {
    worker.stopPeriodicSweeper();
    config.enableBackgroundAnchoring = originalFlag;
    clock.restore();
    sinon.restore();
  });

  it('disabled startup keeps Fabric and the API available without either periodic routine or submissions', async () => {
    config.enableBackgroundAnchoring = false;
    const start = sinon.spy(worker, 'startPeriodicSweeper');
    await bootstrap();
    await clock.tickAsync(60000);
    expect(connect.calledOnce).to.equal(true);
    expect(listen.calledOnceWith(config.port, config.host)).to.equal(true);
    expect(start.called).to.equal(false);
    expect(notes.called).to.equal(false);
    expect(treatments.called).to.equal(false);
    expect(submit.called).to.equal(false);
  });

  it('enabled startup preserves both routines on the existing 15-second schedule', async () => {
    config.enableBackgroundAnchoring = true;
    await bootstrap();
    await clock.tickAsync(14999);
    expect(notes.called).to.equal(false);
    await clock.tickAsync(1);
    expect(notes.calledOnce).to.equal(true);
    expect(treatments.calledOnce).to.equal(true);
    expect(submit.called).to.equal(false);
  });

  it('disabled startup still exposes the API when the initial Fabric connection fails', async () => {
    config.enableBackgroundAnchoring = false;
    connect.rejects(new Error('Mock connection unavailable'));
    await bootstrap();
    await clock.tickAsync(30000);
    expect(listen.calledOnce).to.equal(true);
    expect(notes.called || treatments.called || submit.called).to.equal(false);
  });
});
