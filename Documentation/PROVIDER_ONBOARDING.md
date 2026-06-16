# Provider Onboarding

GifForge stays provider-neutral at the client boundary. The iOS app never calls external AI media providers directly; the backend uses the direct video provider router to choose among enabled fal.ai, Luma, or future backend providers.

## Required Decision Evidence

Create an ignored provider evidence file before selecting a paid provider:

```bash
scripts/validate-provider-onboarding.rb --template Documentation/ProviderEvidence/first-provider.json
```

Fill the evidence after provider review and preflight validation, then run:

```bash
scripts/validate-provider-onboarding.rb Documentation/ProviderEvidence/first-provider.json
```

`Documentation/ProviderEvidence/` is ignored by git. Do not put provider credentials, Authorization header values, API keys, bearer tokens, passwords, or raw provider secret values in the evidence file.

## Contract Requirements

The selected provider path must prove:

- Backend uses the direct video router.
- Text-to-video, image-to-video, and video-to-video are supported.
- Submit returns a non-empty `providerJobId`.
- Result retrieval supports callback or polling until completion.
- Results are downloadable `video/mp4` assets.
- Not-ready result states are retryable instead of being stored as empty assets.
- Provider does not require visible caption text or readable text rendering.
- GIF conversion and caption rendering remain client-side.
- Text, image, and video preflight evidence is recorded.

## Security, Privacy, And Cost Requirements

The selected provider path must prove:

- Credentials stay server-side in Azure Key Vault.
- The iOS app still has no direct provider calls.
- Caption text is not sent to the provider for rendering.
- Provider data-use, retention, and data-processing terms have been reviewed.
- Moderation and abuse-reporting paths are defined.
- Cost model, rate limits, outage fallback, and production rollback are documented.
- Provider enablement and cost override keys are documented in Azure App Configuration.

Provider onboarding is not complete until the evidence validates and deployment evidence confirms `/health` reports `provider=routed-video` and `mode=video`.
