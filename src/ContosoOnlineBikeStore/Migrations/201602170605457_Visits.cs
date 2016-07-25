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
                        VisitId = c.Int(nullable: false, identity: true),
                        CustomerId = c.Int(nullable: false),
                        Date = c.DateTime(nullable: false, storeType: "date"),
                        Reason = c.String(maxLength: 4000),
                        Treatment = c.String(maxLength: 4000),
                        FollowUpDate = c.DateTime(storeType: "date"),
                    })
                .PrimaryKey(t => t.VisitId)
                .ForeignKey("dbo.Customers", t => t.CustomerId, cascadeDelete: true)
                .Index(t => t.CustomerId);
            
        }
        
        public override void Down()
        {
            DropForeignKey("dbo.Visits", "CustomerId", "dbo.Customers");
            DropIndex("dbo.Visits", new[] { "CustomerId" });
            DropTable("dbo.Visits");
        }
    }
}
