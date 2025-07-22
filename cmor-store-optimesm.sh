#!/usr/bin/env bash

#SBATCH --qos=nf
#SBATCH --cpus-per-task=10
#SBATCH --output=log/cmor-store/store.optimesm.gw43.pt.%j.out
#SBATCH --ntasks=1
#SBATCH --account=nlchekli
##SBATCH --time=12:00:00

set -ue

# Although parallelized, the limit on number of concurrent "emv" means you should submit only a handful of parallel tasks 

############
#  Setup   #
############
# -- Args
[ "$#" -ne 1 ] && echo "*EE* script requires one argument: EXP" && exit 1

# Default Experiment Def
ECEMODEL=EC-Earth3-AerChem
id=r1i1p1f1

# /ec/res4/scratch/nm6/cmorized-results/gw23/CMIP6Plus/TIPMIP/EC-Earth-Consortium/EC-Earth3-ESM-1/esm-up2p0-gwl2p0/r3i1p1f1

# ---8<------ HARDCODED PARAMETERS
EXP=$1
peryear=0                       # for range of years
pertable=1                      # uses $tag

dryrun=0
cleanup=0                       # DANGER ZONE !!!!! 0=archive, 1=delete files
# --->8------ HARDCODED PARAMETERS

. ./config.cfg
archive=${ecfs_dir}/${EXP}/cmor

emkdir -p $archive

# Sanity
if (( cleanup ))
then
    dryrun=1
    if ! els $archive >/dev/null 2>&1
    then
        echo "ERROR; Empty archive => refuse to delete local files"
        exit 1
    fi
fi

##############
# Utilities  #
##############
bckp_emcp () {
    emv -e $1  ${archive}/$1
    echmod 444 ${archive}/$1
}

maxsize=137438953472             # limit in bytes for emv as of October 2023 - hpc2020 (137GB)

split_move () {
    # split if larger than what emv can handle
    local f=$1
    actualsize=$(du -b "$f" | cut -f 1)
    if (( $actualsize > $maxsize )); then
        nn=$(( $actualsize / $maxsize + 1))
        split -n $nn -a 1 -d $f ${f}_
        \rm -f $f
        for k in $(eval echo {0..$((nn-1))})
        do 
            bckp_emcp ${f}_${k}
        done
    else
        bckp_emcp $f
    fi
}

not_empty_dir () {
    [[ ! -d "$1" ]] && return 1
    [ -n "$(ls -A $1)" ] && return 0 || return 1
}

# Database - Specific Experiment Def
#    - 'tag' indicates full year range of experiment, used for tarball that gather all years output
case $EXP in
    gw13) XPRMNT=esm-up2p0-gwl1p5 ; MIP=TIPMIP ; id=r3i1p1f1 ; ECEMODEL=EC-Earth3-ESM-1 ; tag='1926-2225';; 
    gw23) XPRMNT=esm-up2p0-gwl2p0 ; MIP=TIPMIP ; id=r3i1p1f1 ; ECEMODEL=EC-Earth3-ESM-1 ; tag='1951-2250';; 
    gw33) XPRMNT=esm-up2p0-gwl3p0 ; MIP=TIPMIP ; id=r3i1p1f1 ; ECEMODEL=EC-Earth3-ESM-1 ; tag='2001-2300';; 
    gw43) XPRMNT=esm-up2p0-gwl4p0 ; MIP=TIPMIP ; id=r3i1p1f1 ; ECEMODEL=EC-Earth3-ESM-1 ; tag='2051-2350';; 
    *) echo "Unknown experiment name: $EXP. Put your experiment in the database."
       usage
       exit 1
esac

datadir=$SCRATCH/cmorized-results/$EXP/CMIP6Plus
root=${MIP}/EC-Earth-Consortium/${ECEMODEL}/$XPRMNT/$id

cd $datadir

