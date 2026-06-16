# Backend API

## GET `/health`

Returns backend health and active provider mode for Container Apps probes.

```json
{
  "ok": true,
  "provider": "fake-frame-sequence",
  "mode": "demo"
}
```

`mode` is `demo` for the built-in fake provider, `external` when `GIFFORGE_PROVIDER_ADAPTER=external-http` is active, and `video` when the direct fal.ai/Luma video router is active.

## POST `/v1/app-attest/challenges`

Creates a short-lived App Attest challenge. Local demo mode can use this endpoint with `GIFFORGE_APP_ATTEST_DEMO_BYPASS=true`; production uses it as the challenge source for server-side App Attest verification.

```json
{
  "challengeId": "uuid",
  "challenge": "base64url-random",
  "expiresAt": "2026-06-14T23:00:00Z"
}
```

## POST `/v1/app-attest/attestations`

Exchanges an App Attest response for a short-lived backend session token. Generation, status, and result routes require this token when `GIFFORGE_APP_ATTEST_REQUIRED=true`.

The backend rejects placeholder attestation material unless `GIFFORGE_APP_ATTEST_DEMO_BYPASS=true` is explicitly configured. With `GIFFORGE_APP_ATTEST_APP_IDENTIFIER` and `GIFFORGE_APP_ATTEST_ROOT_CERTIFICATE_PEM` configured, it verifies challenge binding, attestation CBOR, certificate trust, nonce binding, key-id matching, RP/app-id hash, and COSE public key matching before issuing a session token.

```json
{
  "keyId": "app-attest-key-id",
  "challengeId": "uuid",
  "attestationObject": "base64-attestation-object",
  "clientDataHash": "base64-client-data-hash"
}
```

Response:

```json
{
  "sessionToken": "base64url-session-token",
  "expiresAt": "2026-06-15T07:00:00Z"
}
```

## POST `/v1/generations`

Creates a provider-neutral generation job.

When App Attest is required, include:

```http
Authorization: Bearer <sessionToken>
```

```json
{
  "id": "96DD3998-C2E1-4C39-B7B1-3559D0D271C8",
  "mode": "text_to_gif",
  "originalPrompt": "a corgi typing at a tiny laptop",
  "cleanedPrompt": "a corgi typing at a tiny laptop",
  "expandedPrompt": "Create a looping animated GIF of a corgi typing at a tiny laptop with a clear subject, short seamless motion, readable composition, no embedded text, and no watermarks.",
  "negativePrompt": "readable text, captions, subtitles, logos, watermarks, violent or sexual content",
  "caption": {
    "mode": "userText",
    "text": "ship it"
  },
  "sourceMedia": null,
  "sourceImage": null,
  "sourceImageContext": null,
  "options": {
    "width": 480,
    "height": 360,
    "loopSeconds": 2,
    "stylePreset": "expressive-loop",
    "motionIntensity": "medium"
  },
  "clientTraceId": "trace-id",
  "retryOfJobId": null
}
```

Validation rules:

- `mode` must be `text_to_gif`, `image_to_gif`, or `video_to_gif`.
- `cleanedPrompt` is required and limited to 600 characters.
- `expandedPrompt` is limited to 1,600 characters.
- Caption mode must be `none`, `userText`, or `suggestWithAI`; caption text is limited to 64 characters.
- `options.width` and `options.height`, when present, must be between 64 and 1,024 pixels.
- `options.loopSeconds`, when present, must be between 0.5 and 6.0 seconds.
- `options.motionIntensity`, when present, must be `subtle`, `medium`, or `high`.
- `image_to_gif` requests must include either `sourceImage` or `sourceMedia`.
- `sourceImage` must be the app-processed, metadata-stripped JPEG payload (`image/jpeg`), valid base64, no larger than the processed upload limit, and no wider or taller than 1,024 pixels.
- `sourceImageContext`, when present, is metadata-only local context such as dimensions, orientation, aspect ratio, and a short summary. Its dimensions must match `sourceImage`.
- `sourceMedia`, when present, supports JPEG, PNG, HEIC/HEIF, GIF, MP4, MOV, and Live Photo paired MOV uploads. GIF, MP4, MOV, and Live Photo paired MOV route to video-to-video provider models. JPEG, PNG, and HEIC/HEIF route to image-to-video provider models.
- `video_to_gif` requests must include `sourceMedia`.
- Live Photo requests must send the paired MOV as `sourceMedia` with `mimeType=video/quicktime` and `role=livePhotoPairedVideo`; sending only the still image is rejected for the Live Photo workflow.
- `retryOfJobId`, when present, must reference a failed generation job whose attempt count has not reached `GIFFORGE_GENERATION_MAX_ATTEMPTS`. The backend uses the previous job's attempted provider/model metadata to select the next cheapest compatible candidate.

