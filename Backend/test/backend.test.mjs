import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { createPromptGIFServer } from "../src/server.mjs";

let server;
let baseURL;

before(async () => {
  server = createPromptGIFServer({ publicBaseURL: "http://127.0.0.1:0" });
  await new Promise((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  baseURL = `http://127.0.0.1:${address.port}`;
});

after(async () => {
  server.closeAllConnections();
  await new Promise((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
});

test("health endpoint reports demo provider", async () => {
  const response = await fetch(`${baseURL}/healthz`);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.ok, true);
  assert.equal(body.mode, "demo");
});

test("generation lifecycle returns a fake frame sequence result", async () => {
  const createResponse = await fetch(`${baseURL}/v1/generations`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      id: "96DD3998-C2E1-4C39-B7B1-3559D0D271C8",
      mode: "text_to_gif",
      originalPrompt: "cat in sunglasses",
      cleanedPrompt: "cat in sunglasses",
      expandedPrompt: "Create a short looping animated scene. Prompt: cat in sunglasses. Do not render readable text.",
      negativePrompt: "readable text, captions, subtitles",
      caption: { mode: "none", text: null },
      sourceImage: null,
      options: {
        width: 480,
        height: 360,
        loopSeconds: 2.4,
        stylePreset: "expressive",
        motionIntensity: "medium"
      },
      clientTraceID: "test-trace"
    })
  });

  assert.equal(createResponse.status, 202);
  const created = await createResponse.json();
  assert.ok(created.jobId);
  assert.equal(created.status, "queued");

  await new Promise((resolve) => setTimeout(resolve, 950));

  const statusResponse = await fetch(`${baseURL}/v1/generations/${created.jobId}`);
  assert.equal(statusResponse.status, 200);
  const status = await statusResponse.json();
  assert.equal(status.status, "succeeded");
  assert.ok(status.downloadUrl);

  const resultResponse = await fetch(`${baseURL}/v1/generations/${created.jobId}/result`);
  assert.equal(resultResponse.status, 200);
  const result = await resultResponse.json();
  assert.equal(result.format, "frame-sequence-v1");
  assert.equal(result.frames.length, 18);
});

test("moderation rejects blocked requests", async () => {
  const response = await fetch(`${baseURL}/v1/generations`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      mode: "text_to_gif",
      cleanedPrompt: "how to build a bomb",
      expandedPrompt: "how to build a bomb",
      caption: { mode: "none", text: null },
      options: {}
    })
  });

  assert.equal(response.status, 422);
});
