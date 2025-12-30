#!/usr/bin/env bash

# when=2025; sbatch -q nf -c 1 -n 1 -J saveic_$when -o log/ics/saveic.$when.out --wrap="./clean-store-saveic.sh fs01 ${when}0101 1951"

set -ue

usage() {
    cat << EOT >&2
 Usage:
        [sbatch] ${0##*/} EXP YYYYMMDD YSTART

 Pack Initial State created by save_ic at date YYYYMMDD for experiment
 EXP and store it on ECFS. YSTART is mandatory but used only for FreshWaterForcing.

 The Initial State is alse stored locally in $ISDIR (see config.cfg)

EOT
}

error() { echo "ERROR: $1" >&2; exit 1; }
urror() { echo "ERROR: $1" >&2; usage; exit 1; }

# -- ARGS
[[ "$#" -ne 3 ]]             && urror "Need THREE arguments!"
[[ ! $1 =~ ^[a-Z_0-9]{4}$ ]] && urror "argument EXPERIMENT name (=$1) should be a 4-character string"
[[ ! $2 =~ ^[0-9]{8}$ ]]     && urror "argument DATE (=$2) should be in YYYYMMDD"
[[ ! $3 =~ ^[0-9]{4}$ ]]     && urror "argument YSTART (=$3) should be in YYYY"

EXP=$1
YMD=$2
ystart=$3
YYYY=${YMD:0:4}

flat=1 # older way of working: flat directory where all restart are in the top dir, instead of subdir for each component
hl=    # hardlink. Use "-l" if not copying across file system

. ./config.cfg 

##########
# OUTPUT #
##########
emkdir -p  $ecfs_dir/$EXP/ics
tarb=saveic.${EXP}.${YMD}.tgz

WDIR=$ISDIR/$EXP/$YMD
mkdir -p $WDIR

INDIR=${runs_dir}/$EXP/save_ic

# Minimum sanity check
[[ ! -d $INDIR/$YMD ]]          && error "$PWD/$YMD directory missing"
[[ -z "$(ls -A $INDIR/$YMD)" ]] && error "$PWD/$YMD directory is empty"

#########
# OASIS #
#########
if [[ -d $INDIR/$YMD/oasis ]]
then
    mkdir $WDIR/oasis
    cp -u $INDIR/$YMD/oasis/* $WDIR/oasis
fi

#######
# TM5 #
#######
if [[ -d $INDIR/$YMD/tm5 ]]
then
    mkdir $WDIR/tm5
    cp -u $INDIR/$YMD/tm5/* $WDIR/tm5
fi
    
########
# NEMO #
########
if [[ -d $INDIR/$YMD/nemo ]]
then
    mkdir $WDIR/nemo
    cd $INDIR/$YMD/nemo
    last=$(ls -1 ${EXP}_*_restart_oce_*.nc | tail -1)
    TSTAMP=$(echo $last | sed -nr "s|${EXP}_(.*)_restart_oce_.*.nc|\1|p")
    NCORES=$(echo $last | sed -nr "s|${EXP}_.*_restart_oce_(.*).nc|\1|p")

    [[ ! -x ${RBLD_NEMO:-dummy} ]] && error "${RBLD_NEMO:-dummy} does not exist or is not executable"
    module load prgenv/intel hpcx-openmpi/2.9.0 netcdf4-parallel/4.9.1

    if [[ ! -e restart_oce.nc ]]
    then
        echo "Create generic NEMO OCE/ICE restart for $YMD ($TSTAMP)"
        $RBLD_NEMO ${EXP}_${TSTAMP}_restart_oce $((10#$NCORES + 1))
        $RBLD_NEMO ${EXP}_${TSTAMP}_restart_ice $((10#$NCORES + 1))

        # link the created files to the generic ones
        ln -s ${EXP}_${TSTAMP}_restart_oce.nc restart_oce.nc
        ln -s ${EXP}_${TSTAMP}_restart_ice.nc restart_ice.nc
    fi
    cp -u restart_{oce,ice}.nc $WDIR/nemo

    # Pisces
    if [[ -f ${EXP}_${TSTAMP}_restart_trc_0000.nc ]]
    then
        if [[ ! -e restart_trc.nc ]]
        then
            echo "Create generic NEMO TRC restart for $YMD ($TSTAMP)"
            $RBLD_NEMO ${EXP}_${TSTAMP}_restart_trc $((10#$NCORES + 1))
            ln -s ${EXP}_${TSTAMP}_restart_trc.nc restart_trc.nc
        fi
        cp -u restart_trc.nc $WDIR/nemo
    fi
    
    # cleanup=0
    # if (( cleanup ))
    # then
    #     [[ -e restart_oce.nc ]] && rm -f ${EXP}_${TSTAMP}_restart_oce_*
    #     [[ -e restart_oce.nc ]] && rm -f ${EXP}_${TSTAMP}_restart_ice_*
    #     [[ -e restart_trc.nc ]] && rm -f ${EXP}_${TSTAMP}_restart_trc_*
    # fi
fi

#######
# IFS #
#######
if [[ -d $INDIR/$YMD/ifs ]]
then
    mkdir $WDIR/ifs
    cd $INDIR/$YMD/ifs
    \rm -f filter_gg
    \rm -f filter_sh
    \rm -f ICMGG${EXP}+*-ifs_lastout
    \rm -f ICMGG${EXP}+*-out+init # very large
    \rm -f ICMSH${EXP}+*-ifs_lastout
    \rm -f ICMSH${EXP}+*-out+init # very large
    cp -u ICMGG${EXP}{INIT,INIUA} $WDIR/ifs
    cp -u ICMSH${EXP}INIT $WDIR/ifs
fi

#############
# LPJ-Guess #
#############
if [[ -d ${runs_dir}/$EXP/restart/lpjg ]]
then
    mkdir $WDIR/lpjg
    cp -uvr $hl ${runs_dir}/$EXP/restart/lpjg/*/lpjg_state_$YYYY $WDIR/lpjg
fi

########
# PISM #
########
if [[ -d ${runs_dir}/$EXP/restart/pism_grtes ]]
then
    mkdir $WDIR/pism_grtes
    cp -uv $hl ${runs_dir}/$EXP/restart/pism_grtes/*/pism2ece_forcing_for_$YYYY.nc         $WDIR/pism_grtes
    cp -uv $hl ${runs_dir}/$EXP/restart/pism_grtes/*/pism_grtes_restart-$((YYYY-1))1231.nc $WDIR/pism_grtes
fi

#####################
# FreshWaterForcing #
#####################
if [[ -d ${runs_dir}/$EXP/restart/fwf ]]
then
    mkdir $WDIR/fwf
    rstdir=${runs_dir}/$EXP/restart/fwf/$(printf %03d $((YYYY-ystart+1)))
    echo $rstdir
 
    # *** OBSOLETE, future contributions to fwf not used any longer ***
    ##     # copy 200 years with cumulative FWF after restart
    ##     [ -f $rstdir/CumulativeFreshwaterForcingAnomaly_${e}_Future.csv ] && \
    ##         awk -v leg=$((YYYY-ystart)) 'NR==1 || ( NR>leg && NR<=(leg+200)) {print}' \
    ##             $rstdir/CumulativeFreshwaterForcingAnomaly_${e}_Future.csv \
    ##             > fwf/CumulativeFreshwaterForcingAnomaly_${e}_Future.csv
 
    # running mean over last 30 years at restart
    awk -v leg=$((YYYY-ystart)) 'NR==1 || NR==(leg+1) {print}' \
        $rstdir/OceanSectorThetao_30yRM_${EXP}_*_*.csv \
        > $WDIR/fwf/OceanSectorThetao_lastRM.csv
 
    cp -uv $hl $rstdir/BasalMeltAnomaly_${EXP}.csv $WDIR/fwf
    cp -uv $hl $rstdir/OceanSectorThetao_piControl.csv $WDIR/fwf
    cp -uv $hl $rstdir/FWF_LRF_y????.nc $WDIR/fwf
fi

cd $WDIR
cd ..
tar -cvzf $tarb $YMD

# Archive
emv -o $tarb ${ecfs_dir}/$EXP/ics/$tarb
echmod 444 ${ecfs_dir}/$EXP/ics/$tarb
els -l ${ecfs_dir}/$EXP/ics/$tarb

(( flat )) && { cd $WDIR; for f in */*; do ln $f; done ; } || :