Response:

```json
{
  "jobId": "uuid",
  "status": "queued",
  "statusUrl": "http://127.0.0.1:8787/v1/generations/uuid",
  "expiresAt": "2026-06-16T12:00:00Z"
}
```

## GET `/v1/generations/:jobId`

Returns job state.

```json
{
  "jobId": "uuid",
  "status": "succeeded",
  "downloadUrl": "http://127.0.0.1:8787/v1/generations/uuid/result",
  "message": null,
  "expiresAt": "2026-06-16T12:00:00Z",
  "retryAvailable": false,
  "retryReason": null,
  "retryOfJobId": null
}
```

Failed jobs can return `"retryAvailable": true`, `"retryReason": "provider_failed"`, and `"retryOfJobId": "<failed-job-id>"`. Expired jobs return HTTP `410 Gone` from both the status and result routes. After validation, moderation, and provider submission, persisted job state clears raw `originalPrompt`, visible caption text, source-media bytes, and processed source-image bytes. Deployed environments default to expiring remaining job metadata and result links after 24 hours.

## GET `/v1/generations/:jobId/result`

Returns a temporary generated motion asset. The demo provider returns a frame sequence JSON payload:

```json
{
  "format": "frame-sequence-v1",
  "width": 480,
  "height": 360,
  "promptEcho": "a corgi typing at a tiny laptop",
  "frames": [
    {
      "index": 0,
      "duration": 0.08,
      "backgroundHex": "0B132B",
      "accentHex": "5BC0BE",
      "motionOffset": 0
    }
  ]
}
```

Real provider adapters can return either a frame sequence JSON payload or a direct `video/mp4` payload from the result URL. The iOS app converts either result type into frames, renders captions locally, and writes the final GIF before Messages insertion.

## Direct Video Provider Router

Set `GIFFORGE_PROVIDER_ADAPTER=video` or `GIFFORGE_PROVIDER_ADAPTER=fal-luma` to enable the built-in provider abstraction. The router classifies each request:

- prompt only -> text-to-video
- still image -> image-to-video
- GIF, MP4, MOV, or Live Photo paired MOV -> video-to-video

Enabled provider/model candidates are ordered by configured estimated cost. fal.ai Wan 2.2 defaults are cheaper and selected first. Luma Ray 3.2 defaults are configured as retry candidates. The backend submits to the cheapest compatible candidate for the request. If the provider fails, the job response can include retry metadata; the iOS client keeps the original request media locally, asks the user, and only resubmits with `retryOfJobId` after confirmation. The retry submission skips providers/models already attempted for the previous job.

Provider configuration should come from Azure App Configuration, with API keys stored in Azure Key Vault and referenced by App Configuration or loaded directly from Key Vault. Supported settings include:

- `GIFFORGE_FAL_API_KEY`
- `GIFFORGE_FAL_SUBMIT_URL_TEMPLATE`
- `GIFFORGE_FAL_RESULT_URL_TEMPLATE`
- `GIFFORGE_FAL_TEXT_MODEL`, `GIFFORGE_FAL_IMAGE_MODEL`, `GIFFORGE_FAL_VIDEO_MODEL`
- `GIFFORGE_FAL_TEXT_MODEL_COST_USD`, `GIFFORGE_FAL_IMAGE_MODEL_COST_USD`, `GIFFORGE_FAL_VIDEO_MODEL_COST_USD`
- `GIFFORGE_LUMA_API_KEY`
- `GIFFORGE_LUMA_SUBMIT_URL_TEMPLATE`
- `GIFFORGE_LUMA_RESULT_URL_TEMPLATE`
- `GIFFORGE_LUMA_TEXT_MODEL`, `GIFFORGE_LUMA_IMAGE_MODEL`, `GIFFORGE_LUMA_VIDEO_MODEL`
- `GIFFORGE_LUMA_TEXT_MODEL_COST_USD`, `GIFFORGE_LUMA_IMAGE_MODEL_COST_USD`, `GIFFORGE_LUMA_VIDEO_MODEL_COST_USD`

