namespace ContosoOnlineBikeStore.Migrations
{
    using System;
    using System.Data.Entity.Migrations;
    
    public partial class Visits : DbMigration
    {
        public override void Up()
        {
            CreateTable(
                "dbo.Visits",
                c => new
                    {
                        VisitID = c.Int(nullable: false, identity: true),
                        CustomerID = c.Int(nullable: false),
                        Date = c.DateTime(nullable: false, storeType: "date"),
                        Reason = c.String(maxLength: 4000),
                        Treatment = c.String(maxLength: 4000),
                        FollowUpDate = c.DateTime(storeType: "date"),
                    })
                .PrimaryKey(t => t.VisitID)
                .ForeignKey("dbo.Customers", t => t.CustomerID, cascadeDelete: true)
                .Index(t => t.CustomerID);
            
        }
        
        public override void Down()
        {
            DropForeignKey("dbo.Visits", "CustomerID", "dbo.Customers");
            DropIndex("dbo.Visits", new[] { "CustomerID" });
            DropTable("dbo.Visits");
        }
    }
}
