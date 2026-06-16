#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "time"

MP4_CONTENT_TYPE = "video/mp4"
REQUIRED_KEY_VAULT_SECRETS = %w[
  GIFFORGE_FAL_API_KEY
  GIFFORGE_LUMA_API_KEY
].freeze
REQUIRED_APP_CONFIG_KEYS = %w[
  GIFFORGE_FAL_ENABLED
  GIFFORGE_LUMA_ENABLED
  GIFFORGE_MODEL_COST_USD_FAL_WAN22_TEXT_TO_VIDEO
  GIFFORGE_MODEL_COST_USD_FAL_WAN22_IMAGE_TO_VIDEO
  GIFFORGE_MODEL_COST_USD_FAL_WAN22_VIDEO_TO_VIDEO
  GIFFORGE_MODEL_COST_USD_LUMA_RAY32_TEXT_TO_VIDEO
  GIFFORGE_MODEL_COST_USD_LUMA_RAY32_IMAGE_TO_VIDEO
  GIFFORGE_MODEL_COST_USD_LUMA_RAY32_VIDEO_TO_VIDEO
].freeze
REQUIRED_TOP_LEVEL_STRINGS = %w[
  decisionOwner
  decisionDate
  providerSelection
  modelCatalogSource
  authenticationLocation
  costModel
  expectedLatency
  rateLimits
  supportContact
  dataRetentionSummary
  moderationSummary
  termsReview
  rollbackPlan
].freeze
REQUIRED_ARRAYS = %w[
  providerNames
  supportedResultContentTypes
  requiredKeyVaultSecrets
  requiredAppConfigurationKeys
].freeze
REQUIRED_CHECKS = {
  "contract" => %w[
    usesDirectVideoRouter
    supportsTextToVideo
    supportsImageToVideo
    supportsVideoToVideo
    returnsProviderJobId
    exposesResultPollingOrCallback
    supportsMp4Result
    handlesNotReadyResultState
    generatedGifRemainsClientSide
    doesNotRequireReadableTextRendering
    preflightTextPassed
    preflightImagePassed
    preflightVideoPassed
  ],
  "securityPrivacy" => %w[
    credentialsBackendOnly
    noIosDirectProviderCalls
    noCaptionTextSentForRendering
    noRawOriginalPromptRequiredByProvider
    providerDataUseReviewed
    providerRetentionReviewed
    dataProcessingTermsReviewed
    moderationPathDefined
    abuseReportingPathDefined
  ],
  "productionReadiness" => %w[
    keyVaultSecretsNamed
    appConfigurationProviderFlagsDefined
    appConfigurationCostKeysDefined
    nonprodSmokePlanDefined
    prodDeployPlanDefined
    healthModeVideoExpected
    appAttestRequired
    costLimitDefined
    rateLimitHandlingDefined
    outageFallbackDefined
  ]
}.freeze
FORBIDDEN_KEY_PATTERNS = [
  /secretValue/i,
  /authorizationValue/i,
  /\A(?:apiKey|accessToken|refreshToken|bearerToken|password|token)\z/i
].freeze

options = {
  template: nil
}

OptionParser.new do |parser|
  parser.banner = "Usage: scripts/validate-provider-onboarding.rb [provider-evidence.json] [--template PATH]"

  parser.on("--template PATH", "Write a provider onboarding evidence template and exit.") do |path|
    options[:template] = path
  end

  parser.on("-h", "--help", "Show this help.") do
    puts parser
    exit
  end
end.parse!

def checklist(keys)
  keys.to_h { |key| [key.to_sym, false] }
end

