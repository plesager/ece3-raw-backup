#!/usr/bin/env bash

usage()
{
    echo "Usage:"
    echo "       ${0##*/} [-a account] [-c] EXP LEG"
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
    echo; echo " NEED TWO ARGUMENTS, NO MORE, NO LESS!"; echo
    usage
    exit 0
fi


# location of script to be submitted and its log 
OUT=$SCRATCH/tmp_ece3_bckp
mkdir -p $OUT/log


# -- basic check
if (( $chck ))
then
    echo "Checking $OUT/log/bckp_$1_$2.out"
    ${PAGER:-less} $OUT/log/bckp_$1_$2.out
    exit
fi

# -- submit script
tgt_script=$OUT/bckp_$1_$2

sed "s/<EXPID>/$1/" < backup_ecearth3.sh.tmpl > $tgt_script

[[ -n $account ]] && \
    sed -i "s/<ACCOUNT>/$account/" $tgt_script || \
    sed -i "/<ACCOUNT>/ d" $tgt_script

sed -i "s|<LEG>|$2|" $tgt_script

cd $OUT
qsub $tgt_script
qstat -wu $USER
