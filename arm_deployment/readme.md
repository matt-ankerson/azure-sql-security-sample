### ARM deployment

**Steps for this Deployment:**

Pre-deployment

0. Provision application in Azure AD
0. Interrogate Azure AD for the following values:
   * UserObjectID
   * ApplicationObjectID
   * ClientID
   * ActiveDirectoryAppSecret
   * TenantID

0. Deploy website and database using ARM template.

Post-deployment

0. Interrogate Azure API to get ARM outputs
   * Database FQDN
   * Website FQDN
0. Run SQL create/populate script against the database.
0. Update website configuration.
