#! /usr/bin/env bash

#SBATCH --qos=nf
#SBATCH --ntasks=24
#SBATCH --output=log/del.%j.out
#SBATCH --time=06:00:00

set -e

usage() {
    cat << EOT >&2
 Usage:
        sbatch ${0##*/} [-o MODEL1 -o MODEL2 ...] EXP LEG

   REMOVE local output of ONE leg of one experiment and for any requested components.

 Options are:
    -o model    : an EC-Earth3 component for which local output should be remove

EOT
}

set -eu
error() { echo "ERROR: $1" >&2; exit 1; }
urror() { echo "ERROR: $1" >&2; usage; exit 1; }

# -- HARDCODED OPTIONS - list of components for which the local output is removed
out_models=ifs

# while getopts "ho:" opt; do
#     case "$opt" in
#         h) usage; exit 0 ;;
#         o) out_models="$OPTARG $out_models" ;;
#         ?) echo "UNKNOWN OPTION"; usage; exit 1
#     esac
# done
# shift $((OPTIND-1))

# -- ARG
[[ "$#" -ne 2 ]]             && urror "Need TWO arguments!"
[[ ! $1 =~ ^[a-Z_0-9]{4}$ ]] && urror "argument EXPERIMENT name (=$1) should be a 4-character string"
[[ ! $2 =~ ^[0-9]+$ ]]       && urror "argument LEG_NUMBER (=$2) should be a number"

if [[ -z $out_models && -z $rst_models ]]
then 
    echo " No model selected!"
    exit 0
fi

exp=$1
leg=$((10#$2))

. ./config.cfg 

k3d=$(printf %03d ${leg})

for model in ${out_models}
do
    outdir=${runs_dir}/$exp/output/$model/$k3d
    [[ ! -d $outdir ]] && continue
    cd $outdir
    for f in *
    do
        [[ -f $f ]] && rm -f $f
    done
done

echo " *II* SUCCESS ${exp} ${leg}"
