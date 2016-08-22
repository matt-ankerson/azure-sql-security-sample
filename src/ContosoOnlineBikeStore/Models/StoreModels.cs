using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.ComponentModel.DataAnnotations.Schema;
using System.ComponentModel.DataAnnotations;
using Microsoft.Owin.Security.Provider;

namespace ContosoOnlineBikeStore.Models
{
    public class Customer
    {
        public Customer() { }

        public int CustomerId { get; set; }

        [StringLength(11)]
        [Column(TypeName = "char")]
        [Required]
        [Display(Name = "Credit Card No.")]
        public string SSN { get; set; }

        [StringLength(50)]
        [Display(Name = "First Name")]
        public string FirstName { get; set; }

        [StringLength(50)]
        [Required]
        [Display(Name = "Last Name")]
        public string LastName { get; set; }

        [StringLength(50)]
        [Display(Name = "Middle Name")]
        public string MiddleName { get; set; }

        [StringLength(50)]
        [Required]
        [Display(Name = "Address")]
        public string StreetAddress { get; set; }

        [StringLength(50)]
        [Required]
        public string City { get; set; }

        [StringLength(5)]
        [Column(TypeName = "char")]
        [Required]
        [Display(Name = "Zip Code")]
        public string ZipCode { get; set; }

        [StringLength(2)]
        [Column(TypeName = "char")]
        [Required]
        public string State { get; set; }

        [Column(TypeName = "date")]
        [Required]
        [Display(Name = "Birth Date")]
        public System.DateTime BirthDate { get; set; }

        public string FormattedBirthDate => BirthDate.ToString("MM/dd/yyyy");

        public virtual ICollection<Visit> Visits { get; set; }
        public virtual ICollection<ApplicationUser> ApplicationUsers { get; set; }
    }

    public class Visit
    {
        public int VisitId { get; set; }

        [Required]
        public int CustomerId { get; set; }

        [Column(TypeName = "date")]
        [Required]
        public System.DateTime Date { get; set; }

        [StringLength(4000)]
        [Required]
        public string Reason { get; set; }

        [StringLength(4000)]
        [Required]
        public string Treatment { get; set; }
        [Column(TypeName = "date")]
        public Nullable<System.DateTime> FollowUpDate { get; set; }

        [ForeignKey("CustomerId")]
        public virtual Customer Customer { get; set; }
    }
}