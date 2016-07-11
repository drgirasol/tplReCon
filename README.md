# tplReCon
Uses "The Plant List" for taxonomic status reconciliation.

# The Plant List mySQL dump
The Plant List mySQL database as used in http://bdj.pensoft.net/articles.php?id=7971
tpldata_live110716.zip.001
tpldata_live110716.zip.002
tpldata_live110716.zip.003

# tpl.pm
Collection of reusable functions

# tplNameCheck.pl
Input: CSV-file (using ";" as field separator)
First Column = Family name, Second Column = Taxon name.
Information stored in additional columns will be appended to the results in Output 1.

# Output 1
Inputfile_TPL_NameCheck.csv.
Columns: Family, Genus, input Taxon, Source Id, Status, additional columns

# Output 2
Inputfile_TPL_Ambiguities.csv.
In case the input taxon name is found more than once, all names are stored in corresponding columns separated by "|".
Columns: input Taxon, Accepted name(s), Synonym(s), Unresolved name(s), Misapplied name(s)
