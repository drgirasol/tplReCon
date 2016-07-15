package Col;
use strict;
use warnings;
use Exporter;
use Cwd;
use WWW::Mechanize;
use JSON;
use WWW::JSON;
use Term::ANSIColor;
use Text::Levenshtein qw(distance);
use Data::Dumper;
use File::Slurp;


our @ISA= qw( Exporter );

# these CAN be exported.
our @EXPORT_OK = qw( colReCon );

# these are exported by default.
our @EXPORT = qw( colReCon );

sub taxon2words {
    #
    # split taxon in genus, species and infraspecies parts, returns an array of 4 or dies
    #
    my $taxon = shift(@_);
    my @returnSplits;
    my @tSplits = split(" ", $taxon);
    if (@tSplits == 5 && $tSplits[1] eq "x" && $tSplits[3] =~ /^ssp\.|subsp\.|var\.|f\.|fo\.$/)
    {
        push(@returnSplits, $tSplits[0]);
        push(@returnSplits, $tSplits[2]);
        push(@returnSplits, $tSplits[4]);
        push(@returnSplits, $tSplits[3]);
    } elsif (@tSplits == 4 && $tSplits[2] =~ /^ssp\.|subsp\.|var\.|f\.|fo\.$/)
    {
        push(@returnSplits, $tSplits[0]);
        push(@returnSplits, $tSplits[1]);
        push(@returnSplits, $tSplits[3]);
        push(@returnSplits, $tSplits[2]);
    } elsif (@tSplits == 3 && $tSplits[1] eq "x")
    {
        push(@returnSplits, $tSplits[0]);
        push(@returnSplits, $tSplits[2]);
        push(@returnSplits, "");
        push(@returnSplits, "");
    } elsif (@tSplits == 2)
    {
        push(@returnSplits, $tSplits[0]);
        push(@returnSplits, $tSplits[1]);
        push(@returnSplits, "");
        push(@returnSplits, "");
    } else
    {
        die ("TAXON2WORDS failed trying to split taxon '$taxon'");
    }
    return @returnSplits;
}
sub colTaxa {
    #
    # search at COL for list of taxa and return XML result (save to local directory /CoL_TAXA)
    #    
    #
    my $taxon = shift(@_);
    my $cwd = getcwd();
    my $xmlDir = $cwd."/CoL_TAXA";
    unless(-e $xmlDir)
    {
        mkdir($xmlDir) or die "Error ($!) creating CoL XML directory";
    }
    my $fileName;
    my $lookingFor;
    my $colCall;
    my $dom;
    my @taxonParts = taxon2words($taxon);
    if (@taxonParts == 4)
    {
        my $colUrl = "http://www.catalogueoflife.org/col/";
        my $colKey = "30554fc5008829b418639e58b66eac1b";
        if ($taxonParts[3] ne "")
        {
            $colCall = $colUrl."webservice?name=$taxonParts[0]+$taxonParts[1]&response=full";
            $lookingFor = join(" ",($taxonParts[0],$taxonParts[1]));
            $fileName = "CoL_TAXA/$taxonParts[0]_$taxonParts[1].xml";
        } else
        {
            $colCall = $colUrl."webservice?name=$taxonParts[0]&response=full";
            $lookingFor = $taxonParts[0];
            $fileName = "CoL_TAXA/$taxonParts[0].xml";
        }
        print "\n\tRequesting data for ".colored($lookingFor, 'bold cyan on_black')." from CoL:\n";
        if (-e $fileName)
        {
            # load data from xml file
            print "\n\t\tReading XML from File: ";
            open(my $fh2, "<", $fileName) or die "$fileName $!";
            binmode $fh2; # drop all PerlIO layers possibly created by a use open pragma
            $dom = XML::LibXML->load_xml(IO => $fh2);
        } else
        {
            print "\n\t\tReading from CoL: ";

            if (eval {$dom = XML::LibXML->load_xml(location => $colCall)})
            {
                my $results = $dom->getElementsByTagName("results");
                # my $results = $dom->getElementsByTagName("status");
                my $attributes = $results->get_node(0)->attributes();
                my $errMsg = $attributes->getNamedItem("error_message");
                #print "\n".$errMsg->value."\n";

                if ($errMsg->value ne "")
                {
                    print "\n\t\t -| ".colored($errMsg->value, 'bold red on_black')."\n";
                    return ("false", $errMsg->value);
                } else
                {
                    # save xml as file
                    open my $fh2, ">", $fileName or die "$fileName $!";
                    binmode $fh2; # drop all PerlIO layers possibly created by a use open pragma
                    $dom->toFH($fh2);
                    print "\n\t\t -| Save File\n";
                }
            } else
            {
                print "\n\t\t -| ".colored("XML ERROR",'bold red on_black')."\n";
                die("XML Error");
            }
        }
        return ("true",$dom);
    } else
    {
        return ("false", "Error");
    }
}
sub isIdentical {
	#
	# compares taxon names and returns true (1) / false (0)
	#
	my $context = shift(@_);
	my $taxon = shift(@_);

    my $genus = $context->findnodes('./genus')->get_node(0)->textContent;
    my $species = $context->findnodes('./species')->get_node(0)->textContent;
    my $infraEpithet = $context->findnodes('./infraspecies')->get_node(0)->textContent;
    my $infraMarker = $context->findnodes('./infraspecific_marker')->get_node(0)->textContent;
    my $contextTaxon = join(" ", ($genus, $species, $infraMarker, $infraEpithet));
    $contextTaxon =~ s/\s+$//;
    if ($contextTaxon eq $taxon)
    {
        return (1,$contextTaxon);
    }
    return (0,$contextTaxon);
}
sub loadColDetails
{
    my $json = shift(@_);
    my $taxon = shift(@_);    # TPL entry
    my $taxonName = shift(@_);
    my $response = "full";
    
    my $cwd = getcwd();
    my $jsonDir = $cwd."/CoL_DATA";
    unless(-e $jsonDir)
    {
        mkdir($jsonDir) or die "Error ($!) creating CoL JSON directory";
    }    
    my $fileName;
    if ($taxon->{infraspecificEpithet} eq "")
    {
        $fileName = $taxon->{genus};
    } else
    {
        $fileName = join(" ", ($taxon->{genus}, $taxon->{species}));
    }
    $fileName =~ s/\s/\_/g;
    $fileName =~ s/\_+$//;
    $fileName =~ s/\.$//;
    my $dataFile = "CoL_DATA/$fileName-$response.json";        
        
    my $detailJson;    
    
    if (-e $dataFile)
    {
        # load data from xml file
        print "\n\t\tReading JSON from File: ";
        my $jsonText = read_file($dataFile);        
        $detailJson = decode_json($jsonText);        
    } else
    {
        if (@{$json->{results}} > 0)
        {
            print "\n\t\tRequesting taxa details from Catalouge of Life";
            $detailJson = [];
            foreach my $item (@{$json->{results}})
            {                        
                print ".";
                my $wj = WWW::JSON->new(
                    base_url                   => 'http://www.catalogueoflife.org',
                    post_body_format           => 'JSON'            
                );
                my $get = $wj->get(
                    '/col/webservice',
                    {
                        id       => $item->{id},
                        format   => 'json',
                        response => $response
                    }
                );
                if ($get->success)
                {
                    push($detailJson, $get->response->{results}[0]);
                }        
            }
            open my $df, ">", $dataFile or die "$dataFile $!";
            print $df encode_json $detailJson;
            print "Saved File $dataFile\n";                  
        }
        
    }
    return $detailJson;    
}
sub loadColData 
{
    my $taxon = shift(@_);    # TPL entry
    my $taxonName = shift(@_);
    my $response = "terse";
    my $query = $taxonName;
    $query =~ s/\s+$//;
    $query =~ s/^\s+//;
    
    my $cwd = getcwd();
    my $jsonDir = $cwd."/CoL_DATA";
    unless(-e $jsonDir)
    {
        mkdir($jsonDir) or die "Error ($!) creating CoL JSON directory";
    }    
    
    my $fileName = $taxonName;
    $fileName =~ s/\s/\_/g;
    $fileName =~ s/\_+$//;
    $fileName =~ s/\.$//;
    my $dataFile = "CoL_DATA/$fileName-$response.json";            
    
    print "\n\t\tRequesting taxon status from Catalouge of Life: ".colored($taxonName,'bold cyan on_black');    
    #print "\n\t\tData File: $dataFile\n";   
    
    my $json;
    
    if (-e $dataFile)
    {
        # load data from xml file
        print "\n\t\tReading JSON from File: ";
        my $jsonText = read_file($dataFile);        
        $json = decode_json($jsonText);        
    } else
    {
        print "\n\t\tReading from CoL: ";
        my $wj = WWW::JSON->new(
            base_url                   => 'http://www.catalogueoflife.org',
            post_body_format           => 'JSON'            
        );
        my $get = $wj->get(
            '/col/webservice',
            {
                name       => $query,
                format     => 'json',
                response   => $response
            }
        );        
        if ($get->success && $get->response->{number_of_results_returned} > 0)
        {
            open my $df, ">", $dataFile or die "$dataFile $!";
            
            if ($get->response->{number_of_results_returned}+$get->response->{start} < $get->response->{total_number_of_results})
            {            
                my $combinedResults = [];
                while ($get->response->{number_of_results_returned}+$get->response->{start} < $get->response->{total_number_of_results})
                {
                    my $nextStart = $get->response->{number_of_results_returned}+$get->response->{start};
                    foreach my $item (@{$get->response->{results}})
                    {
                        push($combinedResults, $item); 
                    } 
                    $get = $wj->get(
                        '/col/webservice',
                        {
                            name       => $query,
                            format     => 'json',
                            response   => $response,
                            start      => $nextStart
                        }
                    );                
                }
                $get->response->{results} = $combinedResults;
            }            
            $json = $get->response;            
            print $df encode_json $get->response;
            print "Saved File $dataFile\n";
        }
    }
    return $json;
}
sub evaSimilarStatus
{
    my $json = shift(@_);
    my $taxon = shift(@_);
    my $taxonName = shift(@_);
     
    my $duplicates = 0;
    my $status = "NA";
    my $accepted = "NA";
    my $sourceId = "NA";
    my $alternative = "";
    
    my $return;
    
    my @hits = ();
    
    if (@{$json->{results}} > 0)
    {        
        print "\n\t\t -| Evaluation of CoL Similar Search Result ".scalar @{$json->{results}}."\n";
       
        foreach my $item (@{$json->{results}})
        {            
            #print Dumper($item);
            if ($item->{rank} eq "Infraspecies" && $taxon->{infraspecificRank} ne "")
            {
                push(@hits, $item);                
            } elsif ($item->{rank} eq "Species" && $taxon->{infraspecificRank} eq "")
            {
                push(@hits, $item);                
            }
        }
        if (@hits > 1)
        {
            $status = "Ambiguous (".scalar @hits.")";
            my @allNames = getAllItemNames(@hits);
            if (defined(@allNames))
            {
                $alternative = join(";", @allNames);
            }
            $return = ({status => $status, sourceId => $sourceId, duplicates => scalar @hits, accepted => $accepted, alternative => $alternative});
        } else
        {
            $status = $hits[0]->{name_status};
            $alternative = $hits[0]->{name};
            if ($status eq "synonym")
            { 
                $accepted = $hits[0]->{accepted_name}{name};
            } elsif ($status eq "accepted name")
            {
                $accepted = $hits[0]->{name};
            }
            $sourceId = $hits[0]->{id};            
            $return = ({status => $status, sourceId => $sourceId, duplicates => scalar @hits, accepted => $accepted, alternative => $alternative});
            
        }               
    }    
    return $return;
}
sub getSimilarNames
{
    my $json = shift(@_);    
    my $taxon = shift(@_);
    my $taxonName = shift(@_);
    my $maxLdist = shift(@_);
    
    my $newJson;
    
    #if (@{$json} > 1)
    if (@{$json->{results}} > 1)
    {        
        my $newJsonItems = [];
        my $toi = join(" ", ($taxon->{genus},$taxon->{species},$taxon->{infraspecificEpithet}));
        $toi =~ s/\s+$//;
        #foreach my $item (@{$json})
        foreach my $item (@{$json->{results}})
        { 
            if (defined($item->{rank}) && ($item->{rank} eq "Species" || $item->{rank} eq "Infraspecies"))
            {
                my $alternative = $item->{name};
                $alternative =~ s/\s+$//;
                my $curDist = distance($toi,$alternative);
                #print "\n\t\t\t $toi = $alternative : $curDist";
                if ($curDist <= $maxLdist)
                {
                    print "\n\t\t\t $toi = $alternative : $curDist";
                    push($newJsonItems, $item);
                }
            }
        }
        print "\n\t\t\t";
        if (@{$newJsonItems} > 0)
        {
            $newJson = $json;
            $newJson->{results} = $newJsonItems;
        }        
    }
    return $newJson;
}
sub colReCon
{
    my $tplEntry = shift(@_);    # TPL entry
    my $taxonName = shift(@_);
    my $maxLdist = shift(@_);   
    my $source = "COL";    
    my $result;
    
    my $colResult = colStatus($tplEntry, $taxonName);
    if (defined($colResult))
    {        
        $result = ({status => $colResult->{status}, sourceId => $colResult->{sourceId}, source => $source, accepted => $colResult->{accepted}, alternative => $colResult->{alternative}});        
    } else                     
    {
        my $colHierarchyResults = colHierarchy($tplEntry, $taxonName, $maxLdist);
        if (defined($colHierarchyResults))
        {           
           $result = ({status => $colHierarchyResults->{status}, sourceId => $colHierarchyResults->{sourceId}, source => $source, accepted => $colHierarchyResults->{accepted}, alternative => $colHierarchyResults->{alternative}});
        }      
    }
    return $result;
}
sub colHierarchy
{
    my $taxon = shift(@_);    # TPL entry
    my $taxonName = shift(@_);
    my $maxLdist = shift(@_);
    
    my $accepted = "NA";
    
    my $json;
    my $return;
    
    if ($taxon->{infraspecificRank} ne "")
    {
        my $species = join(" ", ($taxon->{genus}, $taxon->{species}));
        $json = loadColData($taxon, $species);
    } else
    {        
        $json = loadColData($taxon, $taxon->{genus});
    }
    
    if (defined($json))
    {         
        my $newJson = getSimilarNames($json, $taxon, $taxonName, $maxLdist);            
        if (defined($newJson))
        {
            my $successEva = evaSimilarStatus($newJson, $taxon, $taxonName);
            if (defined($successEva))
            {                    
                $return = ({ status => $successEva->{status}, sourceId => $successEva->{sourceId}, accepted => $successEva->{accepted}, alternative => $successEva->{alternative}});
            }
        }       
    }   
    return $return;
    
    
}
sub isInfraSpec
{
    my $taxon = shift(@_);
    my $item = shift(@_);
    my @itemNameSplit = split(" ", $item->{name});
    #print Dumper($item);
    #<STDIN>;
    my $itemInfraEpithet = pop(@itemNameSplit);
    if ($taxon->{species} eq $itemInfraEpithet)
    {
        return 1;
    } else
    {
        return 0;
    }
}
sub getAllItemNames
{    
    my @names;
    foreach my $item (@_)
    {
        push(@names, $item->{name});
    }
    return @names;
}
sub evaColStatus
{
    my $json = shift(@_);
    my $taxon = shift(@_);
    my $taxonName = shift(@_);
         
    my $status = "NA";
    my $sourceId = "NA";
    my $accepted = "NA";
    my $alternative = "";
    
    my $return;        
    
    my @hits = ();
    
    if (@{$json->{results}} > 0)
    {        
        print "\n\t\t -| Evaluation of CoL Search Result ".scalar @{$json->{results}}."\n";
        my $hasGoodHit = 0;
        foreach my $item (@{$json->{results}})
        {                        
            if ($item->{rank} eq "Infraspecies" && $taxon->{infraspecificRank} ne "")
            {
                push(@hits, $item);
                
            } elsif ($item->{rank} eq "Species" && $taxon->{infraspecificRank} eq "")
            {
                push(@hits, $item);
                $hasGoodHit++;   # we asume that if we are looking for a species they will be first in the result-list 
            } elsif ($item->{rank} eq "Infraspecies" && $taxon->{infraspecificRank} eq "" && $hasGoodHit < 1)
            {
                # check if species name is really a infraspecific name
                if (isInfraSpec($taxon, $item) == 1)
                {
                    push(@hits, $item);
                }
            }
        }
        if (@hits > 1)
        {
            $status = "Ambiguous (".scalar @hits.")";
            my @allNames = getAllItemNames(@hits);
            if (defined(@allNames))
            {
                $alternative = join(";", @allNames);
            }
            $return = ({status => $status, sourceId => $sourceId, duplicates => scalar @hits, alternative => $alternative, accepted => $accepted});
        } else
        {
            $status = $hits[0]->{name_status};
            #print Dumper($hits[0]);
            if ($status eq "synonym")
            {
                $accepted = $hits[0]->{accepted_name}{name};
                #print "---".$hits[0]->{accepted_name}{name};
            } elsif ($status eq "accepted name" || $status eq "provisionally accepted name")
            {
                $accepted = $hits[0]->{name};
                #print "---".$hits[0]->{name};
            }
            #<STDIN>;
            $sourceId = $hits[0]->{id};
            $return = ({status => $status, sourceId => $sourceId, duplicates => scalar @hits, alternative => $alternative, accepted => $accepted});
        }               
    }    
    return $return;
}
sub colStatus 
{
    #
    # search at COL or local directory for status of taxon and return XML result
    #    
    #
    my $taxon = shift(@_);    # TPL entry
    my $taxonName = shift(@_);
    
    my $return;
    
    my $json = loadColData($taxon, $taxonName);
    my @notes;

    if (defined($json))
    {                  
        my $successEva = evaColStatus($json, $taxon, $taxonName);
        if (defined($successEva))
        {            
            if ($successEva->{duplicates} > 0)
            { 
                push(@notes, $successEva->{duplicates}." x duplicate(s)");
            }
            $return = ({ status => $successEva->{status}, sourceId => $successEva->{sourceId}, notes => join(",",@notes), alternative => $successEva->{alternative}, accepted => $successEva->{accepted}});
        }
    }       
    return $return;
}
sub colDist
{
    #
    # get COL distribution data by ID, return XML result
    #
    # toDo: check if CoL_DIST directory exists. If not, create it.
    #
    #
    my $taxId = shift(@_);
    my $taxon = shift(@_);

    my @taxonParts = taxon2words($taxon);

    print "\n\tRequesting Catalouge of Life distribution data for ".colored($taxon,'bold cyan on_black')."\n";

    my $fileName = join("_",@taxonParts);
    $fileName =~ s/\_+$//;
    $fileName =~ s/\.$//;
    my $dataFile = "CoL_DIST/$fileName.xml";

    my $colUrl = "http://www.catalogueoflife.org/col/webservice";
    my $colCall = $colUrl."?id=$taxId&format=xml&response=full";

    my $dom;

    if (-e $dataFile)
    {
        # load data from xml file
        print "\n\t\tReading XML from File: ";
        open(my $df, "<", $dataFile) or die "$dataFile $!";
        binmode $df; # drop all PerlIO layers possibly created by a use open pragma
        $dom = XML::LibXML->load_xml(IO => $df);
        return ("true",$dom);
    } else
    {
        print "\n\t\tReading from CoL: ";
        #print "\n\t\t$colCall";
        if (eval {$dom = XML::LibXML->load_xml(location => $colCall)})
        {
            # save xml as file
            open my $df, ">", $dataFile or die "$dataFile $!";
            binmode $df; # drop all PerlIO layers possibly created by a use open pragma
            $dom->toFH($df);
            print "\n\t\t -| Save File\n";
            return ("true",$dom);
        } else
        {
            print "\n\t\t -| ".colored("XML ERROR",'bold red on_black')."\n";
            return ("false","XML Error");
        }
    }
}
sub colSynonyms
{
  #
  # get synonyms
  #
    my $taxon = shift(@_);

    my @taxonParts = taxon2words($taxon);
  	if (@taxonParts == 4)
  	{
        my $colUrl = "http://www.catalogueoflife.org/webservices/";
        my $colKey = "30554fc5008829b418639e58b66eac1b";
        my $colCall = $colUrl."synonyms/query/key/$colKey/genus/$taxonParts[0]/species/$taxonParts[1]/infraspecies/$taxonParts[2]";

        my $dom;
        my %tax;
        my @notes;


      if (eval {$dom = XML::LibXML->load_xml(location => $colCall)})
      {
         my $results = $dom->getElementsByTagName("status");
         my @attributes = $results->get_node(0)->attributes();
         if ($attributes[0]->value == 100)
         {
            print "\n\t\t -| ".colored("Name could not be found at CoL", 'bold red on_black')."\n";
         } elsif ($attributes[0]->value > 100)
         {
            die ("\n\tUnexpected Error (".$attributes[0]->value.") - aborted\n");
         } else
         {
            #print $dom->textContent;
            my $acceptedNames = $dom->findnodes("//sp2000/response/accepted_name");
            my %acc_Id;
            foreach my $context ($acceptedNames->get_nodelist)
            {
               my @acc_attributes = $context->attributes();
               my $acc_genus = $context->findnodes('./genus')->get_node(0)->textContent;
               my $acc_species = $context->findnodes('./species')->get_node(0)->textContent;
               my $acc_infraspec = $context->findnodes('./infraspecies')->get_node(0)->textContent;
               my $acc_infraMarker = $context->findnodes('./infraspecific_marker')->get_node(0)->textContent;
               my $acc_taxon = join(" ", ($acc_genus, $acc_species, $acc_infraMarker, $acc_infraspec));
               $acc_taxon =~ s/\s+$//;
               if ($acc_taxon eq $taxon)
               {
                  $acc_Id{$acc_attributes[0]->value} = 1;
                  my $acc_synonyms = $context->findnodes('./synonyms/synonym');
                  #print "\n\t\t Genus: $acc_genus | Species: $acc_species | Infraspecies: $acc_infraspec";
                  $tax{"cSynonyms"} = $acc_synonyms->size();
               }
            }
            if (scalar(keys %acc_Id) > 1)
            {
               $tax{"Status"} = "Ambiguous (".scalar(keys %acc_Id).")";
            } else
            {
               my @sourceIds = keys %acc_Id;
               $tax{"SourceId"} = $sourceIds[0];
            }
         }
      } else
      {
         push(@notes, "XML error");
      }
    }
}
1;