Function Start-ImmersionPostDeployScript
{
    param(
        [Parameter(Mandatory=$true)]
        [PSCredential]
        $Credentials,
        
        [Parameter(Mandatory=$true)]
        [string]
        $TenantId,

        [Parameter(Mandatory=$true)]
        [string]
        $SubscriptionId,
                                
        [Parameter(Mandatory=$true)]
        [string]
        $Region,

        [Parameter(Mandatory=$true)]
        [string]
        $UserEmail,

        [Parameter(Mandatory=$true)]
        [string]
        $UserPassword,

        [Parameter(Mandatory=$true)]
        [string]
        $ResourceGroupName,
                                
        [Parameter(Mandatory=$true)]
        [string]
        $StorageAccountName
    )

    #
    # Post-deployment steps - to be run after the successful
    #   deployment of the ARM template.
    #
    #   Steps completed:
    #       - Get outputs from ARM deployment.
    #       - Provisions application in Azure AD.
    #       - Creates access policies for Azure Key Vault.
    #       - Updates config for web application
    #       - Inserts seed data in SQL database.
    #

    Connect-MsolService -Credential $Credentials

    #---------------------------------------------#
    # Get the outputs from the latest deployment. #
    #---------------------------------------------#

    Write-Host 'Fetching ARM outputs'

    $deployOutputs = (Get-AzureRMResourceGroupDeployment "$($ResourceGroupName)").Outputs

    #--------------------------------#
    # Setup some necessary variables #
    #--------------------------------#
    $region = $deployOutputs['region'].value
    $username = $deployOutputs['username'].value
    $password = $deployOutputs['password'].value

    $keyVaultName = $deployOutputs['keyVaultName'].value
    $siteName = $deployOutputs['siteName'].value
    $sqlServerName = $deployOutputs['sqlServerName'].value
    $sqlServerDbName = $deployOutputs['sqlServerDbName'].value
    $sqlServerUsername = $deployOutputs['sqlServerUsername'].value

    $aadAppPrincipalId = New-Guid
    $aadSecretGuid = New-Guid
    $aadSecretBytes = [System.Text.Encoding]::UTF8.GetBytes($aadSecretGuid)
    $aadDisplayName = "sqlinjapp$ResourceGroupName"
    $aadTenantId = Get-AzureRmSubscription | Select-Object -ExpandProperty TenantId

    $keyCredential = New-Object  Microsoft.Azure.Commands.Resources.Models.ActiveDirectory.PSADKeyCredential
    $keyCredential.StartDate = [DateTime]::UtcNow.AddDays(-1).ToString('u').Replace(' ', 'T')
    $keyCredential.EndDate= [DateTime]::UtcNow.AddDays(365).ToString('u').Replace(' ', 'T');
    $keyCredential.KeyId = $aadAppPrincipalId
    $keyCredential.Type = "Symmetric"
    $keyCredential.Usage = "Verify"
    $keyCredential.Value = [System.Convert]::ToBase64String($aadSecretBytes)

    #------------------------------------#
    # Provision a new application in AAD #
    #------------------------------------#

    Write-Host 'Provisioning application in AAD'

    # Try retrieve AD application
    $aadApplication = Get-AzureRmAdApplication -IdentifierUri "http://$siteName"

    if ($aadApplication -eq $null) {
        # Create AAD application
        $aadApplication = New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage "http://$siteName" -IdentifierUris "http://$siteName" -KeyCredentials $keyCredential
        # Create service principal for AD application.
        $aadAppServicePrincipal = New-AzureRmADServicePrincipal -ApplicationId $aadApplication.ApplicationId
    } else {
        # AAD application exists, get its service principal.
        $aadAppServicePrincipal = Get-AzureRmADServicePrincipal -SearchString $aadDisplayName
    }


    Write-Host 'Extracting configuration values from AAD response'

    # User objectID
    $aadUserObjectId = Get-AzureRmAdUser -UserPrincipalName $UserEmail | Select-Object -ExpandProperty Id

    # Application's service principal's objectID
    $aadAppServicePrincipalObjectId = $aadAppServicePrincipal.Id
    # Application object ID
    $aadAppObjectId = $aadApplication.ApplicationObjectId
    # App ID / Client ID
    $aadClientId = $aadApplication.ApplicationId

    #----------------------------------#
    # Create Key Vault Access Policies #
    #----------------------------------#

    Write-Host "Creating Key Vault Access Policies for $($keyVaultName)"

    # Create access policy for application.
    # - grants the app permission to read secrets
    Set-AzureRmKeyVaultAccessPolicy -VaultName $keyVaultName -ApplicationId $aadClientId -ObjectId $aadAppServicePrincipalObjectId -PermissionsToSecrets @('get','list') -PermissionsToKeys get,wrapkey,unwrapkey,sign,verify

    # Create access policy for user.
    # - grants the user permission to read and write secrets
    Set-AzureRmKeyVaultAccessPolicy -VaultName $keyVaultName -ObjectId $aadUserObjectId.ToString() -PermissionsToSecrets @('get','list') -PermissionsToKeys create,get,wrapkey,unwrapkey,sign,verify


    #------------------------------#
    # Update website configuration #
    #------------------------------#

    Write-Host 'Updating site config'

    # Get the web app.
    $webApp = Get-AzureRmWebApp -ResourceGroupName "$($ResourceGroupName)" -Name "$($siteName)"
    # Pull out the site settings.
    $appSettingsList = $webApp.SiteConfig.AppSettings

    # Build an object containing the app settings.
    $appSettings = @{}
    ForEach ($kvp in $appSettingsList) {
        $appSettings[$kvp.Name] = $kvp.Value
    }

    # Add the necessary settings to the settings object
    $appSettings['administratorLogin'] = $username
    $appSettings['administratorLoginPassword'] = $password
    $appSettings['applicationLogin'] = $username
    $appSettings['applicationLoginPassword'] = $password
    $appSettings['applicationADID'] = $aadClientId.ToString()
    $appSettings['applicationADSecret'] = $aadSecretGuid.ToString()

    # Push the new app settings back to the web app
    Set-AzureRmWebApp -ResourceGroupName "$($ResourceGroupName)" -Name "$($siteName)" -AppSettings $appSettings


    #----------------------------------------------#
    # Run SQL scripts to populate necessary tables #
    #----------------------------------------------#

    Write-Host 'Executing database bootstrap scripts'

    $sqlServer         = $sqlServerName
    $sqlServerUsername = $sqlServerUsername
    $sqlServerPassword = $password
    $sqlServerDatabase = $sqlServerDbName

    $sqlTimeoutSeconds = [int] [TimeSpan]::FromMinutes(8).TotalSeconds 
    $sqlConnectionTimeoutSeconds = [int] [TimeSpan]::FromMinutes(2).TotalSeconds

    # sql query includes a 1 min wait for reasonable certainty that the database is ready.
    $sqlQuery = "
WAITFOR DELAY '00:01:00'

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'376f23d3-7caf-49be-95cb-17d65be4f0af', NULL, 0, N'ABko+BO9HAfOqj0/fffs4WKSBaMIoww1iSs6WeJWBWgmrymphRs8bsWAIMfFIHUyeA==', N'38e57991-d484-4627-9194-329fd356ff87', NULL, 0, 0, NULL, 0, 0, N'alice@contoso.com')
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'c5834663-0d2d-4089-8dda-f0ede35e4152', NULL, 0, N'AB54hSnUejqCfTTOy9BHs0m1jxYgFbdRnS+IigFEuy/npP5eNPGCV8GgzARnwEWStw==', N'25fc5209-6664-43d7-a678-200eb6770f71', NULL, 0, 0, NULL, 0, 0, N'rachel@contoso.com')

