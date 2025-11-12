# AHSAP AVs
Occasionally we get requests to check if there have been large swings in the AVs
for a provided list of
[AHSAP](https://www.cookcountyassessoril.gov/affordable-housing) parcels.

This script loops through a folder of input files, joins them to `mail_year - 2`
and `mail_year - 1` BoR certified values, `mail_year` mailed values, and an
indicator for large changes, then outputs the initial file joined to the new
columns.

All output files are named the same as their corresponding input file, but
placed in the output folder. The script only assumes there will be an input
column named "Permanent Index Number".