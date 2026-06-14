import { randomUUID } from "node:crypto";
import http from "node:http";
import { FakeProvider } from "./providers/fakeProvider.mjs";
import { MemoryJobStore } from "./jobs/memoryJobStore.mjs";
import { validateGenerationRequest } from "./safety/moderation.mjs";

const DEFAULT_PORT = Number(process.env.PORT ?? 8787);

export function createPromptGIFServer({
  provider = new FakeProvider(),
  jobStore = new MemoryJobStore(),
  publicBaseURL = process.env.PUBLIC_BASE_URL
} = {}) {
  return http.createServer(async (request, response) => {
    try {
      await routeRequest({ request, response, provider, jobStore, publicBaseURL });
    } catch (error) {
      const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
      writeJSON(response, statusCode, {
        error: statusCode >= 500 ? "internal_error" : "invalid_request",
        message: error instanceof Error ? error.message : "Unknown server error."
      });
    }
  });
}

async function routeRequest({ request, response, provider, jobStore, publicBaseURL }) {
  const requestURL = new URL(request.url ?? "/", requestBaseURL(request, publicBaseURL));

  if (request.method === "GET" && requestURL.pathname === "/healthz") {
    writeJSON(response, 200, {
      ok: true,
      provider: provider.name,
      mode: "demo"
    });
    return;
  }

  if (request.method === "POST" && requestURL.pathname === "/v1/generations") {
    const body = await readJSONBody(request, 9_000_000);
    const validation = validateGenerationRequest(body);
    if (!validation.ok) {
      writeJSON(response, validation.status, { error: "invalid_request", message: validation.message });
      return;
    }

    const providerJob = await provider.submitGeneration(body);
    const id = randomUUID();
    jobStore.create({
      id,
      request: body,
      provider: providerJob.provider,
      providerJobId: providerJob.providerJobId
    });

    writeJSON(response, 202, {
      jobId: id,
      status: "queued",
      statusUrl: `${requestBaseURL(request, publicBaseURL)}/v1/generations/${id}`
    });
    return;
  }

  const jobMatch = requestURL.pathname.match(/^\/v1\/generations\/([^/]+)$/);
  if (request.method === "GET" && jobMatch) {
    const job = jobStore.get(jobMatch[1]);
    if (!job) {
      writeJSON(response, 404, { error: "not_found", message: "Generation job was not found." });
      return;
    }

    const status = jobStore.statusFor(job);
    writeJSON(response, 200, {
      jobId: job.id,
      status,
      downloadUrl: status === "succeeded"
        ? `${requestBaseURL(request, publicBaseURL)}/v1/generations/${job.id}/result`
        : null,
      message: status === "failed" ? job.failedMessage : null
    });
    return;
  }

  const resultMatch = requestURL.pathname.match(/^\/v1\/generations\/([^/]+)\/result$/);
  if (request.method === "GET" && resultMatch) {
    const job = jobStore.get(resultMatch[1]);
    if (!job) {
      writeJSON(response, 404, { error: "not_found", message: "Generation job was not found." });
      return;
    }

    const status = jobStore.statusFor(job);
    if (status !== "succeeded") {
      writeJSON(response, 409, { error: "not_ready", message: "Generation result is not ready." });
      return;
    }

    const result = await provider.getResult(job.request);
    writeJSON(response, 200, result, "application/vnd.promptgif.frame-sequence+json");
    return;
  }

  writeJSON(response, 404, { error: "not_found", message: "Route was not found." });
}

function requestBaseURL(request, publicBaseURL) {
  if (publicBaseURL) {
    return publicBaseURL.replace(/\/$/, "");
  }

  const host = request.headers.host ?? `127.0.0.1:${DEFAULT_PORT}`;
  return `http://${host}`;
}

function readJSONBody(request, maxBytes) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];

    request.on("data", (chunk) => {
      size += chunk.length;
      if (size > maxBytes) {
        reject(Object.assign(new Error("Request body is too large."), { statusCode: 413 }));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });

    request.on("end", () => {
      try {
        const text = Buffer.concat(chunks).toString("utf8");
        resolve(text.length ? JSON.parse(text) : {});
      } catch {
        reject(Object.assign(new Error("Request body must be valid JSON."), { statusCode: 400 }));
      }
    });

    request.on("error", reject);
  });
}

function writeJSON(response, statusCode, body, contentType = "application/json") {
  response.writeHead(statusCode, {
    "content-type": contentType,
    "cache-control": "no-store"
  });
  response.end(JSON.stringify(body));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = createPromptGIFServer();
  server.listen(DEFAULT_PORT, () => {
    console.log(`PromptGIF backend listening on http://127.0.0.1:${DEFAULT_PORT}`);
  });
}
