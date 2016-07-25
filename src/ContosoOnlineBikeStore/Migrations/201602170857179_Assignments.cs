namespace ContosoOnlineBikeStore.Migrations
{
    using System;
    using System.Data.Entity.Migrations;
    
    public partial class Assignments : DbMigration
    {
        public override void Up()
        {
            CreateTable(
                "dbo.ApplicationUserCustomers",
                c => new
                    {
                        ApplicationUser_Id = c.String(nullable: false, maxLength: 128),
                        Customers_CustomerID = c.Int(nullable: false),
                    })
                .PrimaryKey(t => new { t.ApplicationUser_Id, t.Customers_CustomerID })
                .ForeignKey("dbo.AspNetUsers", t => t.ApplicationUser_Id, cascadeDelete: true)
                .ForeignKey("dbo.Customers", t => t.Customers_CustomerID, cascadeDelete: true)
                .Index(t => t.ApplicationUser_Id)
                .Index(t => t.Customers_CustomerID);
            AddForeignKey("dbo.Customer", "CustomerID", "dbo.Visit", "CustomerID");
            
        }
        
        public override void Down()
        {
            DropForeignKey("dbo.ApplicationUserCustomers", "Customers_CustomerID", "dbo.Customers");
            DropForeignKey("dbo.ApplicationUserCustomers", "ApplicationUser_Id", "dbo.AspNetUsers");
            DropIndex("dbo.ApplicationUserCustomers", new[] { "Customers_CustomerID" });
            DropIndex("dbo.ApplicationUserCustomers", new[] { "ApplicationUser_Id" });
            DropTable("dbo.ApplicationUserCustomers");
            DropForeignKey("dbo.Customer", "CustomerID", "dbo.Visit");
        }
    }
}
