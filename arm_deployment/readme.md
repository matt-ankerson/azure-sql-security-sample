### ARM deployment

**Steps completed by this deployment:**

Pre-deployment

0. Builds web app to a web-deploy package.
0. Creates a Resource Group and Storage Account.
0. Uploads web-deploy package to Storage Account.
0. Provisions application in Azure AD
0. Interrogates Azure AD for the following values:
   * Tenant ID
   * Application object ID
   * App ID / Client ID
   * Application Secret/Key
   * User object ID

0. Deploys website, database and key-vault using ARM template.

Post-deployment

0. Collects ARM outputs
0. Runs SQL INSERT script against the database.

Sample deployment:
* `.\predeploy my-resource-group-name mystorageaccountname`
