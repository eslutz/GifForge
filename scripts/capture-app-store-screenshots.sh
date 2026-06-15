#!/usr/bin/env bash
set -euo pipefail

output_dir="${1:-${GIFFORGE_SCREENSHOT_OUTPUT_DIR:-Documentation/AppStoreScreenshots/containing-app}}"
destination="${GIFFORGE_SCREENSHOT_DESTINATION:-platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro}"
derived_data_path="${GIFFORGE_SCREENSHOT_DERIVED_DATA:-/private/tmp/gifforge-screenshot-derived-data}"
result_bundle_path="${GIFFORGE_SCREENSHOT_RESULT_BUNDLE:-/private/tmp/gifforge-app-store-screenshots.xcresult}"
attachments_path="${GIFFORGE_SCREENSHOT_ATTACHMENTS:-/private/tmp/gifforge-app-store-screenshots-attachments}"

rm -rf "$output_dir" "$attachments_path"
mkdir -p "$output_dir"
rm -rf "$result_bundle_path"

printf 'Capturing GifForge containing-app screenshots\n'
printf 'Output: %s\n' "$output_dir"
printf 'Destination: %s\n' "$destination"
printf 'Result bundle: %s\n\n' "$result_bundle_path"

xcodebuild \
  -quiet \
  -project Client/GifForge.xcodeproj \
  -scheme GifForge \
  -configuration Debug \
  -destination "$destination" \
  -derivedDataPath "$derived_data_path" \
  -resultBundlePath "$result_bundle_path" \
  -only-testing:GifForgeUITests/GifForgeUITests/testCaptureContainingAppScreenshotsForAppStorePrep \
  test

xcrun xcresulttool export attachments \
  --path "$result_bundle_path" \
  --output-path "$attachments_path"

ruby -rjson -rfileutils -e '
attachments_path, output_dir = ARGV
manifest_path = File.join(attachments_path, "manifest.json")
manifest = JSON.parse(File.read(manifest_path))
attachments = manifest.flat_map { |entry| entry.fetch("attachments", []) }
expected_names = %w[
  01-containing-app-overview.png
  02-containing-app-history.png
  03-containing-app-clear-history.png
  04-containing-app-settings.png
]

attachments.each do |attachment|
  exported_name = attachment.fetch("exportedFileName")
  suggested_name = attachment.fetch("suggestedHumanReadableName", exported_name)
  output_name = suggested_name.sub(/_\d+_[0-9A-F-]+(?=\.png\z)/, "")
  FileUtils.cp(
    File.join(attachments_path, exported_name),
    File.join(output_dir, output_name)
  )
end

missing = expected_names.reject { |name| File.file?(File.join(output_dir, name)) }
unless missing.empty?
  warn "Missing expected screenshot attachments: #{missing.join(", ")}"
  exit 1
end
' "$attachments_path" "$output_dir"

printf '\nScreenshots written to %s\n' "$output_dir"
printf 'XCTest result bundle: %s\n' "$result_bundle_path"
