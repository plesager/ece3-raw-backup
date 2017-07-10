#!/usr/bin/env bash

usage()
{
    echo "Usage:"
    echo "       sub_prmvr_bckp.sh [-a account] [-c] EXP LEG"
    echo
    echo "Submit a job to backup output/restart from ONE leg of a run"
    echo 
    echo "Options are:"
    echo "   -a account  : specify a different special project for accounting (default ${ECE3_POSTPROC_ACCOUNT:-DEFAULT})"
    echo "   -c          : check for success of previously submitted script with a '${PAGER:-less} <log>' command"
    echo
}

set -e

# -- options
account=$ECE3_POSTPROC_ACCOUNT

while getopts "h?ca:" opt; do
    case "$opt" in
        h|\?)
            usage
            exit 0
            ;;
        a)  account=$OPTARG
            ;;
        c)  chck=1
    esac
done
shift $((OPTIND-1))


# -- Arg
if [ "$#" -ne 2 ]; then
   usage
   exit 0
fi


# location of script to be submitted and its log 
OUT=$SCRATCH/tmp_primavera
mkdir -p $OUT


# -- basic check
if (( $chck ))
then
    echo "Checking $OUT/log/bck_prmvr_$1_$2.out"
    ${PAGER:-less} $OUT/log/bck_prmvr_$1_$2.out
    exit
fi

# -- submit script
tgt_script=$OUT/prmvr_$1_$2

sed "s/<EXPID>/$1/" < backup_primavera.sh.tmpl > $tgt_script

[[ -n $account ]] && \
    sed -i "s/<ACCOUNT>/$account/" $tgt_script || \
    sed -i "/<ACCOUNT>/ d" $tgt_script

sed -i "s|<LEG>|$2|" $tgt_script

cd $OUT
qsub $tgt_script
qstat -wu $USER
