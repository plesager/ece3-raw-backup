#!/usr/bin/env bash

#SBATCH --qos=nf
#SBATCH --cpus-per-task=24
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
tag='2015-2063'
WHATSUP=FOCI
cleanup=0                       # DANGER ZONE !!!!! 0=archive, 1=delete files
dryrun=0
# --->8------

. ./config.cfg
archive=${ecfs_dir}/${EXP}/cmor

emkdir -p $archive

bckp_emcp () {
    emv -e $1  ${archive}/$1
    echmod 444 ${archive}/$1
}

# Specific Experiment Def
case $EXP in
    hist) XPRMNT=historical ;           MIP=CMIP ;;
    fhi0) XPRMNT=historical ;           MIP=CMIP ;  id=r1i1p4f1 ;;
    pict) XPRMNT=piControl ;            MIP=CMIP ;;
    a4co) XPRMNT=abrupt-4xCO2 ;         MIP=CMIP ;;
    piNF) XPRMNT=hist-piNTCF ;          MIP=AerChemMIP ;;
    fsc2) XPRMNT=ssp245 ;               MIP=ScenarioMIP ;  id=r1i1p4f1 ;;
    s001) XPRMNT=ssp370 ;               MIP=ScenarioMIP ;;
    fs01) XPRMNT=ssp370 ;               MIP=ScenarioMIP ;  id=r1i2p1f1 ;;
    s002) XPRMNT=ssp370-lowNTCF ;       MIP=AerChemMIP ;;
    s003) XPRMNT=ssp370-lowNTCFCH4 ;    MIP=AerChemMIP ;;
    sst5) XPRMNT=ssp370SST ;            MIP=AerChemMIP ;;
    sst6) XPRMNT=ssp370SST-lowNTCF ;    MIP=AerChemMIP ;;
    sst7) XPRMNT=ssp370SST-lowNTCFCH4 ; MIP=AerChemMIP ;;
    onep) XPRMNT=1pctCO2;        MIP=CMIP ;;
    hpae) XPRMNT=hist-piAer ;    MIP=AerChemMIP ;;
    amip) XPRMNT=amip ;          MIP=CMIP ;;
    s004) XPRMNT=ssp370pdSST ;   MIP=AerChemMIP ;;
    hsp4) XPRMNT=histSST-piCH4 ; MIP=AerChemMIP ;;
    hspr) XPRMNT=histSST-piAer ; MIP=AerChemMIP ;;
    pic1) XPRMNT=piClim-control ; MIP=RFMIP ;;
    pic2) XPRMNT=piClim-NTCF ;    MIP=AerChemMIP ;;
    pic3) XPRMNT=piClim-CH4 ;     MIP=AerChemMIP ;;
    pic4) XPRMNT=piClim-aer ;           MIP=RFMIP ;;
    xh2t) XPRMNT=highres-future ;       MIP=HighResMIP ; id=r2i1p2f1 ;;
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
# for year in {2015..2024}
# do
#     # No split (Note that 6hrPlev and 6hrPlevPt are combined here)
#     for table in 3hr 6hrPlev E3hrPt day
#     do
#         ( flist=$SCRATCH/cmorised-results-flist-$WHATSUP-$table-$year
#           find . -name "*_${table}*_EC-Earth3-AerChem_${XPRMNT}_${id}_g?_${year}*.nc" | sort > $flist
#           tgt=EC-Earth3-AerChem-$WHATSUP-$id-$table-$year.tar
#           echo "tar -cvf $tgt -T $flist"
#           (( dryrun )) || tar -cvf $tgt -T $flist
#           (( dryrun )) || bckp_emcp $tgt
#         ) &
#     done

#     # Require a split
#     for table in 6hrLev AER6hrPt CF3hr
#     do
#         flist=$SCRATCH/cmorised-results-flist-$WHATSUP-$table-$year
#         find . -name *_${table}_EC-Earth3-AerChem_${XPRMNT}_${id}_g?_${year}*.nc | sort > $flist
#         # split
#         split -d -a1 -n r/2 $flist $flist-part
#         for part in {0..1}
#         do
#             ( tgt=EC-Earth3-AerChem-$WHATSUP-$id-$table-$year-part$part.tar
#               echo "tar -cvf $tgt -T $flist-part$part"
#               (( dryrun )) || tar -cvf $tgt -T $flist-part$part
#               (( dryrun )) || bckp_emcp $tgt
#             ) &
#         done
#     done

# done

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

wait
echo '*** SUCCESS ***'
echo "els -l $archive"
els -l $archive

