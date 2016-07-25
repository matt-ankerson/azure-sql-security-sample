namespace ContosoOnlineBikeStore.Migrations
{
    using System;
    using System.Data.Entity.Migrations;
    
    public partial class Nullability : DbMigration
    {
        public override void Up()
        {
            AlterColumn("dbo.Customers", "SSN", c => c.String(nullable: false, maxLength: 11, fixedLength: true, unicode: false));
            AlterColumn("dbo.Customers", "LastName", c => c.String(nullable: false, maxLength: 50));
            AlterColumn("dbo.Customers", "StreetAddress", c => c.String(nullable: false, maxLength: 50));
            AlterColumn("dbo.Customers", "City", c => c.String(nullable: false, maxLength: 50));
            AlterColumn("dbo.Customers", "ZipCode", c => c.String(nullable: false, maxLength: 5, fixedLength: true, unicode: false));
            AlterColumn("dbo.Customers", "State", c => c.String(nullable: false, maxLength: 2, fixedLength: true, unicode: false));
            AlterColumn("dbo.Visits", "Reason", c => c.String(nullable: false, maxLength: 4000));
            AlterColumn("dbo.Visits", "Treatment", c => c.String(nullable: false, maxLength: 4000));
        }
        
        public override void Down()
        {
            AlterColumn("dbo.Visits", "Treatment", c => c.String(maxLength: 4000));
            AlterColumn("dbo.Visits", "Reason", c => c.String(maxLength: 4000));
            AlterColumn("dbo.Customers", "State", c => c.String(maxLength: 2, fixedLength: true, unicode: false));
            AlterColumn("dbo.Customers", "ZipCode", c => c.String(maxLength: 5, fixedLength: true, unicode: false));
            AlterColumn("dbo.Customers", "City", c => c.String(maxLength: 50));
            AlterColumn("dbo.Customers", "StreetAddress", c => c.String(maxLength: 50));
            AlterColumn("dbo.Customers", "LastName", c => c.String(maxLength: 50));
            AlterColumn("dbo.Customers", "SSN", c => c.String(maxLength: 11, fixedLength: true, unicode: false));
        }
    }
}
