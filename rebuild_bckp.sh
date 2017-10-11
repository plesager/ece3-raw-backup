#! /usr/bin/env bash

#PBS -N rebuild
#PBS -q ns
#PBS -l EC_billing_account=nlchekli
#PBS -l walltime=03:00:00
#PBS -j oe

exp=actl

runs_dir="${SCRATCH}/ECEARTH-RUNS/"

set -e

not_empty_dir () {
     [ -n "$(ls -A $1)" ] && return 0 || return 1
}

# -- basic check
for model in ifs nemo
do
    for ff in output restart
    do        
        if [ -d ${runs_dir}/${exp}/${ff}/${model} ]
        then
            echo ; echo "*II* checking ${model} ${ff}" ; echo

            cd ${runs_dir}/${exp}/${ff}/${model}

            for ddd in *
            do 
                if not_empty_dir $ddd
                then
                    for fname in $ddd/*
                    do
                        if [[ $fname =~ .*.gz_0 ]]
                        then
                            base=${fname%_0}
                            echo $base
                            [[ -f $base ]] && echo "*EE* target file ALREADY exits!!" && exit 1
                            cat $base* > $base
                            [[ -f $base ]] && \rm -f ${base}_0 ${base}_1 ${base}_2
                        fi
                    done
                fi
            done
        fi
    done
done
