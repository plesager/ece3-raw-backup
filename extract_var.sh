#! /usr/bin/env bash

#PBS -N extract
#PBS -q ns
#PBS -l EC_billing_account=nlchekli
#PBS -j oe
#PBS -o extract2.log

##PBS -l walltime=02:30:00

#set -e

##################################################################################
# Script to extract variables from IFS output.  The data are gathered from all   #
# legs (up to 20) and monthly averaged into one file.                            #
#                                                                                #
# This is done to limit transfer before further postproc.  Unlike one year of    #
# data, where you can just transfer everything without thinking, here you select #
# and process several years w/o worrying about the later transfer (if any).      #
#                                                                                #
# Current limitation: variables code is harcoded and limited to GG.              #
##################################################################################

module -s load cdo

  #######################
  # SETTINGS            #
  #######################
 
# input path
exp1=c003

stem=/scratch/ms/nl/nm6/ECEARTH-RUNS
ifs_odir=output/ifs

# output path
outdir=${stem}/${exp1}/postproc
mkdir -p ${outdir}

# variable type: either ICMSH (require transformation TODO) or ICMGG
ty=ICMGG 

# util - extract YYYYMM from ifs output filename
function get_yyyymm {
    echo $1 | sed "s|${stem}/${exp1}/${leg_odir}/${ty}${exp1}+||"
}

  #######################
  # EXTRACT VARIABLES   #
  #######################
 
datestt=999999
dateend=0
for k in {1..20}
do
    leg_odir=${ifs_odir}/$(printf "%3.3d" ${k})

    # leg exists?
    if [ ! -d ${stem}/${exp1}/${leg_odir} ]
    then
        continue
    fi

    # filter all monthly files
    for f1 in ${stem}/${exp1}/${leg_odir}/${ty}${exp1}*
    do
        if [[ -e $f1 ]]
        then
            #echo $f1
            yyyymm=$(get_yyyymm $f1)
            if [[ $yyyymm == '000000' ]]; then continue; fi
## XXX            if [[ $yyyymm -le '195210' ]]; then continue; fi # HACK AFTER CRASH
            dateend=$(( yyyymm > dateend ? yyyymm : dateend ))
            datestt=$(( yyyymm < datestt ? yyyymm : datestt ))

#        param is "167.128" ||
#        param is "39.128" ||
#        param is "40.128" ||
#        param is "41.128" ||
#        param is "42.128"


            cat > rules <<-EOF
if (
        param is "212.128"
){
  write "${outdir}/${exp1}_[param]_[shortName]_${yyyymm}";
}
EOF
            grib_filter rules $f1
        else
            echo "problem with $f1"
        fi
    done
done

echo ''
echo '********************'
echo "start at $datestt and ends at $dateend"
echo '********************'
echo ''
# datestt=195001 
# dateend=196912

  #######################
  # REDUCTION           #
  #######################
 
# monthly averages into one file 
cd ${outdir}
#for param in 167.128 39.128 40.128 41.128 42.128
for param in 212.128
do    
    for f in ${exp1}_${param}*
    do
        [[ "${f}" =~ "_monthly" ]] && continue
        [[ "${f}" =~ '\.nc$' ]] && continue
        [[ -e "${f}_monthly" ]] && continue
        #cdo daymean -shifttime,-3hour $f ${f}_daily
        cdo setday,1 -setreftime,1750-1-1,00:00:00,days -settime,00:00:00 -monmean -shifttime,-3hour $f ${f}_monthly
    done

    cdo --history -R -t ecmwf -f nc4 -z zip mergetime \
        "${exp1}_${param}*_monthly" ${exp1}_${param}_${datestt}-${dateend}.nc
done

