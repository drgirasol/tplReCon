#!/usr/local/bin/perl -w

# 
#

use strict;
use warnings;
use Text::CSV;
use DBI;
use Term::ANSIColor;
use Tpl;
use Col;
use Config::General;

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

#
#       Configuration: Preparations
#
#               set defaults
my %defaults;
$defaults{maxldist} = 2;
#               load user settings
my $cfg = Config::General->new(
   -ConfigFile => "settings.cfg",
   -DefaultConfig => \%defaults,
   -MergeDuplicateOptions => "true"
   );
my %config = $cfg->getall;
#
#       Database: Preparations 
#
#               MySQL connection to local database
#
my $dsn = "DBI:mysql:database=".$config{database}{dbname}.";host=".$config{database}{host};
my $dbh = DBI->connect($dsn, $config{database}{user}, $config{database}{dbpass});
#               prepare db querries
my $searchQuery = $dbh->prepare_cached("SELECT * FROM tpldata where genusHybridMarker = '' and genus = ? and species = ? and speciesHybridMarker = ? and infraspecificRank = ? and infraspecificEpithet = ? order by status");
my $infraSpecificQuery = $dbh->prepare_cached("SELECT * FROM tpldata where genusHybridMarker = '' and genus = ? and species = ? and infraspecificRank != ''");
my $infraGenericQuery = $dbh->prepare_cached("SELECT * FROM tpldata where genusHybridMarker = '' and genus = ? and infraspecificRank = ''");
my $byIdQuery = $dbh->prepare_cached("SELECT * FROM tpldata where tplId = ?");

#
#       Output: Preparations
#
my $csv = Text::CSV->new ( { 
   binary => 1,
   sep_char => ';', 
   always_quote => 1
   } )  # should set binary attribute.
                 or die "Cannot use CSV: ".Text::CSV->error_diag ();
$csv->eol ("\n");
#
#       Output (CSV): Taxonomic Status Overview
#
my $outFile = $testFile."_TPL_NameCheck.csv";
my @csv_header = ("Family","Genus","Taxon","Alternative","Source","SourceId","Status","Accepted","Additionals");
my $csvHeaderRef = \@csv_header;
open my $fh, ">:encoding(utf8)", $outFile or die "$outFile $!";
$csv->print ($fh, $csvHeaderRef);
#
#       Output (CSV): Ambiguity Details
#
my $ambFile = $testFile."_TPL_Ambiguities.csv";
my @csv_header = ("oTaxon","Accepted","Synonym","Unresolved","Misapplied");
my $csvHeaderRef = \@csv_header;
open my $fh2, ">:encoding(utf8)", $ambFile or die "$ambFile $!";
$csv->print ($fh2, $csvHeaderRef); 
#
#       Input: Open
#
open(my $data2, '<', $testFile) or die "Could not open '$testFile' $!\n";
my %tax;