# Per year - for variables (typically 3D ones) that are too large for one tarball 
if (( peryear ))
then

    # -- APday variables
    tlist="ta8 hus8 hur ua8 va8 wap8 zg19 ta19 hus19 ua19 va19 wap19"
    
    # --- archives of X year at a time
    grp=10

    for table in $tlist
    do        
        ff=( $(find $root/APday/$table -name "*.nc" | sort) )
        nb=${#ff[@]}
        nn=$(( nb / grp + (nb % grp > 0) ))
        echo
        echo "Creating $nn archives of ${grp} years each for APday/$table"

        for k in $(eval echo {0..$((nn-1))})
        do
            ( is=$((k*grp))
              nf=$grp
              # ie=$(( (k+1) * grp - 1))
              # (( ie > (nb-1) )) && ie=$((nb-1))
              stamp1=$(echo $(basename ${ff[$is]}) | sed -nr "s|.*${id}_.*_(.*)-.*.nc|\1|p")
              tgt=${ECEMODEL}-$XPRMNT-$id-APday-$table-${stamp1}.tar
              echo " archive: $tgt"
              (( dryrun )) || tar -cvf $tgt ${ff[*]:${is}:${nf}}
              (( dryrun )) || split_move $tgt
              (( cleanup )) && \rm -f ${ff[*]:${is}:${nf}}
            ) &
        done
        wait
    done    
fi

# Per table - either variables or tables that fit in one tarball
if (( pertable ))
then
    # Per table - one APday variable / tarball (for SOME variables in that APday table)
    tlist="prsn prc clt psl rsus pr tas tasmax tasmin rsds rlds rlus rlut uas hurs vas hfls hfss huss sfcWind"
    for table in $tlist
    do
        ( tgt=${ECEMODEL}-$XPRMNT-$id-APday-$table-$tag.tar
          echo "tar -cvf $tgt $root/$table"
          (( dryrun )) || tar -cvf $tgt $root/APday/$table
          (( dryrun )) || ls -l $tgt
          (( dryrun )) || split_move $tgt
          (( cleanup )) && rm -rf $root/APday/$table
        ) &
    done
    wait ; echo

    # Per table - one variable / tarball (for ALL variables in those table)
    tlist="APmon OPmonLev OBmonLev"
    for table in $tlist
    do
        for var in $(ls $root/$table)
        do
            ( tgt=${ECEMODEL}-$XPRMNT-$id-$table-$var-$tag.tar
              echo "tar -cvf $tgt $root/$table"
              (( dryrun )) || tar -cvf $tgt $root/$table/$var
              (( dryrun )) || ls -l $tgt
              (( dryrun )) || split_move $tgt
              (( cleanup )) && rm -rf $root/$table/$var
            ) &
        done
        wait ; echo
    done
    
    # Per table - one table / tarball
    for table in OBmon LPday LPmon OPday OPmon SImon
    do
        ( tgt=${ECEMODEL}-$XPRMNT-$id-$table-$tag.tar
          echo "tar -cvf $tgt $root/$table"
          (( dryrun )) || tar -cvf $tgt $root/$table
          (( dryrun )) || ls -l $tgt
          (( dryrun )) || split_move $tgt
          (( cleanup )) && rm -rf $root/$table
        ) &
    done
    wait ; echo

    # Several tables at once
    tgt=${ECEMODEL}-$XPRMNT-$id-OTHERS-$tag.tar
    echo "tar -cvf $tgt $root/APfx $root/LImon $root/LPfx $root/LPyr $root/LPyrPt $root/OPfx $root/OPmonZ $root/SIday $root/SImonPt"
    if ! (( dryrun )) ; then
        ( tar -cvf $tgt $root/APfx $root/LImon $root/LPfx $root/LPyr $root/LPyrPt $root/OPfx $root/OPmonZ $root/SIday $root/SImonPt
          ls -l $tgt
          split_move $tgt
        ) &
    fi
    (( cleanup )) && rm -rf $root/APfx $root/LImon $root/LPfx $root/LPyr $root/LPyrPt $root/OPfx $root/OPmonZ $root/SIday $root/SImonPt
fi

wait
echo '*** SUCCESS ***'
if ! (( cleanup ))
then
    echo "els -l $archive"
    els -l $archive
fi
