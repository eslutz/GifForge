using System.Runtime.CompilerServices;

namespace GifForge.Backend.Tests;

internal static class TestEnvironment
{
  // Runs once when the test assembly loads, before any test executes.
  // GifForgeBackendApp.Create reads configuration from the real process
  // environment (WebApplication.CreateSlimBuilder includes environment
  // variables by default), and GIFFORGE_AUTH_SIGNING_KEY is now
  // unconditionally required with no fallback — every test that spins up
  // the full app needs a real value here, or every one of them throws.
  [ModuleInitializer]
  internal static void SetSigningKey()
  {
    Environment.SetEnvironmentVariable("GIFFORGE_AUTH_SIGNING_KEY", "test-signing-key-not-for-production-use");
  }
}
