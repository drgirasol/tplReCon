package Tpl;
use strict;
use warnings;
use Exporter;
use Term::ANSIColor;
use Text::Levenshtein qw(distance);

our @ISA= qw( Exporter );

# these CAN be exported.
our @EXPORT_OK = qw( evaluateMultiExactHits evaluateHierarchy buildTPLentry buildTaxonName);

# these are exported by default.
our @EXPORT = qw( evaluateMultiExactHits evaluateHierarchy buildTPLentry buildTaxonName);

sub buildTaxonName {
	my $row_hashref = shift(@_);
	my $useAuthor = shift(@_);
	my @taxonName = ();
	push(@taxonName, $row_hashref->{genus});
	unless ($row_hashref->{speciesHybridMarker} eq "")
	{
		push(@taxonName,$row_hashref->{speciesHybridMarker});
	}
	push(@taxonName, $row_hashref->{species});
	unless ($row_hashref->{infraspecificRank} eq "")
	{
		push(@taxonName, $row_hashref->{infraspecificRank});
		push(@taxonName, $row_hashref->{infraspecificEpithet});
	}
	if (defined($useAuthor))
	{
		push(@taxonName, $row_hashref->{authorship});
	}
	return join(" ", @taxonName);
}
sub buildTPLentry {
	my $taxon = shift(@_);
	my @taxaSplit = split(" ",$taxon);
	if (@taxaSplit > 0)
	{
	   my $genus = $taxaSplit[0];
	   my $speciesHybridMarker = "";
	   my $infraspecificRank = "";
	   my $infraspecificEpithet = "";
	   my $species = "";
	   if (@taxaSplit > 2)
	   {	   	
               if ($taxaSplit[1] eq "x")
               {
	          $speciesHybridMarker = "x";
	          $species = $taxaSplit[2];
               } elsif ($taxaSplit[2] =~ /ssp\.|subsp\./)
               {
		  $species = $taxaSplit[1];
		  $infraspecificRank = "subsp.";
		  $infraspecificEpithet = $taxaSplit[3];
               } elsif ($taxaSplit[2] =~ /var\./)
               {
	          $species = $taxaSplit[1];
		  $infraspecificRank = "var.";
		  $infraspecificEpithet = $taxaSplit[3];
               } elsif ($taxaSplit[2] =~ /f\./)
               {
	          $species = $taxaSplit[1];
		  $infraspecificRank = "f.";
		  $infraspecificEpithet = $taxaSplit[3];
               }
            } elsif (@taxaSplit == 2)
            {
            	$species = $taxaSplit[1];
            }
            return ({genus => $genus, species => $species, speciesHybridMarker => $speciesHybridMarker, infraspecificRank => $infraspecificRank, infraspecificEpithet => $infraspecificEpithet});
         } else
         {
         	die("Error: buildTPLentry failed!");
         }
}
sub evaluateMultiExactHits {	
	my $queryResult = shift(@_);
	my %stati;
	my $alternative;
	my $tplId = "";
	my @synTplIds = ();
	
	while (my $dbRow = $queryResult->fetchrow_hashref())
	{
		unless (defined($alternative))
		{
			$alternative = buildTaxonName($dbRow);
		}
		$stati{$dbRow->{status}} = 1;
		if ($dbRow->{status} eq "Accepted") # || $dbRow->{status} eq "Unresolved")
		{
			$tplId = $dbRow->{tplId};
		} elsif ($dbRow->{status} eq "Synonym" || $dbRow->{status} eq "Misapplied")
		{
			push(@synTplIds,$dbRow->{acceptedIds});
		}
	}
	
	if ((keys %stati) > 1)
	{
		# more than one status type => ambiguous status
		# if an accepted name is included return its ID
		return ($alternative, "Ambiguous", $tplId);
	} elsif ((keys %stati) > 0)
	{
		my @status = keys %stati;
		if ($status[0] eq "Synonym")
		{
			$tplId = join("|",@synTplIds);
		}
		return ($alternative, $status[0], $tplId);
	}
}
sub evaluateHierarchy {
	my $taxon = shift(@_);
	my $queryResult = shift(@_);
	my @closeMatches;		             
	my %tax;
	
	while (my $dbRow = $queryResult->fetchrow_hashref())
	{
	   my $testAlternative = join(" ", ($dbRow->{genus},$dbRow->{species},$dbRow->{infraspecificRank},$dbRow->{infraspecificEpithet}));               
	   $testAlternative =~ s/\s+$//;
	   
	   my $curAccId;
	   if ($dbRow->{status} eq "Synonym" || $dbRow->{status} eq "Misapplied")
	   {
		$curAccId = $dbRow->{acceptedId};
	   } else
	   {
	    	$curAccId = $dbRow->{tplId};
	   }
	   
	   my $curDist;
	   if ($taxon =~ /subsp\.|var\.|f\./)
	   {
		my $rRtaxon = $taxon;
		$rRtaxon =~ s/\ssubsp\.|\svar\.|\sf\.//;
		my $rRtestAlternative = $testAlternative;
		$rRtestAlternative =~ s/\ssubsp\.|\svar\.|\sf\.//;			
		$curDist = distance($rRtestAlternative,$rRtaxon);
	   } else
	   {
		$curDist = distance($testAlternative,$taxon);
	   }
	   	   
	   if ($curDist < 3)
	   {                  			
		push(@closeMatches, { tplId => $dbRow->{tplId}, taxon => $testAlternative, distance => $curDist, status => $dbRow->{status}, accId => $curAccId, data => $dbRow });
		print colored("\n\t\t -| $taxon =?= $testAlternative ($curDist)",'bold yellow on_black');
	   } else
	   {
		#print colored("\n\t\t -| $taxon =?= $testAlternative ($curDist)",'bold red on_black');
	   }
	}
	print "\n";
	
	if (@closeMatches > 0)
	{
		my @sorted = sort { $a->{distance} <=> $b->{distance} } @closeMatches;
		my @altNames;
		my %uniqueAltNames;
			
		foreach my $result (@sorted)
		{
			unless (defined($uniqueAltNames{$result->{taxon}}))
			{
				push(@altNames, $result->{taxon});
				$uniqueAltNames{$result->{taxon}} = 1;
			}
		}

		# if there is more than one alternative...
		if (@sorted > 1)
		{
			# if the closest match (first element) is a perfect match OR if the closest match has distance 1 and any other match is more distant (=2)...
			if ($sorted[0]->{distance} == 0 || ($sorted[0]->{distance} == 1 && $sorted[1]->{distance} > 1))
			{
				$tax{"Alternative"} = $sorted[0]->{taxon};
				$tax{"Status"} = $sorted[0]->{status};
				$tax{"SourceId"} = $sorted[0]->{accId};
			# in any other case, we count the result as ambiguous...
			} else
			{
				$tax{"Status"} = "Ambiguous (".scalar(@altNames).")";
				$tax{"Alternative"} = join(",",@altNames);
			}
		# if there is exactly one alternative...
		} else
		{
			$tax{"Alternative"} = $sorted[0]->{taxon};
			$tax{"Status"} = $sorted[0]->{status};
			$tax{"SourceId"} = $sorted[0]->{accId};      
		}    
		return ($tax{"Alternative"}, $tax{"SourceId"}, $tax{"Status"});
	} else
	{
		return ();
	}
}

1;