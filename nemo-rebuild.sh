#!/usr/bin/env bash

# sbatch -q nf -c 1 -n 1 -J nmrbld ./nemo-rebuild.sh EXP PATH

set -ue

usage() {
    cat << EOT >&2
 Usage:
        [sbatch] ${0##*/} EXP PATH

        EXP: 4-letter  experiment id
        PATH: where all nemo restart files are

EOT
}

error() { echo "ERROR: $1" >&2; exit 1; }
urror() { echo "ERROR: $1" >&2; usage; exit 1; }

# -- ARGS
[[ "$#" -ne 2 ]]             && urror "Need TWO arguments!"
[[ ! $1 =~ ^[a-Z_0-9]{4}$ ]] && urror "argument EXPERIMENT name (=$1) should be a 4-character string"

EXP=$1
YMD=$2

. ./config.cfg 

########
# NEMO #
########
if [[ -d $YMD ]]
then
    cd $YMD
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

    # Pisces
    if [[ -f ${EXP}_${TSTAMP}_restart_trc_0000.nc ]]
    then
        if [[ ! -e restart_trc.nc ]]
        then
            echo "Create generic NEMO TRC restart for $YMD ($TSTAMP)"
            $RBLD_NEMO ${EXP}_${TSTAMP}_restart_trc $((10#$NCORES + 1))
            ln -s ${EXP}_${TSTAMP}_restart_trc.nc restart_trc.nc
        fi
    fi
    
else
    error "$YMD not a directory or missing"
fi
