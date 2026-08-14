using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Testcontainers.MsSql;

namespace GifForge.Backend.Tests;

/// <summary>
/// Starts one real SQL Server 2022 container (via Testcontainers) for the
/// whole test run, applies the production migrations exactly as documented in
/// Documentation/DEVELOPMENT.md (001, 002, 003 in order), and exposes a
/// connection string. Shared across the collection so container startup
/// (several seconds) happens once, not once per test.
/// </summary>
public sealed class SqlServerFixture : IAsyncLifetime
{
  private readonly MsSqlContainer container = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest").Build();

  public string ConnectionString { get; private set; } = string.Empty;

  public async Task InitializeAsync()
  {
    await container.StartAsync();
    ConnectionString = container.GetConnectionString();
    await ApplyMigrationsAsync();
  }

  public async Task DisposeAsync()
  {
    await container.DisposeAsync();
  }

  private async Task ApplyMigrationsAsync()
  {
    var migrationsDirectory = Path.Combine(
      AppContext.BaseDirectory,
      "..", "..", "..", "..", "Backend", "Database", "Migrations"
    );
    var migrationFiles = Directory
      .GetFiles(migrationsDirectory, "*.sql")
      .OrderBy(path => path, StringComparer.Ordinal)
      .ToArray();

    if (migrationFiles.Length == 0)
    {
      throw new InvalidOperationException($"No migration files found under '{migrationsDirectory}'.");
    }

    await using var connection = new SqlConnection(ConnectionString);
    await connection.OpenAsync();

    foreach (var migrationFile in migrationFiles)
    {
      foreach (var batch in SplitOnGoBatches(await File.ReadAllTextAsync(migrationFile)))
      {
        if (string.IsNullOrWhiteSpace(batch))
        {
          continue;
        }

        await using var command = connection.CreateCommand();
        command.CommandText = batch;
        await command.ExecuteNonQueryAsync();
      }
    }
  }

  /// <summary>
  /// `GO` is a batch separator recognized by sqlcmd/SSMS, not real T-SQL —
  /// ADO.NET's SqlCommand must execute each batch as a separate command.
  /// </summary>
  private static IEnumerable<string> SplitOnGoBatches(string script) =>
    Regex.Split(script, @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase);
}

[CollectionDefinition("SqlServer")]
public sealed class SqlServerCollection : ICollectionFixture<SqlServerFixture>;
