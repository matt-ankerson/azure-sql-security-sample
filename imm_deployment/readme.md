### ARM deployment for Immersion platform

**Steps completed by this deployment:**

Pre-deployment

0. Get or creates resource group.
0. Deploys website, database and key-vault using ARM template.

Post-deployment

0. Collects ARM outputs
0. Provision application in Azure AD
0. Interrogates Azure AD for the following values:
   * Tenant ID
   * Application object ID
   * App ID / Client ID
   * Application Secret/Key
   * User object ID
0. Create Key Vault access policies.
0. Update website configuration.
0. Runs SQL INSERT script against the database.

Sample deployment:
* `.\simulate_deployment`

**Note:** You may want to edit some of the parameters supplied by the simulate\_deployment script.
