/** Isolated atomic persistence fake. No Firebase initialization or network access. */
export class MemoryFirestore {
  readonly documents = new Map<string, any>();
  failWrites: (path: string, value: any) => boolean = () => false;
  private queue: Promise<unknown> = Promise.resolve();
  private snapshot(path: string) {
    const value = this.documents.get(path);
    return { exists: value !== undefined, data: () => value === undefined ? undefined : structuredClone(value) };
  }
  collection(name: string): any {
    return { doc: (id: string) => {
      const path = `${name}/${id}`;
      return {
        path, get: async () => this.snapshot(path),
        set: async (value: any, options?: any) => {
          if (this.failWrites(path, value)) throw new Error('Fake persistence failure');
          this.documents.set(path, structuredClone(options?.merge ? { ...this.documents.get(path), ...value } : value));
        }
      };
    } };
  }
  async runTransaction<T>(callback: (transaction: any) => Promise<T>): Promise<T> {
    const run = this.queue.then(async () => {
      const writes: Array<{ ref: any; value: any; options: any }> = [];
      const result = await callback({
        get: async (ref: any) => this.snapshot(ref.path),
        set: (ref: any, value: any, options?: any) => { writes.push({ ref, value, options }); }
      });
      if (writes.some(write => this.failWrites(write.ref.path, write.value))) throw new Error('Fake persistence failure');
      for (const write of writes) {
        this.documents.set(write.ref.path, structuredClone(write.options?.merge
          ? { ...this.documents.get(write.ref.path), ...write.value } : write.value));
      }
      return result;
    });
    this.queue = run.catch(() => undefined);
    return run;
  }
}
