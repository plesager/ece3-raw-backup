#! /usr/bin/env bash

#SBATCH --qos=nf
#SBATCH --cpus-per-task=24
#SBATCH --output=log/rtrv.%j.out
#SBATCH --time=12:00:00
#SBATCH --ntasks=1

set -e

usage() {
    cat << EOT >&2
 Usage:
        [sbatch] ${0##*/} [-c] [-s] [-o MODEL1 -o MODEL2 ...] [-r MODEL1 -r MODEL2 ...] EXP LEG

 Submit a job to retrieve OUTPUT and/or RESTART from ONE leg of one
 experiment and for any requested components.

 Options are HARDCODED (see below) for the time being. Idea:
    -r model    : an EC-Earth3 component for which restart should be retrieved
    -o model    : an EC-Earth3 component for which output should be retrieved
    -c          : check for success of a previous retrieval
    -s          : silent
    -l          : page the log of a previous retrieval with a '${PAGER:-less} <log>' command

EOT
}

set -eu
error() { echo "ERROR: $1" >&2; exit 1; }
urror() { echo "ERROR: $1" >&2; usage; exit 1; }

# -- HARDCODED OPTIONS - list of models for which output or restart are requested
out_models=  #"ifs"
rst_models="ifs nemo oasis"
verb=1

# while getopts "ho:r:cl" opt; do
#     case "$opt" in
#         h) usage; exit 0 ;;
#         o) out_models="$OPTARG $out_models" ;;
#         r) rst_models="$OPTARG $rst_models" ;;
#         c) chck=1 ;;
#         l) page=1 ;;
#         ?) echo "UNKNOWN OPTION"; usage; exit 1
#     esac
# done
# shift $((OPTIND-1))


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
    
    (( verb )) && echo "*II* getting output ${k3d} of ${model}"

    if [[ $model = tm5 ]] 
    then
        farch=output.${model}.${k3d}.tar
        for f in $(els ${ecfs_dir}/${exp}/${farch}*)
        do
            ( cd ${runs_dir}/${exp}
              ecp ${ecfs_dir}/${exp}/$f $f ) &
        done
        wait
        ( cd ${runs_dir}/${exp}
          [[ -f ${farch}_0 ]] && cat ${farch}_* > ${farch}  
          tar -xf ${farch}
          #rm -f output.${model}.${k3d}.tar*
        ) &
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
    
    (( verb )) && echo "*II* getting restart ${k3d} of ${model}"

    if [[ $model != tm5 ]] 
    then
        {
            ecp ${ecfs_dir}/${exp}/restart.${model}.${k3d}.tar restart.${model}.${k3d}.tar 
            tar -xvf restart.${model}.${k3d}.tar
        } &
    else
        echo "*EE* TM5 restart should be retrieved manually (only few files)"
    fi

done
wait

(( verb )) && echo " *II* SUCCESS ${exp} ${leg}"
