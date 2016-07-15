package Tpl;
use strict;
use warnings;
use Exporter;
use Term::ANSIColor;
use Text::Levenshtein qw(distance);

our @ISA= qw( Exporter );

# these CAN be exported.
our @EXPORT_OK = qw( evaluateMultiExactHits evaluateHierarchy buildTPLentry buildTaxonName getTPLaccepted);

# these are exported by default.
our @EXPORT = qw( evaluateMultiExactHits evaluateHierarchy buildTPLentry buildTaxonName getTPLaccepted);

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
sub getTPLaccepted
{
	my $acceptedId = shift(@_);	
	my $query = shift(@_);
	my $accepted;
	$query->execute($acceptedId);	
	if ($query->rows > 0)
	{
		  my $ref = $query->fetchrow_hashref();
		  $accepted = buildTaxonName($ref);
	}		
	return $accepted;
}
sub evaluateMultiExactHits 
{	
	my $queryResult = shift(@_);
	
	my $taxonName;
	my $tplId = "NA";
	my $status = "NA";
	my $alternative = "";
	
	my %ambNames;

	$ambNames{Accepted} = [ () ];
	$ambNames{Synonym} = [ () ];
	$ambNames{Unresolved} = [ () ];
	$ambNames{Misapplied} = [ () ];
	
	my %ambIds;
	
	$ambIds{Accepted} = [ () ];
	$ambIds{Synonym} = [ () ];
	$ambIds{Unresolved} = [ () ];
	$ambIds{Misapplied} = [ () ];
	
	while (my $dbRow = $queryResult->fetchrow_hashref())
	{
		push($ambNames{$dbRow->{status}}, buildTaxonName($dbRow,1));
		push($ambIds{$dbRow->{status}}, $dbRow->{tplId});		
		unless (defined($taxonName))
		{
			$taxonName = buildTaxonName($dbRow);
		}
	}
	if (@{$ambIds{Accepted}} == 1)
	{
		$tplId = @{$ambIds{Accepted}}[0];
	}
	if ( @{$ambIds{Accepted}}+@{$ambIds{Synonym}}+@{$ambIds{Unresolved}}+@{$ambIds{Misapplied}} > 1 )
	{
		$status = "Ambiguous (".scalar @{$ambIds{Accepted}}+@{$ambIds{Synonym}}+@{$ambIds{Unresolved}}+@{$ambIds{Misapplied}}.")";
		$alternative = join(";", (@{$ambNames{Accepted}},@{$ambNames{Synonym}},@{$ambNames{Unresolved}},@{$ambNames{Misapplied}}));
		$alternative =~ s/\;\;/\;/g;
	}
	return ({taxonName => $taxonName, status => $status, tplId => $tplId, alternative => $alternative, ambNames => \%ambNames});
}
sub evaluateHierarchy {
	my $taxon = shift(@_);			# searchterm
	my $queryResult = shift(@_);		# db entries
	my $maxLdist = shift(@_);		# maximum levenshtein distance
	my $byIdQuery = shift(@_);
	my @closeMatches;		             
	
	my $alternative;
	my $sourceId = "NA";
	my $status;	
	my $accepted = "NA";
	my $result;
	
	while (my $dbRow = $queryResult->fetchrow_hashref())
	{
	   # a potential alternative name
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
	   	# searchterm: remove infra specific rank name before distance measurement
		  my $rRtaxon = $taxon;
		  $rRtaxon =~ s/\ssubsp\.|\svar\.|\sf\.//;
		  # potential alternative name: remove infra specific rank name before distance measurement
		  my $rRtestAlternative = $testAlternative;
		  $rRtestAlternative =~ s/\ssubsp\.|\svar\.|\sf\.//;
		  $curDist = distance($rRtestAlternative,$rRtaxon);
	   } else
	   {
		  $curDist = distance($testAlternative,$taxon);
	   }
	   	   
	   if ($curDist <= $maxLdist)
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
		# sort alternative names by distance
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
			# if the closest match (first element) is a perfect match OR 
			# if the closest match has distance 1 and any other match is more distant...
			if ($sorted[0]->{distance} == 0 || ($sorted[0]->{distance} == 1 && $sorted[1]->{distance} > 1))
			{
				$alternative = $sorted[0]->{taxon};
				$status = $sorted[0]->{status};
				$sourceId = $sorted[0]->{tplId};
				my $acceptedName = getTPLaccepted($sorted[0]->{accId}, $byIdQuery);
				if (defined($acceptedName))
				{
					 $accepted = $acceptedName;
				} else
				{
					 if ($status eq "Accepted")
					 {
						$accepted = $sorted[0]->{taxon};
					 }
				}
			# in any other case, we count the result as ambiguous...
			} else
			{
				$status = "Ambiguous (".scalar(@altNames).")";
				$alternative = join(",",@altNames);
			}
		# if there is exactly one alternative...
		} else
		{
			$alternative = $sorted[0]->{taxon};
			$status = $sorted[0]->{status};
			$sourceId = $sorted[0]->{tplId};
			my $acceptedName = getTPLaccepted($sorted[0]->{accId}, $byIdQuery);
			if (defined($acceptedName))
			{
				$accepted = $acceptedName;
			} else
			{
				if ($status eq "Accepted")
				{
					 $accepted = $sorted[0]->{taxon};
				}
			}
		}    
		$result = ({alternative => $alternative, tplId => $sourceId, status => $status, accepted => $accepted});
	}
	return $result;
}

1;