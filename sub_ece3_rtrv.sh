#!/usr/bin/env bash

usage() {
    cat << EOT >&2
 Usage:
        ${0##*/} [-a account] [-c] [-o MODEL1 -o MODEL2 ...] EXP LEG

 Submit a job to retrieve output/restart from ONE leg of an experiment
 
 Options are:
    -o model    : an EC-Earth3 component for which output should be retrieve
    -a account  : specify a different special project for accounting (default ${ECE3_POSTPROC_ACCOUNT:-DEFAULT})
    -c          : check for success of previously submitted script
    -l          : page the log files of previously submitted script with a '${PAGER:-less} <log>' command
    -d depend   : add job dependency

EOT
}

set -e

# -- options
account=$ECE3_POSTPROC_ACCOUNT
dependency=
omodels=

while getopts "h?o:cd:a:" opt; do
    case "$opt" in
        h|\?)
            usage
            exit 0
            ;;
        o)  omodels="$OPTARG $omodels"
            ;;
        a)  account=$OPTARG
            ;;
        c)  chck=1
            ;;
        d)  dependency=$OPTARG
            ;;
        l)  page=1
    esac
done
shift $((OPTIND-1))


# -- Arg
if [ "$#" -ne 2 ]; then
    echo; echo " NEED TWO ARGUMENTS"; echo
    usage
    exit 0
fi


if [[ -z $omodels ]]
then 
    echo " No model selected!"
    exit 0
fi


# location of script to be submitted and its log 
OUT=$SCRATCH/tmp_ece3_rtrv
mkdir -p $OUT/log


# -- basic check
if (( $chck ))
then
    ls -l $OUT/log/rtrv_$1_$2.out
    grep "\*II\*" $OUT/log/rtrv_$1_$2.out
    echo
    exit
fi

# -- read log
if (( $page ))
then
    echo "Checking $OUT/log/rtrv_$1_$2.out"
    ${PAGER:-less} $OUT/log/rtrv_$1_$2.out
    exit
fi

# -- submit script
tgt_script=$OUT/rtrv_$1_$2

sed "s/<EXPID>/$1/" < retrieve-ece3.sh.tmpl > $tgt_script

sed -i "s/<OUTMODELS>/$omodels/" $tgt_script
sed -i "s/<RSTMODELS>/$rmodels/" $tgt_script
sed -i "s|<LEG>|$2|" $tgt_script

[[ -n $account ]] && \
    sed -i "s/<ACCOUNT>/$account/" $tgt_script || \
    sed -i "/<ACCOUNT>/ d" $tgt_script

[[ -n $dependency ]] && \
    sed -i "s/<DEPENDENCY>/$dependency/" $tgt_script || \
    sed -i "/<DEPENDENCY>/ d" $tgt_script

cd $OUT
qsub $tgt_script
