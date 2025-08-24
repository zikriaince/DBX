#2024-12-23-zai: Corrected paths for SAS 2.0.
scion_data = "/scion/data"
cd $scion_data
cp -p $scion_data/dentemax_form_a_*.dat $scion_data/archive/
cp -p $scion_data/dentemax_form_a_*.flg $scion_data/archive/
unzip -o dentemax_form_a_*.dat
cp  $scion_data/archive/scion.flg $scion_data

#2023-09-19-zikri: Changed the validation code to use original file names instead of shortened names.
#2023-08-28-zikri: Added steps to standardize names that are needed for validations
echo "renaming dentemax csv files as scion_rt(1,2,4,5)" >> ${scion_log_file}
for x in  1 2 4 5; do mv PRODUCTION_DENTEMAX_WAOIC_FORMA_$x.csv scion_rt$x.csv; done
rm *.dat
