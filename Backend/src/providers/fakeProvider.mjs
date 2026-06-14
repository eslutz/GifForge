import { createHash } from "node:crypto";

export class FakeProvider {
  constructor() {
    this.name = "fake-frame-sequence";
  }

  async submitGeneration(request) {
    return {
      provider: this.name,
      providerJobId: `fake_${createHash("sha256").update(request.clientTraceID ?? request.cleanedPrompt).digest("hex").slice(0, 16)}`
    };
  }

  async getResult(request) {
    const palette = paletteForPrompt(request.cleanedPrompt);
    const frameCount = 18;
    const width = request.options?.width ?? 480;
    const height = request.options?.height ?? 360;
    const loopSeconds = request.options?.loopSeconds ?? 2.4;
    const duration = Number((loopSeconds / frameCount).toFixed(3));

    return {
      format: "frame-sequence-v1",
      width,
      height,
      promptEcho: request.cleanedPrompt,
      frames: Array.from({ length: frameCount }, (_, index) => ({
        index,
        duration,
        backgroundHex: palette[index % palette.length],
        accentHex: palette[(index + 2) % palette.length],
        motionOffset: Math.sin((index / frameCount) * Math.PI * 2) * 48
      }))
    };
  }
}

function paletteForPrompt(prompt) {
  const palettes = [
    ["#006D77", "#83C5BE", "#EDF6F9", "#FFDDD2", "#E29578"],
    ["#264653", "#2A9D8F", "#E9C46A", "#F4A261", "#E76F51"],
    ["#0B132B", "#5BC0BE", "#F7FFF7", "#FFE66D", "#FF6B6B"],
    ["#233D4D", "#A1C181", "#FE7F2D", "#FCCA46", "#619B8A"]
  ];
  const digest = createHash("sha256").update(prompt).digest();
  return palettes[digest[0] % palettes.length];
}