SET IDENTITY_INSERT [dbo].[Customers] ON 

INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (1, N'7080500924846561', N'Catherine', N'Abel', N'R.', N'57251 Serene Blvd', N'Van Nuys', N'91411', N'CA', CAST(N'1996-09-10' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (2, N'1754110183784465', N'Kim', N'Abercrombie', N'', N'Tanger Factory', N'Branch', N'55056', N'MN', CAST(N'1967-06-05' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (3, N'7666907822888209', N'Frances', N'Adams', N'B.', N'6900 Sisk Road', N'Modesto', N'95354', N'CA', CAST(N'2005-12-26' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (4, N'7693674877859346', N'Jay', N'Adams', N'', N'Blue Ridge Mall', N'Kansas City', N'64106', N'MS', CAST(N'2011-12-28' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (5, N'3329417446634529', N'Robert', N'Ahlering', N'E.', N'6500 East Grant Road', N'Tucson', N'85701', N'AZ', CAST(N'1953-12-01' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (6, N'3294656316927245', N'Stanley', N'Alan', N'A.', N'567 Sw Mcloughlin Blvd', N'Milwaukie', N'97222', N'OR', CAST(N'1967-09-15' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (7, N'7928476634907615', N'Paul', N'Alcorn', N'L.', N'White Mountain Mall', N'Rock Springs', N'82901', N'WY', CAST(N'2010-03-23' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (8, N'4489446772613881', N'Mary', N'Alexander', N'', N'2345 West Spencer Road', N'Lynnwood', N'98036', N'WA', CAST(N'1985-02-20' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (9, N'3838954836066459', N'Michelle', N'Alexander', N'', N'22589 West Craig Road', N'North Las Vegas', N'89030', N'NV', CAST(N'2009-03-02' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (10, N'3551367087884326', N'Marvin', N'Allen', N'N.', N'First Colony Mall', N'Sugar Land', N'77478', N'TX', CAST(N'1962-12-26' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (11, N'4946484506883279', N'Oscar', N'Alpuerto', N'L.', N'Rocky Mountain Pines Outlet', N'Loveland', N'80537', N'CO', CAST(N'2000-09-19' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (12, N'5480538995207698', N'Ramona', N'Antrim', N'J.', N'998 Forest Road', N'Saginaw', N'48601', N'MI', CAST(N'1991-11-12' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (13, N'7138122715569670', N'Thomas', N'Armstrong', N'B.', N'Fox Hills', N'Culver City', N'90232', N'CA', CAST(N'1964-11-06' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (14, N'6196888279074482', N'John', N'Arthur', N'', N'2345 North Freeway', N'Houston', N'77003', N'TX', CAST(N'1987-10-12' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (15, N'3718062234715231', N'Chris', N'Ashton', N'', N'70 N.W. Plaza', N'Saint Ann', N'63074', N'MS', CAST(N'1991-07-22' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (16, N'1424684242163317', N'Teresa', N'Atkinson', N'', N'The Citadel Commerce Plaza', N'City Of Commerce', N'90040', N'CA', CAST(N'1969-06-16' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (17, N'9449414999912926', N'Stephen', N'Ayers', N'M.', N'2533 Eureka Rd.', N'Southgate', N'48195', N'MI', CAST(N'1977-02-05' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (18, N'3467864779933190', N'James', N'Bailey', N'B.', N'Southgate Mall', N'Missoula', N'59801', N'MT', CAST(N'1951-09-22' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (19, N'5173177395228560', N'Douglas', N'Baldwin', N'A.', N'Horizon Outlet Center', N'Holland', N'49423', N'MI', CAST(N'1956-10-21' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (20, N'5803456865831636', N'Wayne', N'Banack', N'N.', N'48255 I-10 E. @ Eastpoint Blvd.', N'Baytown', N'77520', N'TX', CAST(N'1997-04-04' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (21, N'3559758088863723', N'Robert', N'Barker', N'L.', N'6789 Warren Road', N'Westland', N'48185', N'MI', CAST(N'1991-04-26' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (22, N'5661006195660685', N'John', N'Beaver', N'A.', N'1318 Lasalle Street', N'Bothell', N'98011', N'WA', CAST(N'2010-09-03' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (23, N'1348679342179396', N'John', N'Beaver', N'A.', N'99300 223rd Southeast', N'Bothell', N'98011', N'WA', CAST(N'1999-09-10' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (24, N'4604176554469235', N'Edna', N'Benson', N'J.', N'Po Box 8035996', N'Dallas', N'75201', N'TX', CAST(N'1963-03-19' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (25, N'2096830686230992', N'Payton', N'Benson', N'P.', N'997000 Telegraph Rd.', N'Southfield', N'48034', N'MI', CAST(N'1952-09-16' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (26, N'7049384184052962', N'Robert', N'Bernacchi', N'M.', N'25915 140th Ave Ne', N'Bellevue', N'98004', N'WA', CAST(N'2000-04-09' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (27, N'6513846185580603', N'Robert', N'Bernacchi', N'M.', N'2681 Eagle Peak', N'Bellevue', N'98004', N'WA', CAST(N'1993-03-13' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (28, N'9955352244295579', N'Matthias', N'Berndt', N'', N'Escondido', N'Escondido', N'92025', N'CA', CAST(N'1974-05-15' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (29, N'3076476034446489', N'Jimmy', N'Bischoff', N'', N'3065 Santa Margarita Parkway', N'Trabuco Canyon', N'92679', N'CA', CAST(N'2015-10-26' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (30, N'3851910963127971', N'Mae', N'Black', N'M.', N'Redford Plaza', N'Redford', N'48239', N'MI', CAST(N'1997-01-03' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (31, N'8388316013059496', N'Donald', N'Blanton', N'L.', N'Corporate Office', N'El Segundo', N'90245', N'CA', CAST(N'2015-05-25' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (32, N'2876373511820517', N'Michael', N'Blythe', N'Greg', N'9903 Highway 6 South', N'Houston', N'77003', N'TX', CAST(N'1989-03-04' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (33, N'2854968334591501', N'Gabriel', N'Bockenkamp', N'L.', N'67 Rainer Ave S', N'Renton', N'98055', N'WA', CAST(N'1976-06-20' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (34, N'1535029745920813', N'Luis', N'Bonifaz', N'', N'72502 Eastern Ave.', N'Bell Gardens', N'90201', N'CA', CAST(N'2012-05-14' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (35, N'9393873267184961', N'Cory', N'Booth', N'K.', N'Eastern Beltway Center', N'Las Vegas', N'89106', N'NV', CAST(N'1974-02-05' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (36, N'2962698650353716', N'Randall', N'Boseman', N'', N'2500 North Stemmons Freeway', N'Dallas', N'75201', N'TX', CAST(N'1999-05-09' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (37, N'9634259252802916', N'Cornelius', N'Brandon', N'L.', N'789 West Alameda', N'Westminster', N'80030', N'CO', CAST(N'1976-02-06' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (38, N'1739219638231403', N'Richard', N'Bready', N'', N'4251 First Avenue', N'Seattle', N'98104', N'WA', CAST(N'1987-11-02' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (39, N'8066843423085262', N'Ted', N'Bremer', N'', N'Bldg. 9n/99298', N'Redmond', N'98052', N'WA', CAST(N'1996-09-12' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (40, N'7894555945990703', N'Alan', N'Brewer', N'', N'4255 East Lies Road', N'Carol Stream', N'60188', N'IL', CAST(N'1997-07-24' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (41, N'8346555388052884', N'Walter', N'Brian', N'J.', N'25136 Jefferson Blvd.', N'Culver City', N'90232', N'CA', CAST(N'1970-07-18' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (42, N'5431321218380767', N'Christopher', N'Bright', N'M.', N'Washington Square', N'Portland', N'97205', N'OR', CAST(N'1988-12-26' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (43, N'8379868179679430', N'Willie', N'Brooks', N'P.', N'Holiday Village Mall', N'Great Falls', N'59401', N'MT', CAST(N'2014-04-28' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (44, N'5781610126752642', N'Jo', N'Brown', N'', N'250000 Eight Mile Road', N'Detroit', N'48226', N'MI', CAST(N'1972-08-12' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (45, N'1762207164073368', N'Robert', N'Brown', N'', N'250880 Baur Blvd', N'Saint Louis', N'63103', N'MS', CAST(N'1980-04-08' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (46, N'2296475500122440', N'Steven', N'Brown', N'B.', N'5500 Grossmont Center Drive', N'La Mesa', N'91941', N'CA', CAST(N'1965-12-01' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (47, N'2815526454443618', N'Mary', N'Browning', N'K.', N'Noah Lane', N'Chicago', N'60610', N'IL', CAST(N'1998-07-11' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (48, N'3630127985378157', N'Michael', N'Brundage', N'', N'22555 Paseo De Las Americas', N'San Diego', N'92102', N'CA', CAST(N'1990-06-28' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (49, N'6051802564643735', N'Shirley', N'Bruner', N'R.', N'4781 Highway 95', N'Sandpoint', N'83864', N'ID', CAST(N'1975-07-02' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (50, N'8095430273331102', N'June', N'Brunner', N'B.', N'678 Eastman Ave.', N'Midland', N'48640', N'MI', CAST(N'1993-07-01' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (51, N'8868236671324304', N'Megan', N'Burke', N'E.', N'Arcadia Crossing', N'Phoenix', N'85004', N'AZ', CAST(N'2008-06-19' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (52, N'7213308298655760', N'Karren', N'Burkhardt', N'K.', N'2502 Evergreen Ste E', N'Everett', N'98201', N'WA', CAST(N'2001-02-27' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (53, N'5953193118414172', N'Linda', N'Burnett', N'E.', N'2505 Gateway Drive', N'North Sioux City', N'57049', N'SD', CAST(N'1965-12-11' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (54, N'2849433021838555', N'Jared', N'Bustamante', N'L.', N'3307 Evergreen Blvd', N'Washougal', N'98671', N'WA', CAST(N'1960-09-19' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (55, N'6354379316633456', N'Barbara', N'Calone', N'J.', N'25306 Harvey Rd.', N'College Station', N'77840', N'TX', CAST(N'1990-08-23' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (56, N'5770945678469399', N'Lindsey', N'Camacho', N'R.', N'S Sound Ctr Suite 25300', N'Lacey', N'98503', N'WA', CAST(N'1995-01-19' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (57, N'7788076120726699', N'Frank', N'Campbell', N'', N'251340 E. South St.', N'Cerritos', N'90703', N'CA', CAST(N'2006-02-18' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (58, N'6440667297285193', N'Henry', N'Campen', N'L.', N'2507 Pacific Ave S', N'Tacoma', N'98403', N'WA', CAST(N'1965-08-24' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (59, N'5927961894613441', N'Chris', N'Cannon', N'', N'Lakewood Mall', N'Lakewood', N'90712', N'CA', CAST(N'2006-06-09' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (60, N'1600293251386187', N'Jane', N'Carmichael', N'N.', N'5967 W Las Positas Blvd', N'Pleasanton', N'94566', N'CA', CAST(N'1977-04-26' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (61, N'4373834693275250', N'Jovita', N'Carmody', N'A.', N'253950 N.E. 178th Place', N'Woodinville', N'98072', N'WA', CAST(N'2012-09-22' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (62, N'7291167247787424', N'Rob', N'Caron', N'', N'Ward Parkway Center', N'Kansas City', N'64106', N'MS', CAST(N'1990-05-21' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (63, N'7587525570853565', N'Andy', N'Carothers', N'', N'566 S. Main', N'Cedar City', N'84720', N'UT', CAST(N'1969-04-07' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (64, N'9194509815355253', N'Donna', N'Carreras', N'F.', N'12345 Sterling Avenue', N'Irving', N'75061', N'TX', CAST(N'2008-09-16' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (65, N'7300713256115448', N'Rosmarie', N'Carroll', N'J.', N'39933 Mission Oaks Blvd', N'Camarillo', N'93010', N'CA', CAST(N'1994-04-06' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (66, N'4724504745714417', N'Raul', N'Casts', N'E.', N'99040 California Avenue', N'Sand City', N'93955', N'CA', CAST(N'1989-07-13' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (67, N'9067415164472812', N'Matthew', N'Cavallari', N'J.', N'North 93270 Newport Highway', N'Spokane', N'99202', N'WA', CAST(N'1952-07-26' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (68, N'8495532758835461', N'Andrew', N'Cencini', N'', N'558 S 6th St', N'Klamath Falls', N'97601', N'OR', CAST(N'1991-01-12' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (69, N'2879717115234870', N'Stacey', N'Cereghino', N'M.', N'220 Mercy Drive', N'Garland', N'75040', N'TX', CAST(N'1967-06-03' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (70, N'7826286708443707', N'Forrest', N'Chandler', N'J.', N'The Quad @ WestView', N'Whittier', N'90605', N'CA', CAST(N'2002-11-06' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (71, N'2613871438037652', N'Lee', N'Chapla', N'J.', N'99433 S. Greenbay Rd.', N'Racine', N'53182', N'WI', CAST(N'1991-06-12' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (72, N'1740349631661494', N'Yao-Qiang', N'Cheng', N'', N'25 N State St', N'Chicago', N'60610', N'IL', CAST(N'1954-05-01' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (73, N'5060790570448357', N'Nicky', N'Chesnut', N'E.', N'9920 North Telegraph Rd.', N'Pontiac', N'48342', N'MI', CAST(N'1966-04-22' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (74, N'1917543354038639', N'Ruth', N'Choin', N'A.', N'7760 N. Pan Am Expwy', N'San Antonio', N'78204', N'TX', CAST(N'1963-07-01' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (75, N'7787371989886596', N'Anthony', N'Chor', N'', N'Riverside', N'Sherman Oaks', N'91403', N'CA', CAST(N'2014-07-27' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (76, N'7531737775650743', N'Pei', N'Chow', N'', N'4660 Rodeo Road', N'Santa Fe', N'87501', N'NM', CAST(N'1979-09-11' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (77, N'6916208166397406', N'Jill', N'Christie', N'J.', N'54254 Pacific Ave.', N'Stockton', N'95202', N'CA', CAST(N'2001-11-20' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (78, N'7759857337450047', N'Alice', N'Clark', N'', N'42500 W 76th St', N'Chicago', N'60610', N'IL', CAST(N'1965-12-06' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (79, N'5274146328977882', N'Connie', N'Coffman', N'L.', N'25269 Wood Dale Rd.', N'Wood Dale', N'60191', N'IL', CAST(N'1993-10-02' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (80, N'9697443115919107', N'John', N'Colon', N'L.', N'77 Beale Street', N'San Francisco', N'94109', N'CA', CAST(N'1999-06-06' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (81, N'9427193450639077', N'Scott', N'Colvin', N'A.', N'25550 Executive Dr', N'Elgin', N'60120', N'IL', CAST(N'1976-04-23' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (82, N'1348075941698008', N'Scott', N'Cooper', N'', N'Pavillion @ Redlands', N'Redlands', N'92373', N'CA', CAST(N'1952-12-20' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (83, N'6690119131897346', N'Eva', N'Corets', N'', N'2540 Dell Range Blvd', N'Cheyenne', N'82001', N'WY', CAST(N'1991-05-16' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (84, N'6742374010070156', N'Marlin', N'Coriell', N'M.', N'99800 Tittabawasee Rd.', N'Saginaw', N'48601', N'MI', CAST(N'1983-03-16' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (85, N'3475568745636135', N'Jack', N'Creasey', N'', N'Factory Merchants', N'Barstow', N'92311', N'CA', CAST(N'2004-05-16' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (86, N'8087162252537012', N'Grant', N'Culbertson', N'', N'399700 John R. Rd.', N'Madison Heights', N'48071', N'MI', CAST(N'1984-01-28' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (87, N'2916273169891521', N'Scott', N'Culp', N'', N'750 Lakeway Dr', N'Bellingham', N'98225', N'WA', CAST(N'1987-07-08' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (88, N'3647882853191232', N'Conor', N'Cunningham', N'', N'Sports Store At Park City', N'Park City', N'84098', N'UT', CAST(N'1990-08-12' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (89, N'1898923728092678', N'Megan', N'Davis', N'N.', N'48995 Evergreen Wy.', N'Everett', N'98201', N'WA', CAST(N'1983-10-14' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (90, N'9629966479962878', N'Alvaro', N'De Matos Miranda Filho', N'', N'Mountain Square', N'Upland', N'91786', N'CA', CAST(N'1962-04-25' AS Date))
INSERT [dbo].[Customers] ([CustomerId], [SSN], [FirstName], [LastName], [MiddleName], [StreetAddress], [City], [ZipCode], [State], [BirthDate]) VALUES (271, N'8706874375267103', N'Caroline', N'Vicknair', N'A.', N'660 Lindbergh', N'Saint Louis', N'63103', N'MS', CAST(N'2007-09-10' AS Date))
SET IDENTITY_INSERT [dbo].[Customers] OFF
SET IDENTITY_INSERT [dbo].[Visits] ON 

INSERT [dbo].[Visits] ([VisitId], [CustomerId], [Date], [Reason], [Treatment], [FollowUpDate]) VALUES (1, 1, CAST(N'2016-01-10' AS Date), N'Headache', N'A nap', NULL)
INSERT [dbo].[Visits] ([VisitId], [CustomerId], [Date], [Reason], [Treatment], [FollowUpDate]) VALUES (2, 1, CAST(N'2016-01-10' AS Date), N'Worse headache', N'A longer nap', NULL)
SET IDENTITY_INSERT [dbo].[Visits] OFF
GO"

    Push-Location
    try {
        Invoke-Sqlcmd -ServerInstance $sqlServer -Username $sqlServerUsername -Password $sqlServerPassword -Database $sqlServerDatabase -Query $sqlQuery -QueryTimeout $sqlTimeoutSeconds -ConnectionTimeout $sqlConnectionTimeoutSeconds
    } catch {
        Write-Warning "Error executing sql command (consider executing manually)`n$($_.Exception)"
    }
    finally {
        # Work around Invoke-Sqlcmd randomly changing the working directory
        Pop-Location
    }
}