def evidence_template
  {
    collectedAt: Time.now.utc.iso8601,
    providerNames: [
      "fal.ai",
      "luma"
    ],
    decisionOwner: "",
    decisionDate: "",
    providerSelection: "Direct fal.ai/Luma video router",
    modelCatalogSource: "Backend C# model catalog; App Configuration only overrides provider enablement and costs.",
    supportedResultContentTypes: [
      MP4_CONTENT_TYPE
    ],
    authenticationLocation: "Azure Key Vault secrets referenced through Azure App Configuration; do not store secret values here.",
    requiredKeyVaultSecrets: REQUIRED_KEY_VAULT_SECRETS,
    requiredAppConfigurationKeys: REQUIRED_APP_CONFIG_KEYS,
    costModel: "",
    expectedLatency: "",
    rateLimits: "",
    supportContact: "",
    dataRetentionSummary: "",
    moderationSummary: "",
    termsReview: "",
    rollbackPlan: "",
    contract: checklist(REQUIRED_CHECKS.fetch("contract")).merge(
      providerPayloadInvariant: "Provider-facing requests generate silent MP4 video assets; GIF conversion and caption rendering remain client-side.",
      textPreflightEvidence: "",
      imagePreflightEvidence: "",
      videoPreflightEvidence: "",
      notes: ""
    ),
    securityPrivacy: checklist(REQUIRED_CHECKS.fetch("securityPrivacy")).merge(
      notes: ""
    ),
    productionReadiness: checklist(REQUIRED_CHECKS.fetch("productionReadiness")).merge(
      nonprodSmokeEvidence: "",
      productionDeployEvidence: "",
      notes: ""
    )
  }
end

def validate_no_sensitive_keys(value, path, errors)
  case value
  when Hash
    value.each do |key, child|
      key_path = path.empty? ? key.to_s : "#{path}.#{key}"
      if FORBIDDEN_KEY_PATTERNS.any? { |pattern| key.to_s.match?(pattern) }
        errors << "#{key_path} should not be stored in source-controlled provider evidence. Keep provider credentials in GitHub environment secrets, Azure secrets, or Key Vault."
      end
      validate_no_sensitive_keys(child, key_path, errors)
    end
  when Array
    value.each_with_index { |child, index| validate_no_sensitive_keys(child, "#{path}[#{index}]", errors) }
  end
end

def require_string(hash, key, path, errors)
  value = hash[key]
  return if value.is_a?(String) && !value.strip.empty?

  errors << "#{path}.#{key} must be a non-empty string."
end

def require_true(hash, key, path, errors)
  return if hash[key] == true

  errors << "#{path}.#{key} must be true."
end

def require_array(hash, key, path, errors)
  value = hash[key]
  return value if value.is_a?(Array) && value.any?

  errors << "#{path}.#{key} must be a non-empty array."
  []
end

if options[:template]
  File.write(options[:template], "#{JSON.pretty_generate(evidence_template)}\n")
  puts "Provider onboarding evidence template written to #{options[:template]}"
  exit
end

path = ARGV.fetch(0) do
  warn "Missing provider evidence JSON path. Use --template PATH to create a template."
  exit 2
end

evidence = JSON.parse(File.read(path))
errors = []

validate_no_sensitive_keys(evidence, "", errors)

REQUIRED_TOP_LEVEL_STRINGS.each do |key|
  require_string(evidence, key, "$", errors)
end

REQUIRED_ARRAYS.each do |key|
  require_array(evidence, key, "$", errors)
end

REQUIRED_CHECKS.each do |section, checks|
  value = evidence[section]
  unless value.is_a?(Hash)
    errors << "$.#{section} must be an object."
    next
  end

  checks.each { |check| require_true(value, check, "$.#{section}", errors) }
end

result_types = Array(evidence["supportedResultContentTypes"])
unless result_types.include?(MP4_CONTENT_TYPE)
  errors << "$.supportedResultContentTypes must include #{MP4_CONTENT_TYPE}."
end

required_key_vault_secrets = Array(evidence["requiredKeyVaultSecrets"])
REQUIRED_KEY_VAULT_SECRETS.each do |secret|
  errors << "$.requiredKeyVaultSecrets must include #{secret}." unless required_key_vault_secrets.include?(secret)
end

required_app_config_keys = Array(evidence["requiredAppConfigurationKeys"])
REQUIRED_APP_CONFIG_KEYS.each do |key|
  errors << "$.requiredAppConfigurationKeys must include #{key}." unless required_app_config_keys.include?(key)
end

provider_names = Array(evidence["providerNames"])
%w[fal.ai luma].each do |provider|
  errors << "$.providerNames must include #{provider}." unless provider_names.include?(provider)
end

%w[textPreflightEvidence imagePreflightEvidence videoPreflightEvidence].each do |key|
  require_string(evidence.fetch("contract", {}), key, "$.contract", errors)
end

%w[nonprodSmokeEvidence productionDeployEvidence].each do |key|
  require_string(evidence.fetch("productionReadiness", {}), key, "$.productionReadiness", errors)
end

if errors.any?
  warn "Provider onboarding validation failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "Provider onboarding validation passed for #{path}."
