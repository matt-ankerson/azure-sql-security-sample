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
                        Customers_CustomerId = c.Int(nullable: false),
                    })
                .PrimaryKey(t => new { t.ApplicationUser_Id, t.Customers_CustomerId })
                .ForeignKey("dbo.AspNetUsers", t => t.ApplicationUser_Id, cascadeDelete: true)
                .ForeignKey("dbo.Customers", t => t.Customers_CustomerId, cascadeDelete: true)
                .Index(t => t.ApplicationUser_Id)
                .Index(t => t.Customers_CustomerId);
            
        }
        
        public override void Down()
        {
            DropForeignKey("dbo.ApplicationUserCustomers", "Customers_CustomerId", "dbo.Customers");
            DropForeignKey("dbo.ApplicationUserCustomers", "ApplicationUser_Id", "dbo.AspNetUsers");
            DropIndex("dbo.ApplicationUserCustomers", new[] { "Customers_CustomerId" });
            DropIndex("dbo.ApplicationUserCustomers", new[] { "ApplicationUser_Id" });
            DropTable("dbo.ApplicationUserCustomers");
        }
    }
}
