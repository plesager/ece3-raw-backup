#!/usr/bin/env bash

usage()
{
    echo "Usage:"
    echo "       ${0##*/} [-r] [-f NB] EXP"
    echo
    echo "Check the backup of EVERY legs of one run, by listing"
    echo "output and restart directories that are not empty."
    echo
    echo "Options are:"
    echo "   -r            : list the [R]emote target dir"
    echo "   -f LEG_NUMBER : specify leg number, for which the output/restart [F]iles are listed"
    echo
}

set -e

runs_dir="${SCRATCH}/ECEARTH-RUNS/"
ecfs_dir="ec:/${USER}/ECEARTH-RUNS/"

# -- options

while getopts "rf:h?" opt; do
    case "$opt" in
        h|\?)
            usage
            exit 0
            ;;
        r) remote=1
            ;;
        f)  full=$OPTARG
    esac
done
shift $((OPTIND-1))


# -- Arg
if [ "$#" -ne 1 ]; then
    echo; echo " NEED ONE ARGUMENT, NO MORE, NO LESS!"; echo
    usage
    exit 0
fi

# -- Utils
not_empty_dir () {
    [[ ! -d "$1" ]] && return 1
    [ -n "$(ls -A $1)" ] && return 0 || return 1
}

# -- basic check
for model in ifs nemo
do
    for ff in output restart
    do        
        if [ -d ${runs_dir}/$1/${ff}/${model} ]
        then
            echo ; echo "*II* checking ${model} ${ff}" ; echo

            cd ${runs_dir}/$1/${ff}/${model}
            #quick-but-not-rigourous: du -sh * | grep -v "^4.0K"

            for ddd in *
            do 
                if not_empty_dir $ddd
                then
                    du -sh $ddd
                    (( $full )) && [[ $(printf %03d $full) = $ddd ]] && \
                        ls ${runs_dir}/$1/${ff}/${model}/$(printf %03d $full)
                fi
            done
        fi
    done
done

if (( remote ))
then
    echo ; echo "*II* checking top dir" ; echo

    els -l $ecfs_dir/$1

    for model in ifs nemo
    do
        for ff in output restart
        do        
            echo ; echo "*II* checking ${model} ${ff}" ; echo
            els -l $ecfs_dir/$1/${ff}/${model}

            for ddd in $(els $ecfs_dir/$1/${ff}/${model})
            do
                if (( detail ))
                then
                    els -l $ecfs_dir/$1/${ff}/${model}/$ddd
                else
                    echo $ddd $(els $ecfs_dir/$1/${ff}/${model}/$ddd | wc -w)
                fi
            done
        done
    done
fi
