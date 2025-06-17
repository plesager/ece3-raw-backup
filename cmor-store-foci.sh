#!/usr/bin/env bash

#SBATCH --qos=nf
#SBATCH --cpus-per-task=12
#SBATCH --output=log/store.%j.out
#SBATCH --ntasks=1
##SBATCH --time=12:00:00

set -ue

############
# Strategy #
############

# Considering the followings:
#  - we do not normally store cmorized data: this is more of a one-off
#    job for the FOCI project. We still store all "in case of some study"
#    but there is no plan for publishing, and no need to write a
#    script that could handle other experiments.
#  - we are strictly interested in the downscaling data: they are the
#    one to be shared (all 6hr basically). So it is fine to pack other
#    data as we want (eg mix tables and/or years in a tarball) but
#    those for the project should be user-friendly to some extend. So
#    I do not use an automatic split of tarball, as it is done in backup_ece3.sh
#  - We are interesting in few periods, namely:
#    - 2015-2024 (U. Thessaloniki)
#    - 2045-2055 (FOCI), with 2046-2055 (U. Thessaloniki)  -- PRIORITY #1 --
#    - 2091-2100 (U. Thessaloniki)


# Default Experiment Def
ECEMODEL=EC-EARTH-AerChem
id=r1i1p1f1

# ---8<------ Hardcoded parameters
EXP=fs01
WHATSUP=FOCI
dryrun=0

pertable=0                      # Once: uses $tag, requires manual cleanup
#v1: tag='2015-2063'
tag='2064-2100'

peryear=1                       # for range of years which is set at the CLI with $1 and $2. Although parallelized, the limit on number of concurrent emv means you should submit about one handful of years 
cleanup=1                       # DANGER ZONE !!!!! 0=archive, 1=delete files ; does not apply to "pertable"
# --->8------

. ./config.cfg
archive=${ecfs_dir}/${EXP}/cmor

emkdir -p $archive

bckp_emcp () {
    emv -e $1  ${archive}/$1
    echmod 444 ${archive}/$1
}

# Database - Specific Experiment Def
case $EXP in
    hist) XPRMNT=historical ;           MIP=CMIP ;;
    fhi0) XPRMNT=historical ;           MIP=CMIP ;  id=r1i1p4f1 ;;
    pict) XPRMNT=piControl ;            MIP=CMIP ;;
    a4co) XPRMNT=abrupt-4xCO2 ;         MIP=CMIP ;;
    piNF) XPRMNT=hist-piNTCF ;          MIP=AerChemMIP ;;
    fsc2) XPRMNT=ssp245 ;               MIP=ScenarioMIP ;  id=r1i1p4f1 ;;
    s001) XPRMNT=ssp370 ;               MIP=ScenarioMIP ;;
    fs01) XPRMNT=ssp370 ;               MIP=ScenarioMIP ;  id=r1i2p1f1 ;;
    s2hh) XPRMNT=highres-future ;       MIP=HighResMIP ; id=r1i1p2f1 ;;
    *)
        echo "Unknown experiment name: $EXP. Put your experiment in the database."
        usage
        exit 1
esac

datadir=$SCRATCH/cmorized-results/$EXP/CMIP6
root=${MIP}/EC-Earth-Consortium/EC-Earth3-AerChem/$XPRMNT/$id

cd $datadir

