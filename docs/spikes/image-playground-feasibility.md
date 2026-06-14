# Evaluate Image Playground Feasibility Inside the iMessage Extension

## Spike Goal

Determine whether Image Playground can be used as an optional Apple-native still-image generation path without blocking the external-provider architecture.

## Likely v1 Decision

Plan as if Image Playground is not available. Treat it as a possible future enhancement.

## Research Questions

- Can Image Playground be presented from an iMessage extension?
- Does it work in compact and expanded Messages modes?
- Can the app receive and access the generated image result?
- Can the generated image be used as source material for the app's GIF pipeline?
- Is the system UI acceptable for a fast GIPHY-like Messages flow?
- What happens when Apple Intelligence, Private Cloud Compute, or Image Playground is unavailable?
- Are there App Review concerns?

## Acceptance Criteria

- Prototype can launch Image Playground from the Messages extension.
- Prototype can receive an image result.
- Prototype can turn that still image into a simple GIF.
- Prototype can insert the resulting GIF using attachment insertion.
- Feasibility is classified as one of:
  - Adopt now.
  - Optional source-image mode only.
  - Post-v1.
  - Do not use.

## Prototype Plan

1. Add an isolated spike branch and a separate `ImagePlaygroundSpikeView`.
2. Present Image Playground from expanded Messages mode first.
3. Record compact-mode behavior separately.
4. Convert the returned still image into a two-frame GIF through `PromptGIFCore`.
5. Insert the GIF with attachment insertion.
6. Test unavailable-device behavior.
7. Document App Review risks and UX tradeoffs.
