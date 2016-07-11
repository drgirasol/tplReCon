#!/usr/local/bin/perl -w

# 
#

use strict;
use warnings;
use Text::CSV;
use DBI;
use Term::ANSIColor;
use Tpl;

(my $testFile) = @ARGV;

if (!defined($testFile)) { 
   if (!defined($testFile))
   {
      die "No testfile file defined!";
   }
}
binmode(STDOUT, ":utf8");
my $start_run = time();
print "Test File: ".$testFile."\n";

# MySQL connection to local database

my $dsn = "DBI:mysql:database=dbName;host=localhost";
my $dbh = DBI->connect($dsn, "dbUser", "dbPassword");

my $csv = Text::CSV->new ( { 
   binary => 1,
   sep_char => ';', 
   always_quote => 1
   } )  # should set binary attribute.
                 or die "Cannot use CSV: ".Text::CSV->error_diag ();
$csv->eol ("\n");
#
#       Taxonomic Status Overview
#
my $outFile = $testFile."_TPL_NameCheck.csv";
my @csv_header = ("Family","Genus","Taxon","SourceId","Status","Exception","Additionals");
my $csvHeaderRef = \@csv_header;
open my $fh, ">:encoding(utf8)", $outFile or die "$outFile $!";
$csv->print ($fh, $csvHeaderRef);
#
#       Ambiguity Details
#
my $ambFile = $testFile."_TPL_Ambiguities.csv";
my @csv_header = ("oTaxon","Accepted","Synonym","Unresolved","Misapplied");
my $csvHeaderRef = \@csv_header;
open my $fh2, ">:encoding(utf8)", $ambFile or die "$ambFile $!";
$csv->print ($fh2, $csvHeaderRef); 
 
open(my $data2, '<', $testFile) or die "Could not open '$testFile' $!\n";
my %tax;

my $searchQuery = $dbh->prepare_cached("SELECT * FROM tpldata where genusHybridMarker = '' and genus = ? and species = ? and speciesHybridMarker = ? and infraspecificRank = ? and infraspecificEpithet = ? order by status");
my $synonymQuery = $dbh->prepare_cached("SELECT * FROM tpldata where acceptedId = ?");
while (my $line = <$data2>) {
     
  $tax{"SourceId"} = 0;
  $tax{"Status"} = "NA";
  $tax{"Exception"} = "NA";  
    
  chomp $line;
  $line =~ s/^\s+//;
  $line =~ s/\s+$//;
  
  my @lineSplits = split(";",$line);  
  #
  # 
  # 
  if (@lineSplits > 1)
  {  
      my $family = shift(@lineSplits);
      my $taxon = shift(@lineSplits);      
      my $tplEntry = buildTPLentry($taxon);
            
      my %ambNames;
      $ambNames{Accepted} = [ () ];
      $ambNames{Synonym} = [ () ];
      $ambNames{Unresolved} = [ () ];
      $ambNames{Misapplied} = [ () ];
      print "\n\tCheck TPL database for $taxon: ";      
      $searchQuery->execute($tplEntry->{genus}, $tplEntry->{species}, $tplEntry->{speciesHybridMarker}, $tplEntry->{infraspecificRank}, $tplEntry->{infraspecificEpithet});
      if ($searchQuery->rows == 1)
      {         
         my $ref = $searchQuery->fetchrow_hashref();
         $tax{"Status"} = $ref->{status};         
         print colored($ref->{status}, 'bold yellow on_black')." | ";
         if ($ref->{status} eq "Synonym")
         {
            $tax{"SourceId"} = $ref->{acceptedId};
         } else {
            $tax{"SourceId"} = $ref->{tplId};
         }         
      } else {
         if ($searchQuery->rows > 1)
         {
            my @statList;
            my %amb_stats;
            my $amb_acc_uid;
            my %amb_accIds;
            while (my $stati = $searchQuery->fetchrow_hashref())
            {      
               push($ambNames{$stati->{status}}, buildTaxonName($stati,1));
               if (defined($amb_stats{$stati->{status}}))
               {
                  $amb_stats{$stati->{status}}++;
               } else
               {
                  $amb_stats{$stati->{status}} = 1;
                  $amb_acc_uid = $stati->{tplId};
               }
               if ($stati->{acceptedId} ne "")
               {
                    $amb_accIds{$stati->{acceptedId}} = 1;
               }
            }
            my @amb_stats_keys = keys %amb_stats;
            my @amb_stat_accIds = keys %amb_accIds;
            if (@amb_stats_keys == 1 && @amb_stat_accIds == 1)
            {
                $tax{"Status"} = $amb_stats_keys[0];
                $tax{"SourceId"} = $amb_stat_accIds[0];
            } else
            {
                foreach my $statKey (@amb_stats_keys)
                {
                   push(@statList, "$statKey (".$amb_stats{$statKey}.")");
                }
                $tax{"Status"} = "Ambiguous [".join(",",@statList)."]";
                print colored($tax{"Status"}, 'bold red on_black');
                if (defined($amb_stats{"Accepted"}))
                {
                   if ($amb_stats{"Accepted"} == 1)
                   {
                      $tax{"SourceId"} = $amb_acc_uid;                      
                   }
                }
            }

         } else
         {
            print colored("NA", 'bold red on_black');
         }
      }
      print "\n";
      my @columns = ($family,$tplEntry->{genus},$taxon,$tax{"SourceId"},$tax{"Status"},$tax{"Exception"});
      push(@columns, @lineSplits);
      $csv->print ($fh, \@columns);
      if (@{$ambNames{Accepted}} > 0 || @{$ambNames{Synonym}} > 0 || @{$ambNames{Unresolved}} > 0 || @{$ambNames{Misapplied}} > 0)
      {
         my @columns = ($taxon, join("|",@{$ambNames{Accepted}}), join("|",@{$ambNames{Synonym}}), join("|",@{$ambNames{Unresolved}}), join("|",@{$ambNames{Misapplied}}));
         $csv->print ($fh2, \@columns);
      }      
  } else  
  {
     die("Line with less than 3 fields");
  }  
}
my $end_run = time();
my $run_time = ($end_run - $start_run) / 60;
print "\n\nScript runtime: $run_time minutes.";
close $fh or die "$outFile: $!";
close $fh2 or die "$ambFile: $!";