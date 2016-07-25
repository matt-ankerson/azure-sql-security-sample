-- Reset the demo 
ALTER TABLE Customers ALTER COLUMN LastName DROP MASKED
ALTER TABLE Customers ALTER COLUMN MiddleName DROP MASKED
ALTER TABLE Customers ALTER COLUMN StreetAddress DROP MASKED
ALTER TABLE Customers ALTER COLUMN ZipCode DROP MASKED
go

-- Mask Last Name (Exposes only first Letter of Last Name)
ALTER TABLE Customers ALTER COLUMN LastName ADD MASKED WITH (FUNCTION = 'partial(1, "xxxx", 0)')

-- Mask middle initial, street address, and zip code (Fully Masked)
ALTER TABLE Customers ALTER COLUMN MiddleName ADD MASKED WITH (FUNCTION = 'default()')
ALTER TABLE Customers ALTER COLUMN StreetAddress ADD MASKED WITH (FUNCTION = 'default()')
ALTER TABLE Customers ALTER COLUMN ZipCode ADD MASKED WITH (FUNCTION = 'default()')
