#!/usr/bin/env bash

usage() {
    cat << EOT >&2
 Usage:
        ${0##*/} [-l] [-r] [-f NB] [-o MODEL1 -o MODEL2 ...] EXP
 
 Check the backup of EVERY legs of one run, by listing
 output and restart directories that are not empty.
 
 Options are:
    -b            : [B]asic, ie check that the logs report success
    -l            : list non-empty [L]ocal dirs and their size
    -r            : list [R]emote dirs and number of file (or files themselves in case of restart tarballs and tm5 output)
    -o model      : limit to ouput from model. Can be several. Default is all possible.
    -f LEG_NUMBER : specify leg number, for which the output/restart [F]iles are listed

EOT
}

set -e

. ./config.cfg 

# -- options
omodels=
while getopts "vbrlo:f:h?" opt; do
    case "$opt" in
        h|\?)
            usage
            exit 0
            ;;
        b) basic=1 ;;
        l) local=1 ;;
        o) omodels="$OPTARG $omodels" ;;
        r) remote=1 ;;
        f) full=$OPTARG ;;
        v) verbose=1
    esac
done
shift $((OPTIND-1))


# -- Arg
if [ "$#" -ne 1 ]; then
    echo; echo " NEED ONE ARGUMENT, NO MORE, NO LESS!"; echo
    usage
    exit 0
fi

if [[ -z $omodels ]]            # default to all models
then 
    omodels="ifs nemo tm5 oasis"
    #exit 0
fi


# -- Utils
not_empty_dir () {
    [[ ! -d "$1" ]] && return 1
    [ -n "$(ls -A $1)" ] && return 0 || return 1
}

# -- check

if (( basic ))
then
    # Assumption about the log file specified when calling "sbatch -o logfile backup_ece3.sh ..."
    log=log/${exp}-$(printf %03d $i).out
    if [[ -f $log ]]
    then
        (( verbose )) && { echo; echo " -- Check $log --" ; 
                           grep "ECMWF.*INFO.*ExitCode" $log ; 
                           grep "ECMWF.*INFO.*State" $log ; }
        excode=$(sed -nr "s|.*INFO.* ExitCode *: ||"p $log)
        status=$(sed -nr "s|.*INFO.*State *: ||"p $log)
        second=$(sed -nr "s|.*INFO.* ElapsedRaw *: ||"p $log)
        if [[ $excode = '0:0' && $status = COMPLETED ]]; then
            (( verbose )) && echo "Looks like it went ok."
        fi
        echo -n "Runtime (hh:mm:ss): "
        echo $second | awk '{printf "%d:%02d:%02d\n", $1/3600, ($1/60)%60, $1%60}'
    else
        echo "submit script log not found: $log"
    fi
fi


if (( local ))
then
    for model in $omodels
    do
        for ff in output restart
        do        
            if [ -d ${runs_dir}/$1/${ff}/${model} ]
            then
                echo ; echo "*II* checking ${model} ${ff} [dir_size leg_nb]" ; echo

                cd ${runs_dir}/$1/${ff}/${model}
            #quick-but-not-rigourous: du -sh * | grep -v "^4.0K"

                for ddd in *
                do 
                    if not_empty_dir $ddd
                    then
                        du -sh $ddd
                        (( $full )) && [[ $(printf %03d $full) == $ddd ]] && \
                            ls ${runs_dir}/$1/${ff}/${model}/$(printf %03d $full)
                    fi
                done
            fi
        done
    done
fi

if (( remote ))
then

    # echo ; echo "*II* checking REMOTE top dir" ; echo
    # els -l $ecfs_dir/$1

    # -- Output
    for model in ${omodels//tm5}
    do
        [[ $model == oasis ]] && continue
        for ff in output
        do        
            echo ; echo "*II* checking REMOTE ${model} ${ff} [leg_nb/ nb_files]" ; echo
            #els -l $ecfs_dir/$1/${ff}/${model}

            for ddd in $(els $ecfs_dir/$1/${ff}/${model})
            do
                if (( $full )) && [[ $(printf %03d/ $full) = $ddd ]]
                then
                    echo $ddd
                    els -l $ecfs_dir/$1/${ff}/${model}/$ddd
                else
                    echo $ddd $(els $ecfs_dir/$1/${ff}/${model}/$ddd | wc -w)
                fi
            done
        done
    done

    if [[ $omodels =~ tm5 ]]
    then
        echo ; echo "*II* checking REMOTE tm5 output" ; echo
        els -l $ecfs_dir/$1/output.tm5.*.tar
    fi

    # -- Restart
    for model in ${omodels//tm5}
    do        
        echo ; echo "*II* checking REMOTE RESTART for ${model}" ; echo
        els -l $ecfs_dir/$1/restart.${model}.*.tar || :
    done

    if [[ $omodels =~ tm5 ]]
    then
        echo ; echo "*II* checking REMOTE RESTART for tm5" ; echo
        els -l $ecfs_dir/$1/tm5-restart-*.tar
    fi

fi
