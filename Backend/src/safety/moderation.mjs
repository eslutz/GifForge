const BLOCKED_TERMS = [
  "child sexual",
  "minor sexual",
  "terrorist recruitment",
  "how to build a bomb"
];

export function validateGenerationRequest(body) {
  if (!body || typeof body !== "object") {
    return { ok: false, status: 400, message: "Request body must be a JSON object." };
  }

  if (!["text_to_gif", "image_to_gif"].includes(body.mode)) {
    return { ok: false, status: 400, message: "mode must be text_to_gif or image_to_gif." };
  }

  if (typeof body.cleanedPrompt !== "string" || body.cleanedPrompt.trim().length === 0) {
    return { ok: false, status: 400, message: "cleanedPrompt is required." };
  }

  if (body.cleanedPrompt.length > 600 || String(body.expandedPrompt ?? "").length > 1600) {
    return { ok: false, status: 400, message: "Prompt is too long." };
  }

  if (body.caption?.text && String(body.caption.text).length > 64) {
    return { ok: false, status: 400, message: "Caption is too long." };
  }

  if (body.mode === "image_to_gif") {
    if (!body.sourceImage || typeof body.sourceImage.dataBase64 !== "string") {
      return { ok: false, status: 400, message: "sourceImage is required for image_to_gif." };
    }

    const base64Length = body.sourceImage.dataBase64.length;
    if (base64Length > 8_000_000) {
      return { ok: false, status: 413, message: "sourceImage exceeds the demo upload limit." };
    }
  }

  const searchable = [
    body.cleanedPrompt,
    body.expandedPrompt,
    body.caption?.text
  ].join(" ").toLowerCase();

  const blockedTerm = BLOCKED_TERMS.find((term) => searchable.includes(term));
  if (blockedTerm) {
    return { ok: false, status: 422, message: "Request failed moderation checks." };
  }

  return { ok: true };
}