while (my $line = <$data2>) {
     
  $tax{"Source"} = "TPL";
  $tax{"SourceId"} = "NA";
  $tax{"Status"} = "NA";
  $tax{"Accepted"} = "NA";
  $tax{"Alternative"} = "";
  
    
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
      unless ($tplEntry->{species} ne "")
      {
         next;
      }     
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
         print colored($ref->{status}, 'bold yellow on_black');
         if ($ref->{status} eq "Synonym" || $ref->{status} eq "Misapplied")
         {
            $tax{"SourceId"} = $ref->{tplId};
            my $tplAccepted = getTPLaccepted($ref->{acceptedId}, $byIdQuery);
            if (defined($tplAccepted))
            {
               $tax{"Accepted"} = $tplAccepted;               
            }
         } else {
            $tax{"SourceId"} = $ref->{tplId};
            if ($ref->{status} eq "Accepted")
            {
               $tax{"Accepted"} = $taxon;
            }
         }         
      } else {
         if ($searchQuery->rows > 1)
         {
            my $multiCheck = evaluateMultiExactHits($searchQuery);
            $tax{"Status"} = $multiCheck->{status};
            $tax{"SourceId"} = $multiCheck->{tplId};
            $tax{"Alternative"} = $multiCheck->{alternative};
            %ambNames = %{$multiCheck->{ambNames}};
            print colored($tax{"Status"}, 'bold yellow on_black');
         } else
         {        
            # if no match was found using TPL exact match search...
            #
            # evaluate all infraspecific names if supplied name has infraspecific rank
            if ($tplEntry->{infraspecificRank} ne "")
            {
               # check infraspecific entities
               $infraSpecificQuery->execute($tplEntry->{genus}, $tplEntry->{species});
               if ($infraSpecificQuery->rows > 0)
               {                                
                  my $hierarchyResult = evaluateHierarchy($taxon, $infraSpecificQuery, $config{maxldist}, $byIdQuery);
                  if (defined($hierarchyResult))
                  {
                     $tax{"Status"} = $hierarchyResult->{status};
                     $tax{"Accepted"} = $hierarchyResult->{accepted};
                     $tax{"SourceId"} = $hierarchyResult->{tplId};
                     $tax{"Alternative"} = $hierarchyResult->{alternative};
                     print colored($tax{"Status"}, 'bold cyan on_black')." | ".$tax{"Alternative"};
                  } else
                  {
                     print colored("NA (TPL)", 'bold red on_black');
                     my $colReConResult = colReCon($tplEntry, $taxon, $config{maxldist});
                     
                     if (defined($colReConResult))
                     {
                        $tax{"Status"} = $colReConResult->{status};
                        $tax{"Accepted"} = $colReConResult->{accepted};
                        $tax{"Alternative"} = $colReConResult->{alternative};
                        $tax{"SourceId"} = $colReConResult->{sourceId};
                        $tax{"Source"} = $colReConResult->{source};
                        print colored($tax{"Status"}." (COL)", 'bold cyan on_black');
                     } else                     
                     {                                                                
                        print colored("NA (COL)", 'bold red on_black');
                     }
                  }
               } else
               {
                     print colored("NA (TPL)", 'bold red on_black');
                     my $colReConResult = colReCon($tplEntry, $taxon, $config{maxldist});
                     
                     if (defined($colReConResult))
                     {
                        $tax{"Status"} = $colReConResult->{status};
                        $tax{"Accepted"} = $colReConResult->{accepted};
                        $tax{"Alternative"} = $colReConResult->{alternative};
                        $tax{"SourceId"} = $colReConResult->{sourceId};
                        $tax{"Source"} = $colReConResult->{source};
                        print colored($tax{"Status"}." (COL)", 'bold cyan on_black');
                     } else                     
                     {                                                                
                        print colored("NA (COL)", 'bold red on_black');
                     }                 
               }
            } else 
            {
               # check speciesHybridMarker
               my $hybridAlternative;
               if ($tplEntry->{speciesHybridMarker} eq "")
               {
                  # check if name exists with speciesHybridMarker
                  $searchQuery->execute($tplEntry->{genus}, $tplEntry->{species}, "x", $tplEntry->{infraspecificRank}, $tplEntry->{infraspecificEpithet});
                  $hybridAlternative = join(" ", ($tplEntry->{genus}, "x", $tplEntry->{species}));
               } elsif ($tplEntry->{speciesHybridMarker} eq "x")
               {
                  # check if name exists without speciesHybridMarker
                  $searchQuery->execute($tplEntry->{genus}, $tplEntry->{species}, "", $tplEntry->{infraspecificRank}, $tplEntry->{infraspecificEpithet});
                  $hybridAlternative = join(" ", ($tplEntry->{genus}, $tplEntry->{species}));
               }
               if ($searchQuery->rows > 0)
               {
                     if ($searchQuery->rows == 1)
                     {         
                        my $ref = $searchQuery->fetchrow_hashref();
                        $tax{"Status"} = $ref->{status};         
                        $tax{"Alternative"} = $hybridAlternative;
                        print colored($tax{"Status"}, 'bold cyan on_black')." | ".$hybridAlternative;
                        if ($ref->{status} eq "Synonym" || $ref->{status} eq "Misapplied")
                        {
                           $tax{"SourceId"} = $ref->{tplId};
                           my $tplAccepted = getTPLaccepted($ref->{acceptedId}, $byIdQuery);
                           if (defined($tplAccepted))
                           {
                              $tax{"Accepted"} = $tplAccepted;               
                           }
                        } else {
                           $tax{"SourceId"} = $ref->{tplId};
                           if ($ref->{status} eq "Accepted")
                           {
                              $tax{"Accepted"} = $taxon;
                           }
                        }         
                     } else {
                        my $multiCheck = evaluateMultiExactHits($searchQuery);
                        $tax{"Status"} = $multiCheck->{status};
                        $tax{"SourceId"} = $multiCheck->{tplId};
                        $tax{"Alternative"} = $multiCheck->{alternative};                        
                        print colored($tax{"Status"}, 'bold cyan on_black');
                     }
               } else
               {
                  # check infrageneric entities
                  $infraGenericQuery->execute($tplEntry->{genus});                  
                  if ($infraGenericQuery->rows > 0)
                  {
                     my $hierarchyResult = evaluateHierarchy($taxon, $infraGenericQuery, $config{maxldist}, $byIdQuery);
                     if (defined($hierarchyResult))
                     {
                        $tax{"Status"} = $hierarchyResult->{status};
                        $tax{"Accepted"} = $hierarchyResult->{accepted};
                        $tax{"SourceId"} = $hierarchyResult->{tplId};
                        $tax{"Alternative"} = $hierarchyResult->{alternative};
                        print colored($tax{"Status"}, 'bold cyan on_black')." | ".$tax{"Alternative"};
                     } else
                     {
                        print colored("NA (TPL)", 'bold red on_black');
                        my $colReConResult = colReCon($tplEntry, $taxon, $config{maxldist});
                        
                        if (defined($colReConResult))
                        {
                           $tax{"Status"} = $colReConResult->{status};
                           $tax{"Accepted"} = $colReConResult->{accepted};
                           $tax{"Alternative"} = $colReConResult->{alternative};
                           $tax{"SourceId"} = $colReConResult->{sourceId};
                           $tax{"Source"} = $colReConResult->{source};
                           print colored($tax{"Status"}." (COL)", 'bold cyan on_black');
                        } else                     
                        {                                                                
                           print colored("NA (COL)", 'bold red on_black');
                        }
                     }
                  } else
                  {
                     print colored("NA (TPL)", 'bold red on_black');
                     my $colReConResult = colReCon($tplEntry, $taxon, $config{maxldist});
                     
                     if (defined($colReConResult))
                     {
                        $tax{"Status"} = $colReConResult->{status};
                        $tax{"Accepted"} = $colReConResult->{accepted};
                        $tax{"Alternative"} = $colReConResult->{alternative};
                        $tax{"SourceId"} = $colReConResult->{sourceId};
                        $tax{"Source"} = $colReConResult->{source};
                        print colored($tax{"Status"}." (COL)", 'bold cyan on_black');
                     } else                     
                     {                                                                
                        print colored("NA (COL)", 'bold red on_black');
                     }                             
                  }
               }
            }                        
         }
      }
      print "\n";
      my @columns = ($family,$tplEntry->{genus},$taxon,$tax{"Alternative"},$tax{"Source"},$tax{"SourceId"},$tax{"Status"},$tax{"Accepted"});
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
