export class MemoryJobStore {
  constructor() {
    this.jobs = new Map();
  }

  create({ id, request, provider, providerJobId, createdAt = Date.now() }) {
    const job = {
      id,
      request,
      provider,
      providerJobId,
      createdAt,
      failedMessage: null
    };
    this.jobs.set(id, job);
    return job;
  }

  get(id) {
    return this.jobs.get(id) ?? null;
  }

  statusFor(job) {
    if (job.failedMessage) {
      return "failed";
    }

    const ageMs = Date.now() - job.createdAt;
    if (ageMs < 300) {
      return "queued";
    }
    if (ageMs < 900) {
      return "running";
    }
    return "succeeded";
  }
}
