using GifForge.Backend.Security;
using Microsoft.Data.SqlClient;
using System.Reflection;

namespace GifForge.Backend.Tests;

public sealed class SqlGifForgeAccountStoreTests
{
  [Fact]
  public void ConstructorDoesNotUseSqlClientActiveDirectoryAuthentication()
  {
    var store = new SqlGifForgeAccountStore("gifforge.database.windows.net", "gifforge");

    var connectionString = (string)typeof(SqlGifForgeAccountStore)
      .GetField("connectionString", BindingFlags.Instance | BindingFlags.NonPublic)!
      .GetValue(store)!;
    var builder = new SqlConnectionStringBuilder(connectionString);

    Assert.Equal(SqlAuthenticationMethod.NotSpecified, builder.Authentication);
    Assert.True(builder.Encrypt);
    Assert.False(builder.TrustServerCertificate);
  }

  [Theory]
  [InlineData(1, true)]
  [InlineData(2, false)]
  public void ShouldRetryOpenRetriesOnlyTheFirstTransientTimeout(int attempt, bool expected)
  {
    var shouldRetry = SqlGifForgeAccountStore.ShouldRetryOpen(new TimeoutException(), attempt);

    Assert.Equal(expected, shouldRetry);
  }
}
