#!/usr/bin/env bash

# when=2025; sbatch -q nf -c 1 -n 1 -J saveic_$when -o log/saveic.$when.out --wrap="./clean-store-saveic.sh fs01 ${when}0101"

set -ue

usage() {
    cat << EOT >&2
 Usage:
        [sbatch] ${0##*/} EXP YYYYMMDD

 Pack Initial State created by save_ic at date YYYYMMDD for experiment
 EXP and store it on ECFS

EOT
}

set -eu
error() { echo "ERROR: $1" >&2; exit 1; }
urror() { echo "ERROR: $1" >&2; usage; exit 1; }

# -- ARGS
[[ "$#" -ne 2 ]]             && urror "Need TWO arguments!"
[[ ! $1 =~ ^[a-Z_0-9]{4}$ ]] && urror "argument EXPERIMENT name (=$1) should be a 4-character string"
[[ ! $2 =~ ^[0-9]{8}$ ]]     && urror "argument DATE (=$2) should be in YYYYMMDD"

EXP=$1
YMD=$2

. ./config.cfg 

# -- OUTPUT
emkdir -p  $ecfs_dir/$EXP
tarb=saveic.${EXP}.${YMD}.tgz

# -- WORK
cd ${runs_dir}/$EXP/save_ic

# Minimum sanity check
[[ ! -d $YMD ]]          && error "$PWD/$YMD directory missing"
[[ -z "$(ls -A $YMD)" ]] && error "$PWD/$YMD directory is empty"

# If NEMO is one of the components, check if rebuild (and link) was applied
if [[ -d $YMD/nemo ]]
then
    cd $YMD/nemo
    last=$(ls -1 ${EXP}_*_restart_ice_*.nc | tail -1)
    TSTAMP=$(echo $last | sed -nr "s|${EXP}_(.*)_restart_ice_.*.nc|\1|p")
    NCORES=$(echo $last | sed -nr "s|${EXP}_.*_restart_ice_(.*).nc|\1|p")
    
    if [[ ! -e restart_oce.nc ]]
    then
        echo "Create generic NEMO restart for $YMD ($TSTAMP)"
        [[ ! -x ${RBLD_NEMO:-dummy} ]] && error "${RBLD_NEMO:-dummy} does not exist or is not executable"
        module load prgenv/intel hpcx-openmpi/2.9.0 netcdf4-parallel/4.9.1
        $RBLD_NEMO ${EXP}_${TSTAMP}_restart_oce $((10#$NCORES + 1))
        $RBLD_NEMO ${EXP}_${TSTAMP}_restart_ice $((10#$NCORES + 1))

        # link the created files to the generic ones
        ln -s ${EXP}_${TSTAMP}_restart_oce.nc restart_oce.nc
        ln -s ${EXP}_${TSTAMP}_restart_ice.nc restart_ice.nc
    fi
    cd ->/dev/null 
fi

# List
flist=
[[ -d $YMD/ifs   ]] && flist="$YMD/ifs/ICMGG${EXP}INIT $YMD/ifs/ICMSH${EXP}INIT $YMD/ifs/ICMGG${EXP}INIUA"
[[ -d $YMD/nemo  ]] && flist="$flist $YMD/nemo/*restart_*ce.nc"
[[ -d $YMD/oasis ]] && flist="$flist $YMD/oasis/*"
[[ -d $YMD/tm5   ]] && flist="$flist $YMD/tm5/*"

tar -cvzf $tarb $flist

# Archive
emv -e $tarb ${ecfs_dir}/$EXP/$tarb
echmod 444 ${ecfs_dir}/$EXP/$tarb

# Clean up
if [[ -d $YMD/ifs ]]
then
    cd $YMD/ifs
    \rm -f filter_gg
    \rm -f filter_sh
    \rm -f ICMGG${EXP}+*-ifs_lastout
    \rm -f ICMGG${EXP}+*-out+init # very large
    \rm -f ICMSH${EXP}+*-ifs_lastout
    \rm -f ICMSH${EXP}+*-out+init # very large
    #KEEP ICMGG${EXP}INIT
    #KEEP ICMGG${EXP}INIUA
    #KEEP ICMSH${EXP}INIT
    cd -
fi

if [[ -d $YMD/nemo ]]
then
    cd $YMD/nemo
    rm -f ${EXP}_${TSTAMP}_restart_oce_*
    rm -f ${EXP}_${TSTAMP}_restart_ice_*
    cd -
fi
