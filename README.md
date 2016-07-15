# tplReCon
Uses "The Plant List" (TPL, primary) and the "Catalogue Of Life" (COL, secondary) for taxonomic status reconciliation.

# The Plant List mySQL dump
TPL mySQL database as used in http://bdj.pensoft.net/articles.php?id=7971
tpldata_live110716.zip.001
tpldata_live110716.zip.002
tpldata_live110716.zip.003

# Tpl.pm & Col.pm
TPL and COL specific collection of reusable functions

# tplReCon.pl
  Input: CSV-file (using ";" as field separator)
    First Column = Family name, Second Column = Taxon name.
    Information stored in additional columns will be appended to the results in Output 1.
  Usage: tplNameCheck.pl "directory/CSV-file.csv". 
    Output files will be stored in the directory of the input file.

# Output 1
Inputfile_TPL_NameCheck.csv.
Columns: Family, Genus, (input) Taxon, Alternative(s), Source, Source Id, Status, Accepted (name), additional columns

# Output 2
Inputfile_TPL_Ambiguities.csv.
In case the input taxon name is found more than once, all names are stored in corresponding columns separated by "|".
Columns: (original) Taxon, Accepted name(s), Synonym(s), Unresolved name(s), Misapplied name(s)
