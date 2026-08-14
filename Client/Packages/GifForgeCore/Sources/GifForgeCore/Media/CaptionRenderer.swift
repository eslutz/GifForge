import CoreGraphics
import CoreText
import Foundation

public struct CaptionRenderingStyle: Sendable {
  public var fontSize: CGFloat
  public var minimumFontSize: CGFloat
  public var bottomInset: CGFloat
  public var horizontalInset: CGFloat
  public var maxLines: Int

  public init(
    fontSize: CGFloat = 32,
    minimumFontSize: CGFloat = 18,
    bottomInset: CGFloat = 28,
    horizontalInset: CGFloat = 24,
    maxLines: Int = 2
  ) {
    self.fontSize = fontSize
    self.minimumFontSize = minimumFontSize
    self.bottomInset = bottomInset
    self.horizontalInset = horizontalInset
    self.maxLines = maxLines
  }
}

public struct CaptionTextLayout: Sendable {
  public var lines: [String]
  public var fontSize: CGFloat
  public var textBounds: CGRect

  public init(lines: [String], fontSize: CGFloat, textBounds: CGRect) {
    self.lines = lines
    self.fontSize = fontSize
    self.textBounds = textBounds
  }
}

public struct CaptionRenderer: Sendable {
  public var style: CaptionRenderingStyle

  public init(style: CaptionRenderingStyle = CaptionRenderingStyle()) {
    self.style = style
  }

  public func layoutCaption(_ caption: String, canvasSize: CGSize) -> CaptionTextLayout {
    let maxWidth = max(1, canvasSize.width - style.horizontalInset * 2)
    let maxLines = max(1, style.maxLines)
    let words = caption
      .replacingOccurrences(of: "\n", with: " ")
      .split(separator: " ")
      .map(String.init)

    func layout(at fontSize: CGFloat) -> (layout: CaptionTextLayout, fits: Bool) {
      let font = Self.captionFont(size: fontSize)
      let lines = wrappedLines(words: words, font: font, maxWidth: maxWidth, maxLines: maxLines)
      let widest = lines.map { lineWidth($0, font: font) }.max() ?? 0
      let result = CaptionTextLayout(
        lines: lines,
        fontSize: fontSize,
        textBounds: CGRect(
          x: 0,
          y: 0,
          width: min(maxWidth, widest),
          height: CGFloat(lines.count) * fontSize * 1.16
        )
      )
      return (result, lines.count <= maxLines && widest <= maxWidth)
    }

    // Binary-search the largest whole-point size that fits; fitting is monotonic in size.
    var low = Int(style.minimumFontSize)
    var high = Int(style.fontSize)
    var best: CaptionTextLayout?

    while low <= high {
      let mid = (low + high) / 2
      let candidate = layout(at: CGFloat(mid))
      if candidate.fits {
        best = candidate.layout
        low = mid + 1
      } else {
        high = mid - 1
      }
    }

    return best ?? layout(at: style.minimumFontSize).layout
  }

  public func renderCaption(_ caption: String?, over image: CGImage) throws -> CGImage {
    guard let caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return image
    }

    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw GifForgeError.mediaRenderingFailed(message: "Could not create a caption drawing context.")
    }

    let size = CGSize(width: image.width, height: image.height)
    context.draw(image, in: CGRect(origin: .zero, size: size))
    drawCaption(caption, in: context, canvasSize: size)

    guard let rendered = context.makeImage() else {
      throw GifForgeError.mediaRenderingFailed(message: "Could not render captioned frame.")
    }

    return rendered
  }

  private func drawCaption(_ caption: String, in context: CGContext, canvasSize: CGSize) {
    context.saveGState()
    context.translateBy(x: 0, y: canvasSize.height)
    context.scaleBy(x: 1, y: -1)
    context.textMatrix = .identity

    let layout = layoutCaption(caption, canvasSize: canvasSize)
    let font = Self.captionFont(size: layout.fontSize)
    let lineHeight = layout.fontSize * 1.16
    var y = canvasSize.height - style.bottomInset - layout.textBounds.height
    context.setShadow(
      offset: CGSize(width: 0, height: 2),
      blur: 6,
      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.75)
    )

    for text in layout.lines {
      let attributes = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
      ] as CFDictionary
      guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes) else {
        continue
      }

      let line = CTLineCreateWithAttributedString(attributed)
      let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds, .useOpticalBounds])
      let x = max(style.horizontalInset, (canvasSize.width - bounds.width) / 2)
      context.textPosition = CGPoint(x: x, y: y)
      CTLineDraw(line, context)
      y += lineHeight
    }

    context.restoreGState()
  }

  private func wrappedLines(
    words: [String],
    font: CTFont,
    maxWidth: CGFloat,
    maxLines: Int
  ) -> [String] {
    guard !words.isEmpty else {
      return []
    }

    var lines: [String] = []
    var current = ""

    for word in words {
      let candidate = current.isEmpty ? word : "\(current) \(word)"
      if lineWidth(candidate, font: font) <= maxWidth || current.isEmpty {
        current = candidate
      } else {
        lines.append(current)
        current = word
      }

      if lines.count == maxLines {
        break
      }
    }

    if !current.isEmpty, lines.count < maxLines {
      lines.append(current)
    }

    if lines.count == maxLines,
       let last = lines.indices.last,
       words.joined(separator: " ").hasPrefix(lines.joined(separator: " ")) == false {
      lines[last] = String(lines[last].prefix(max(0, lines[last].count - 1))) + "..."
    }

    return lines
  }

  private func lineWidth(_ text: String, font: CTFont) -> CGFloat {
    guard let attributed = CFAttributedStringCreate(nil, text as CFString, [kCTFontAttributeName: font] as CFDictionary) else {
      return 0
    }

    let line = CTLineCreateWithAttributedString(attributed)
    return CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds, .useOpticalBounds]).width
  }

  /// The system's bold UI font so captions match platform typography, with the
  /// historical HelveticaNeue-Bold as fallback where the UI font is unavailable.
  static func captionFont(size: CGFloat) -> CTFont {
    if let uiFont = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) {
      return uiFont
    }

    return CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
  }
}
