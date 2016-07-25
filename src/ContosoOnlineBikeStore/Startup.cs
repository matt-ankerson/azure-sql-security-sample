using Microsoft.Owin;
using Owin;
using Microsoft.SqlServer.Management.AlwaysEncrypted.AzureKeyVaultProvider;
using System.Collections.Generic;
using System.Data.SqlClient;
using Microsoft.IdentityModel.Clients.ActiveDirectory;

[assembly: OwinStartupAttribute(typeof(ContosoOnlineBikeStore.Startup))]
namespace ContosoOnlineBikeStore
{
    public partial class Startup
    {
        public void Configuration(IAppBuilder app)
        {
            ConfigureAuth(app);
            InitializeAzureKeyVaultProvider();
        }

        private static Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential _clientCredential;

        static void InitializeAzureKeyVaultProvider()
        {
            string clientId = "65c01ff5-add9-47dc-8a18-08ade7b516a4";
            string clientSecret = "qgb0M91ysvhs+2rzpyKo+Nv/nbR/O+ZV88DZ/fseHEk=";

            _clientCredential = new ClientCredential(clientId, clientSecret);

           SqlColumnEncryptionAzureKeyVaultProvider azureKeyVaultProvider =
              new SqlColumnEncryptionAzureKeyVaultProvider(GetToken);

            Dictionary<string, SqlColumnEncryptionKeyStoreProvider> providers =
              new Dictionary<string, SqlColumnEncryptionKeyStoreProvider>();

            providers.Add(SqlColumnEncryptionAzureKeyVaultProvider.ProviderName, azureKeyVaultProvider);
            SqlConnection.RegisterColumnEncryptionKeyStoreProviders(providers);
        }

        public async static System.Threading.Tasks.Task<string> GetToken(string authority, string resource, string scope)
        {
            var authContext = new AuthenticationContext(authority);
            AuthenticationResult result = await authContext.AcquireTokenAsync(resource, _clientCredential);

            if (result == null)
                throw new System.InvalidOperationException("Failed to obtain the access token");

            return result.AccessToken;
        }
    }
}