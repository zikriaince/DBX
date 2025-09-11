https://customerconnect.vmware.com/en/downloads/details?downloadGroup=CART23FQ4_MAC_2212.1&productId=1027&rPId=107193
https://customerconnect.omnissa.com/downloads/details?downloadGroup=CART26FQ2_MAC_2506&productId=1616&rPId=119131
https://customerconnect.omnissa.com/en/downloads/details?downloadGroup=CART23FQ4_MAC_2212.1&productId=1027&rPId=107193


#!/bin/bash
# TODO: Convert to Python.
#20250319-z: Enhanced message logging.
#20241115-z: Print "Skipping" if file already exists. Removed space from FCHN log file name.
#20241021-z: Changed rh-python36 references with /usr/bin/python3.8 (returned by which python3.8) for the new SAS environment. 
#20241016-z: Changed FORMA_TOP and replaced paths for the new SAS environment. 
#20240411-z: Replaced rh-python38 with rh-python36 as only 1065 server has rh-python38. 
#20240404-z: Replaced cms_taxonomy with nucc_taxonomy to pull Taxonomy data from National Uniform Claims Committee (NUCC), 
#20240311-z: Added cms_taxonomy to pull Taxonomy data from CMS. 
#20231227-z: Corrected flag file name and modified download_files to create flag if new files were pulled. 
#20231206-z: Added code to create "<entity>_new_file.flg". 
#20230713-z: Corrected date comparison in download_files function. 
#20230713-z: Commented out pull for int_pharmacy, we are assuming it is the same as medimpact.
filename=$(realpath "$0")
#filename=`basename $0`
#filename=`echo $filename | cut -d\. -f1`

scion_data = "/scion/data"

echo
echo "====================================================================."
echo "`date '+%Y%m%d %T'`> ${filename}.sh starting" 
echo ""

export FORMA_TOP=/form_a
export FORMA_BIN=${FORMA_TOP}/bin
export ENTITIES_TOP=${FORMA_TOP}/entities
export UPWD=`cat $FORMA_TOP/.dwssap/.nwdw/.forma | gunzip`
export PATH=$PATH:/usr/bin/python3.8


# Configure variables for download_files to be used for all entities. 
set_environment_for_entity() {
    local_data_folder=${ENTITIES_TOP}/$entity/data
    local_archive_folder=$local_data_folder/archive
    flag_file=$local_data_folder/${entity}.flg
    start_ts=$(date --date today "+%Y%m%d_%H%M%S")
    log_file=${ENTITIES_TOP}/$entity/logs/${entity}_download_${start_ts}.log
    pulled_new_files=false

    echo "--------------------------------------------------------------------." | tee -a ${log_file}
    echo "$(date '+%Y%m%d %H:%M:%S'): Downloading files for entity $entity" | tee -a ${log_file}
    echo "entity..............: $entity"
    echo "remote server.......: $server"
    echo "file mask...........: $file_mask"
    echo "local data folder...: $local_data_folder"
    echo "local archive folder: $local_archive_folder"
    echo "start timestamp.....: $start_ts"
    echo "log file............: $log_file"
    echo "flag file...........: $flag_file"
    echo
}