The backend downloads provider result assets and stores generated MP4s in GifForge-controlled storage. The app receives only `/v1/generations/:jobId/result` URLs, never provider URLs.

The backend does not persist source media for retry/fallback. After validation and provider submission, durable job state clears raw source-media and source-image bytes. Retry material remains on the client device in the active-generation snapshot until the job succeeds, expires, or the user declines retry. `GIFFORGE_GENERATION_MAX_ATTEMPTS` caps total client-mediated retry attempts, defaulting to 3.

Failed job status responses include `retryAvailable`, `retryReason`, and `retryOfJobId` when the backend can accept a user-confirmed retry.

## POST `/v1/provider-callbacks/:jobId`

Provider gateways can push completion to this endpoint instead of waiting for queue polling. If `GIFFORGE_PROVIDER_CALLBACK_SECRET` is configured, callbacks must include:

```http
X-GifForge-Provider-Callback-Secret: <secret>
```

Successful callback:

```json
{
  "status": "succeeded",
  "providerJobId": "provider-job-id",
  "assetUrl": "https://provider.example/video.mp4",
  "contentType": "video/mp4"
}
```

The backend validates the provider job id, downloads the asset, stores it in GifForge-controlled result storage, marks the job succeeded, and keeps returning the stable `/v1/generations/:jobId/result` URL to the iOS client. Failed callbacks mark the job failed with generic app-safe copy and retry metadata when another configured provider/model remains available. Unknown in-progress statuses are accepted without changing the job.

## External HTTP Provider Contract

Set `GIFFORGE_PROVIDER_ADAPTER=external-http` to use the provider-neutral HTTP adapter. The backend maps the app request into a sanitized provider payload before posting to `GIFFORGE_EXTERNAL_PROVIDER_SUBMIT_URL`; that payload includes motion prompt fields, options, optional source-image/source-image-context data, `captionMode`, and `renderCaptionLocally=true`, but omits raw `originalPrompt` and visible caption text.

Submission response:

```json
{
  "providerJobId": "provider-specific-job-id"
}
```

Submission failure handling:

- Provider `400`, `401`, `403`, and `422` responses are treated as permanent provider rejections. The app-facing generation route returns HTTP `422` with generic safe copy and does not persist or dispatch a generation job.
- Provider `408`, `429`, `5xx`, network, and timeout-style failures are treated as retryable availability failures. The app-facing generation route returns HTTP `503` with generic safe copy and does not expose provider error bodies.

The backend later downloads the motion asset from `GIFFORGE_EXTERNAL_PROVIDER_RESULT_URL_TEMPLATE`, replacing `{providerJobId}` and `{jobId}` placeholders. The result response must use either:

- `application/vnd.gifforge.frame-sequence+json`
- `video/mp4`

Result responses of `202` or `204` are treated as retryable not-ready states, so the queue worker can retry instead of storing an empty asset. Result responses with unsupported content types or empty motion assets are treated as permanent provider failures.

Before deploying a real provider gateway, run `scripts/validate-external-provider-contract.rb` with `GIFFORGE_EXTERNAL_PROVIDER_SUBMIT_URL`, `GIFFORGE_EXTERNAL_PROVIDER_RESULT_URL_TEMPLATE`, and optional `GIFFORGE_EXTERNAL_PROVIDER_AUTHORIZATION`. The script submits the same sanitized provider payload shape, validates that the submit response returns `providerJobId`, polls the result URL until the configured timeout, and verifies that the result is either non-empty `video/mp4` or a valid `frame-sequence-v1` payload. Use `--print-payload` to inspect the exact JSON without making network calls.

Use `Documentation/PROVIDER_ONBOARDING.md` and `scripts/validate-provider-onboarding.rb` to record the selected provider decision, text/image preflight evidence, privacy/security review, cost/rate-limit review, and production secret plan before switching production to `providerAdapter=external-http`.
