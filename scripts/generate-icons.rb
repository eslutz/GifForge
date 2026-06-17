#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tempfile"

ROOT = File.expand_path("..", __dir__)

SOURCE_ICON = File.join(ROOT, "Documentation", "Branding", "AppIconSource.jpg")
APP_ICON = File.join(ROOT, "Client", "App", "GifForge", "Assets.xcassets", "AppIcon.appiconset")
MESSAGES_ICON = File.join(ROOT, "Client", "Extensions", "GifForgeMessages", "Assets.xcassets", "iMessage App Icon.stickersiconset")

def run_sips!(*args)
  stdout, stderr, status = Open3.capture3("sips", *args)
  return stdout if status.success?

  warn stderr unless stderr.empty?
  raise "sips failed: #{args.join(' ')}"
end

def image_size(path)
  output = run_sips!("-g", "pixelWidth", "-g", "pixelHeight", path)
  width = output[/pixelWidth:\s+(\d+)/, 1]&.to_i
  height = output[/pixelHeight:\s+(\d+)/, 1]&.to_i
  raise "Could not read image dimensions for #{path}" unless width && height

  [width, height]
end

def write_png_from_source(source, output, width, height)
  source_width, source_height = image_size(source)
  target_ratio = width.to_f / height
  source_ratio = source_width.to_f / source_height

  crop_width = source_width
  crop_height = source_height

  if source_ratio > target_ratio
    crop_width = (source_height * target_ratio).round
  elsif source_ratio < target_ratio
    crop_height = (source_width / target_ratio).round
  end

  FileUtils.mkdir_p(File.dirname(output))

  Tempfile.create(["gifforge-icon-crop", ".png"]) do |cropped|
    cropped.close
    run_sips!(
      "-c", crop_height.to_s, crop_width.to_s,
      source,
      "-o", cropped.path
    )
    run_sips!(
      "-s", "format", "png",
      "-z", height.to_s, width.to_s,
      cropped.path,
      "-o", output
    )
  end
end

unless File.file?(SOURCE_ICON)
  raise "Missing source icon at #{SOURCE_ICON}"
end

FileUtils.mkdir_p(APP_ICON)
FileUtils.mkdir_p(MESSAGES_ICON)

write_png_from_source(SOURCE_ICON, File.join(APP_ICON, "gifforge-app-icon-1024.png"), 1024, 1024)

{
  "gifforge-messages-58.png" => [58, 58],
  "gifforge-messages-87.png" => [87, 87],
  "gifforge-messages-120x90.png" => [120, 90],
  "gifforge-messages-180x135.png" => [180, 135],
  "gifforge-messages-134x100.png" => [134, 100],
  "gifforge-messages-148x110.png" => [148, 110],
  "gifforge-messages-54x40.png" => [54, 40],
  "gifforge-messages-81x60.png" => [81, 60],
  "gifforge-messages-64x48.png" => [64, 48],
  "gifforge-messages-96x72.png" => [96, 72],
  "gifforge-messages-1024x768.png" => [1024, 768]
}.each do |filename, (width, height)|
  write_png_from_source(SOURCE_ICON, File.join(MESSAGES_ICON, filename), width, height)
end

puts "Generated GifForge app and iMessage icon assets from Documentation/Branding/AppIconSource.jpg."