# Function to download files from the server via SFTP
download_files() {
    entity=$1
    server=$2
    file_mask=$3
    set_environment_for_entity

    cd $local_data_folder 

    echo "Connecting to $server..."  | tee -a "$log_file"
    # Create a temporary batch script for retrieving file information
    # ls command of sftp does not allow long timestamp format (--time-style=long-iso)
    # sftp not allowed us to "ls -l > remote_files.txt" (couldnt-canonicalise)
    batch_script=$(mktemp)
    #zikri: we don't need to add remote path to files because they all are in our remote home 
    #echo "cd /remote/path/to/files" >> $batch_script
    echo "ls -l ${file_mask}" >> $batch_script
    echo "bye" >> $batch_script

    # Connect to the server via sftp and retrieve file information
    sftp -b $batch_script $server > remote_files.txt
    echo
    echo "Remote files ${file_mask} for download" | tee -a "$log_file"
    cat remote_files.txt  | tee -a "$log_file"


    echo
    echo "Process the remote file information"
    # IFS= (internal field seperator) is used to ignore any spaces, for extra precaution
    while IFS= read -r line; do
        # check if the line starts with a hypen using regular expression matching
        if [[ $line =~ ^- ]]; then

            file=$(echo "$line" | awk '{print $9}')
            mondd=$(echo "$line" | awk '{print $6, $7}')
# if date is not in current year then time portion shows that year, 3rd line below
# Otherwise 8th token is a timestamp in HH:MI format
#-rw-------    0 0        0         1444389 Jun 26 08:39 FormA_Ind.csv
#-rw-------    0 0        0          349701 Jun 26 08:45 FormA_Org.csv
#-rw-------    0 0        0            3282 Dec 23  2022 Mapped_Taxonomy_Capacity.csv
            timestamp=$(echo "$line" | awk '{print $8}')
            local_file="$local_data_folder/$file"
            local_file_ts=$(date -d "$(stat -c %y $local_file )" '+%Y-%b-%d %H:%M')

            echo
            echo "file.........: $file"
            echo "timestamp....: $timestamp"
            echo "mondd........: $mondd"
            echo "local_file...: $local_file"
            echo "local_file_ts: $local_file_ts"

            if [[ ! -e $local_file ]] || \
               ([[ $timestamp == *":"* ]] && [[ $(date -d "$(stat -c %y $local_file)" '+%b %d') != "$mondd" ]]) || \
               ([[ $timestamp == *":"* ]] && [[ $(date -d "$(stat -c %y $local_file)" '+%H:%M') != "$timestamp" ]]); then
               # this will exclude files that are created in current year
               
               if [[ -e $local_file ]]; then
                  echo "Moving $file to archive directory..." | tee -a "$log_file"
                  #dt=$(date -d "$(stat -c %y $local_file)" '+%Y%m%d')
                  # Extract the file name and extension
                  file_name=$(basename "$local_file")
                  file_extension="${file_name##*.}"
                  file_name="${file_name%.*}"

                  # Get the last modified date of the file
                  last_modified=$(stat -c %y "$local_file" | awk '{print $1}')

                  # Remove dashes from the date
                  last_modified=${last_modified//-/}

                  # Create the new file name with the date
                  file_name_with_date="${file_name}_${last_modified}.${file_extension}"
              
                  mv $local_file "$local_archive_folder/$file_name_with_date"

               fi
                
               echo "Downloading..: $file from $server..." | tee -a "$log_file"
               # get one file at a time!
               sftp $server <<EOF
lcd $local_data_folder
get -p "$file"
quit
EOF
                
               # Turn new file downloaded indicator on
               pulled_new_files=true
               echo "$(date '+%Y%m%d_%H%M%S'): Downloaded $file" | tee -a "$log_file"
               echo ""
            else
               echo "Skipping.....: $file already exists." | tee -a "$log_file"
            fi
        fi
    done < remote_files.txt

    
    # Remove the temporary files
    echo 
    echo "Remove the temporary files" | tee -a "$log_file"
    rm "$batch_script" remote_files.txt


    # If a new file(s) downloaded
    if [ ${pulled_new_files} == true ]; then
       # Create new file flag
       touch $flag_file
       echo "Created flag file ${flag_file}." | tee -a ${log_file}               
       #sqlplus -S forma/${UPWD}@nwdw "delete from ERROR_LOG_WORKING where business_lineid = ; commit; exit;"                
       #echo "Removed previously created validations for ${entity}."
    else
       echo "No new files downloaded and flag file not created." | tee -a ${log_file}               
    fi
    echo "$(date '+%Y%m%d %H:%M:%S'): Finished downloading files for entity $entity" | tee -a ${log_file}
    echo "--------------------------------------------------------------------." | tee -a ${log_file}
    echo ""
}


# ########################################################################################
# zikri: Bolted on later to allow pulling of files for chosen entiti(y/ies) as well as for all.
pull() {
    case "$1" in
        "aff_medical")
            # Affiliated Medical
            download_files "aff_medical" \
                           "sFTP_NWDW_HIS_AFILTD@sftp-nwdw-form-a.appl.kp.org" \
                           "*.csv"
            ;;
        #zikri-20240404: replaced with taxonmy to download from nucc.org
        "cms_taxonomy")
            # NPPES (National Plan and Provider Enumeration System by CMS)
            # not on SFTP server. it is listed on CMS.gov download site.
            # needs parsing of web page to get the download URL and pull a JSON file
            # that has no line breaks (a CSV download exists on a pop-up window which is harder to scrape)
            # which then needs to be converted to proper CSV format.
            EHOME=/gpfs/FS2/sasdata/adhoc/kpit/cdts/nwdis/NWKPIT/FORMA/form_a/entities/cms_taxonomy
            DATA=$EHOME/data
            BIN=/gpfs/FS2/sasdata/adhoc/kpit/cdts/nwdis/NWKPIT/FORMA/form_a/bin
            echo "move existing extracts to archive otherwise python script aborts"
            mv ${DATA}/*.json ${DATA}/*.csv ${DATA}/*.xlsx ${DATA}/*.zip       ${DATA}/archive
            cms_log_file=/gpfs/FS2/sasdata/adhoc/kpit/cdts/nwdis/NWKPIT/FORMA/form_a/entities/taxonomy/logs/cms_taxonomy_download_$(date --date today "+%Y%m%d_%H%M%S").log
            echo "executing update_cms_taxonomy.py" | tee -a ${cms_log_file}
            /usr/bin/python3.8  ${BIN}/update_cms_taxonomy.py   >> ${cms_log_file} 
            if [ $? -eq 0 ]; then
                echo "..pull script ran successfully."
            else
                echo "..pull script failed with exit status $?"
            fi
            echo "..additional info: ${cms_log_file}"
            ;;
        "fchn")
            # FCHN (First Choice Health Network)
            fchn_log_file=/gpfs/FS2/sasdata/adhoc/kpit/cdts/nwdis/NWKPIT/FORMA/form_a/entities/fchn/logs/fchn_download_$(date --date today "+%Y%m%d_%H%M%S").log
            echo "calling FCHN pull script (sftp_get_fchn.py)..." | tee ${fchn_log_file} 
            /usr/bin/python3.8 ${FORMA_BIN}/sftp_get_fchn.py >> ${fchn_log_file} 
            if [ $? -eq 0 ]; then
                echo "..pull script ran successfully."
            else
                echo "..pull script failed with exit status $?"
            fi
            echo "..additional info: ${fchn_log_file}"
            ;;
        "int_dental")
            # Internal Dental
            download_files "int_dental" \
                           "sFTP_NWDW_HIS_DENTAL@sftp-nwdw-form-a.appl.kp.org" \
                           "*.csv"
            ;;
        "int_medical")
            # Internal Medical
            download_files "int_medical" \
                           "sFTP_NWDW_HIS_INTRNL@sftp-nwdw-form-a.appl.kp.org" \
                           "NWP_WA_OIC_*.csv"
            ;;
        "Xint_pharmacy")
            echo "int_pharmacy extracts are ???pushed to us as a csv file and flag file to signal new files???."
            #zikri-20230713: isn't this medimpact? if so, it is being pulled. should remove it
            ;;
        "medimpact")
            download_files "medimpact" \
                           "sFTP_NWDW_HIS_PHX@sftp-nwdw-form-a.appl.kp.org" \
                           "*.csv"
            ;;
        "nppes")
            # NPPES (National Plan and Provider Enumeration System by CMS)
            # not on SFTP server. it is listed on CMS.gov download site.
            # needs parsing of web page to get the download URL and pul
            EHOME=/gpfs/FS2/sasdata/adhoc/kpit/cdts/nwdis/NWKPIT/FORMA/form_a/entities/nppes
            DATA=$EHOME/data
            BIN=/gpfs/FS2/sasdata/adhoc/kpit/cdts/nwdis/NWKPIT/FORMA/form_a/bin
            echo "move existing extracts to archive otherwise python script aborts"
            mv ${DATA}/*.csv ${DATA}/*.xlsx ${DATA}/*.zip       ${DATA}/archive
            nppes_log_file=/gpfs/FS2/sasdata/adhoc/kpit/cdts/nwdis/NWKPIT/FORMA/form_a/entities/nppes/logs/nppes_download_$(date --date today "+%Y%m%d_%H%M%S").log
            echo "calling NPPES pull script (update_nppes_deactivation.py)..." >> ${nppes_log_file}
            /usr/bin/python3.8  ${BIN}/update_nppes_deactivation.py   >> ${nppes_log_file} 
            if [ $? -eq 0 ]; then
                echo "..pull script ran successfully."
            else
                echo "..pull script failed with exit status $?"
            fi
            echo "..additional info: ${nppes_log_file}"
            ;;
        #zikri-20230718: "data/scion_unpack.sh" will be doing unpacking. keeping it here for history.
        "scion")
            entity=scion
            # no server to pull data from and no file mask
            set_environment_for_entity
            cd ${local_data_folder}
            
            current_ts=$(stat -c %Y dentemax_form_a_*.dat)
            latest_archive_ts=$(find ${local_data_folder}/archive -type f -name "*.dat" -exec stat -c %Y {} + | sort -n | tail -n 1)
            echo "Current File TS=${current_ts}  vs. Latest File in Arcrhive=${latest_archive_ts}"
            if ( $curent_ts > $latest_archive_ts ); then
              echo "current is NOT in the archive"
              # Turn new file downloaded indicator on
              pulled_new_files=true
              # Create new file flag
              touch $flag_file      
              echo "created flag file ${flag_file}."        
            fi

            echo "$(date '+%Y%m%d %H:%M:%S'): Downloaded $file" | tee -a "$log_file"
            echo ""
            cp ${local_data_folder}/dentemax_form_a_*.dat ${local_archive_folder}
            scion_log_file=/gpfs/FS2/sasdata/adhoc/kpit/cdts/nwdis/NWKPIT/FORMA/form_a/entities/scion/logs/scion_download_$(date --date today "+%Y%m%d_%H%M%S").log
            echo "unzipping form-a data file received from dentemax" >> ${scion_log_file}
            unzip -o dentemax_form_a_*.dat
            echo "renaming dentemax csv files as scion_rt(1,2,4,5)" >> ${scion_log_file}
            for x in  1 2 4 5; do mv PRODUCTION_DENTEMAX_WAOIC_FORMA_$x.csv scion_rt$x.csv; done
            rm *.dat
            ;;
        "taxonomy")
            # NUCC (National Uniform Claims Committee)
            # not on SFTP server. it is listed on NUCC.gov download site.
            # File name is https://www.nucc.org/images/stories/CSV/nucc_taxonomy_240.csv
            # 3 numbers in the file name are for: YY followed by 0 if pulling before July or 1 in July and later.
            EHOME=/gpfs/FS2/sasdata/adhoc/kpit/cdts/nwdis/NWKPIT/FORMA/form_a/entities/taxonomy
            DATA=$EHOME/data
            BIN=/gpfs/FS2/sasdata/adhoc/kpit/cdts/nwdis/NWKPIT/FORMA/form_a/bin
            echo "move existing extracts to archive otherwise python script aborts"
            mv ${DATA}/*.csv  ${DATA}/archive
            taxonomy_log_file=/gpfs/FS2/sasdata/adhoc/kpit/cdts/nwdis/NWKPIT/FORMA/form_a/entities/taxonomy/logs/taxonomy_download_$(date --date today "+%Y%m%d_%H%M%S").log
            echo "Calling Taxonomy pull script (update_taxonomy.py)..." | tee -a ${taxonomy_log_file}
            /usr/bin/python3.8  ${BIN}/update_taxonomy.py   >> ${taxonomy_log_file} 
            if [ $? -eq 0 ]; then
                echo "..pull script ran successfully."
            else
                echo "..pull script failed with exit status $?"
            fi
            echo "..additional info: ${taxonomy_log_file}"
            ;;
        *)
            if [ -z "$1" ]; then
                echo "No parameter provided."
            else
                echo "Invalid parameter: $1"
            fi
            echo "Usage: ./script_name [param1] [param2] [param3]"
            ;;
    esac
}

# Check the number of arguments
if [ $# -eq 0 ]; then
    # No parameters provided, pull files for all entities
    pull "aff_medical"
    #zikri-2020404:replaced with just taxonomy after switching CMS with NUCC.
    #pull "cms_taxonomy"
    pull "fchn"
    pull "int_dental"
    pull "int_medical"
    #zikri-20230713:assuming same as medimpact.
    #pull "int_pharmacy"
    pull "medimpact"
    pull "nppes"
    pull "scion"
    pull "taxonomy"
    echo "Completed all pulls."
    exit 0
fi

# Iterate through the arguments and execute the function accordingly
for arg in "$@"; do
    # Convert argument to lowercase for case-insensitive comparison
    arg_lower=$(echo "$arg" | tr '[:upper:]' '[:lower:]')

    # Call the function with the argument
    pull "$arg_lower"
done
echo "Completed data pulls requested. Please see individual log files created for details."

echo "`date '+%Y%m%d %T'`> $filename.sh finished." 
echo "====================================================================."
echo
