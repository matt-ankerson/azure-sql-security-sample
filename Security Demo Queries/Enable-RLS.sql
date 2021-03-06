-- If repeating the demo on the same installation, Reset 
DROP SECURITY POLICY IF EXISTS Security.customerSecurityPolicy
DROP FUNCTION IF EXISTS Security.customerAccessPredicate
DROP SCHEMA IF EXISTS Security
go

-- Observe existing schema
SELECT * FROM Customers
go

-- Observe the mapping table, which assigns customers to application users
-- We'll use RLS to ensure that application users can only access customers assigned to them
SELECT * FROM ApplicationUserCustomers
go


-- Create separate schema for RLS objects
-- (not required, but best practice to limit access)
CREATE SCHEMA Security
go


-- Create predicate function for RLS
-- This determines which users can access which rows
CREATE FUNCTION Security.customerAccessPredicate(@CustomerID int)
	RETURNS TABLE
	WITH SCHEMABINDING
AS
	RETURN SELECT 1 AS isAccessible
	FROM dbo.ApplicationUserCustomers
	WHERE 
	(
		-- application users can access only customers assigned to them
		Customer_CustomerID = @CustomerID
		AND ApplicationUser_Id = CAST(SESSION_CONTEXT(N'UserId') AS nvarchar(128)) 
	)
	OR 
	(
		-- DBAs can access all customers
		IS_MEMBER('db_owner') = 1
	)
go

-- Create security policy that adds this function as a security predicate on the Customers and Visits tables
-- Filter predicates filter out customers who shouldn't be accessible by the current user
-- Block predicates prevent the current user from inserting any customers who aren't mapped to the user
CREATE SECURITY POLICY Security.customerSecurityPolicy
	ADD FILTER PREDICATE Security.customerAccessPredicate(CustomerID) ON dbo.Customers,
	ADD BLOCK PREDICATE Security.customerAccessPredicate(CustomerID) ON dbo.Customers,
	ADD FILTER PREDICATE Security.customerAccessPredicate(CustomerID) ON dbo.Visits,
	ADD BLOCK PREDICATE Security.customerAccessPredicate(CustomerID) ON dbo.Visits
go
