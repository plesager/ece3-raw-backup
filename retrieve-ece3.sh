#! /usr/bin/env bash

#SBATCH --qos=nf
#SBATCH --ntasks=24
#SBATCH --output=rtrv.%j.out
#SBATCH --time=06:00:00

 #######################################
 # RETRIEVES output/restart from ECFS. #
 # Two inputs, EXP and LEG number.     #
 #######################################

set -e

usage() {
    cat << EOT >&2
 Usage:
        [sbatch] ${0##*/} [-c] [-o MODEL1 -o MODEL2 ...] [-r MODEL1 -r MODEL2 ...] EXP LEG

 Submit a job to retrieve output/restart from ONE leg of one experiment
 
 Options are:
    -r model    : an EC-Earth3 component for which restart should be retrieved
    -o model    : an EC-Earth3 component for which output should be retrieved
    -c          : check for success of previous retrieval
    -l          : page the log of previous retrieval with a '${PAGER:-less} <log>' command

EOT
}

set -eu
error() { echo "ERROR: $1" >&2; exit 1; }
urror() { echo "ERROR: $1" >&2; usage; exit 1; }

# -- OPTIONS
out_models=
rst_models=

while getopts "ho:r:cl" opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        o) out_models="$OPTARG $out_models" ;;
        r) rst_models="$OPTARG $rst_models" ;;
        c) chck=1 ;;
        l) page=1
        ?) echo "UNKNOWN OPTION"; usage; exit 1
    esac
done
shift $((OPTIND-1))


# -- ARG
[[ "$#" -ne 2 ]] && urror "Need TWO arguments!"
[[ ! $1 =~ ^[a-Z_0-9]{4}$ ]] && urror "argument EXPERIMENT name (=$1) should be a 4-character string"
[[ ! $2 =~ ^[0-9]+$ ]] && urror "argument LEG_NUMBER (=$2) should be a number"


if [[ -z $out_models && -z $rst_models ]]
then 
    echo " No model selected!"
    exit 0
fi

exp=$1
leg=$((10#$2))

######################### Hardcoded options ###########################
. ./config.cfg 

# tar_restart=1 (assumed that's used in backup_ece3.sh)
############################# options #############################


k3d=$(printf %03d ${leg})

for model in ${out_models}
do
    mkdir -p ${runs_dir}/${exp}/output/${model}/${k3d}
    cd ${runs_dir}/${exp}/output/${model}/${k3d}
    
    echo "*II* getting output ${k3d} of ${model}"

    if [[ $model = tm5 ]] 
    then
        ( cd ${runs_dir}/${exp}
            ecp ${ecfs_dir}/${exp}/output.${model}.${k3d}.tar output.${model}.${k3d}.tar
            tar -xf output.${model}.${k3d}.tar 
            rm -f output.${model}.${k3d}.tar ) &
    else
        for f in $(els ${ecfs_dir}/${exp}/output/${model}/${k3d})
        do
            ( ecp ${ecfs_dir}/${exp}/output/${model}/${k3d}/${f} ${f} 
                [[ $f =~ .*gz$ ]] && gunzip $f ) &
        done
        wait
    fi
done
wait

for model in ${rst_models}
do
    mkdir -p ${runs_dir}/${exp}/restart/${model}/${k3d}
    cd ${runs_dir}/${exp}
    
    echo "*II* getting restart ${k3d} of ${model}"

    if [[ $model != tm5 ]] 
    then
        {
            ecp ${ecfs_dir}/${exp}/restart.${model}.${legnb}.tar restart.${model}.${legnb}.tar 
            tar -xvf restart.${model}.${legnb}.tar
        } &
    else
        echo "*EE* TM5 restart should be retrieved manually (only few files)"
    fi

done
wait

echo " *II* SUCCESS ${exp} ${leg}"