# Per year
if (( peryear ))
then
    # -- Args
    [ "$#" -ne 2 ] && echo "*EE* script requires two arguments: YEARSTART YEAREND" && exit 1
    [[ ! $1 =~ ^[0-9]{4}$ ]] && echo "*EE* argument YEARSTART (=$1) should be a 4-digit number" && exit 1
    [[ ! $2 =~ ^[0-9]{4}$ ]] && echo "*EE* argument YEAREND (=$2) should be a 4-digit number" && exit 1

    #v1: for year in {2016..2024}
    #v1: for year in {2025..2044}
    #v1: for year in {2045..2055}
    #v1: for year in {2056..2063}
    #for year in {2064..2070}
    for year in $(eval echo {$1..$2})
    do
        # No split (Note that 6hrPlev and 6hrPlevPt are combined here)
        for table in 3hr 6hrPlev E3hrPt day
        do
            flist=$SCRATCH/cmorised-results-flist-$WHATSUP-$table-$year
            if [[ ! -s $flist ]] && (( cleanup ))
            then
                echo "ERROR unless you know - then comment"
                exit 1
            fi
            [[ ! -s $flist ]] && find . -name "*_${table}*_EC-Earth3-AerChem_${XPRMNT}_${id}_g?_${year}*.nc" | sort > $flist
            if (( cleanup ))
            then
                ( echo "Remove files from $flist"
                  <$flist xargs rm
                ) &
            else
                ( tgt=EC-Earth3-AerChem-$WHATSUP-$id-$table-$year.tar
                  echo "tar -cvf $tgt -T $flist"
                  (( dryrun )) || tar -cvf $tgt -T $flist
                  (( dryrun )) || bckp_emcp $tgt
                ) &
            fi
        done

        # Require split in two
        for table in AER6hrPt
        do
            flist=$SCRATCH/cmorised-results-flist-$WHATSUP-$table-$year
            if [[ ! -s $flist ]]
            then
                find . -name *_${table}_EC-Earth3-AerChem_${XPRMNT}_${id}_g?_${year}*.nc | sort > $flist
                split -d -a1 -n r/2 $flist $flist-part
            fi
            for part in {0..1}
            do
                if (( cleanup ))
                then
                    ( echo "Remove files from $flist-part$part"
                      <$flist-part$part xargs rm
                    ) &
                else
                    ( tgt=EC-Earth3-AerChem-$WHATSUP-$id-$table-$year-part$part.tar
                      echo "tar -cvf $tgt -T $flist-part$part"
                      (( dryrun )) || tar -cvf $tgt -T $flist-part$part
                      (( dryrun )) || bckp_emcp $tgt
                    ) &
                fi
            done
        done

        # Require split in three
        for table in 6hrLev CF3hr
        do
            flist=$SCRATCH/cmorised-results-flist-$WHATSUP-$table-$year
            if [[ ! -s $flist ]]
            then
                find . -name *_${table}_EC-Earth3-AerChem_${XPRMNT}_${id}_g?_${year}*.nc | sort > $flist
                split -d -a1 -n r/3 $flist $flist-part
            fi
            for part in {0..2}
            do
                if (( cleanup ))
                then
                    ( echo "Remove files from $flist-part$part"
                      <$flist-part$part xargs rm
                    ) &
                else
                    ( tgt=EC-Earth3-AerChem-$WHATSUP-$id-$table-$year-part$part.tar
                      echo "tar -cvf $tgt -T $flist-part$part"
                      (( dryrun )) || tar -cvf $tgt -T $flist-part$part
                      (( dryrun )) || bckp_emcp $tgt
                    ) &
                fi
            done
        done

    done
fi

if (( pertable ))
then
    # Per table - one table / tarball
    for table in Omon AERhr AERmon Amon CFmon E3hr AERday CFday Oday
    do
        ( tgt=EC-Earth3-AerChem-$WHATSUP-$id-$table-$tag.tar
          echo "tar -cvf $tgt $root/$table"
          (( dryrun )) || tar -cvf $tgt $root/$table
          (( dryrun )) || ls -l $tgt
          (( dryrun )) || bckp_emcp $tgt
          #(( cleanup )) && rm -rf $root/Omon $root/AERhr $root/AERmon $root/Amon $root/CFmon $root/E3hr $root/AERday $root/CFday $root/Oday
        ) &
    done

    # Per table - several tables at once
    tgt=EC-Earth3-AerChem-$WHATSUP-$id-OTHERS-$tag.tar
    echo "tar -cvf $tgt $root/Emon $root/SIday $root/SImon $root/Lmon $root/LImon $root/AERmonZ"
    if ! (( dryrun )) ; then
        ( tar -cvf $tgt $root/Emon $root/SIday $root/SImon $root/Lmon $root/LImon $root/AERmonZ
          ls -l $tgt
          bckp_emcp $tgt
        ) &
        #(( cleanup )) && rm -rf $root/Emon $root/SIday $root/SImon $root/Lmon $root/LImon $root/AERmonZ
    fi

    # Once - fixed fields
    tgt=EC-Earth3-AerChem-$WHATSUP-$id-FX.tar
    echo "tar -cvf $tgt $root/fx $root/Ofx"
    if ! (( dryrun )) ; then
        tar -cvf $tgt $root/fx $root/Ofx
        ls -l $tgt
        bckp_emcp $tgt
    fi
fi

wait
echo '*** SUCCESS ***'
if ! (( cleanup ))
then
    echo "els -l $archive"
    els -l $archive
fi
