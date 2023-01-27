#! /usr/bin/env bash

#SBATCH --qos=nf
#SBATCH --output=bckp.%j.out
#SBATCH --time=06:00:00

usage() {
    cat << EOT >&2
USAGE:
   sbatch $(basename $0) Experiment LegNumber

   Move output and restart files from one leg of an EC-Earth3 Experiment to ECFS.


EXAMPLES (they assume that the directory specified with the --output option exists!)

    sbatch --output=log/aeGz-003.out --job-name=aeGz-003 $(basename $0) aeGz 3

  or for several legs:

    exp=aeGz
    for i in {1..4}; do mess=\${exp}-\$(printf %03d \$i); sbatch -o log/\${mess}.out -J \$mess $(basename $0) \${exp} \$i; done

    this variant will do the same:
    for i in {001..004}; do mess=\${exp}-\$i; sbatch -o log/\${mess}.out -J \$mess $(basename $0) \${exp} \$i; done

EOT
}

set -ue

# -- Args
if [ "$#" -ne 2 ]; then
    echo; echo "*EE* script requires two arguments"; echo
    usage
    exit 1
fi

if [[ ! $1 =~ ^[a-Z_0-9]{4}$ ]]; then
    echo; echo "*EE* argument EXPERIMENT name (=$1) should be a 4-character string"; echo
    usage
    exit 1
fi

if [[ ! $2 =~ ^[0-9]+$ ]]; then
    echo ;echo "*EE* argument LEG_NUMBER (=$2) should be a number"; echo
    usage
    exit 1
fi

exp=$1
leg=$((10#$2))

######################### Hardcoded options #########################
tar_restart=1

if (( leg ))
then
    # This applies to all legs
    
    # -- set to 0 if you want to ignore these data
    do_restart=1
    do_ifs_output=1
    do_nemo_output=1
    do_tm5_output=1

    # -- do not change
    do_tm5_restart=0
    do_hiresclim2=0
    do_climato=0
    do_log=0
else
    # Special case of leg 0. Typically done only once. Useful for
    # tarball of TM5 restarts, log files, and output of hiresclim
    # post-processing.

    # -- set to 0 if you want to ignore these data
    do_tm5_restart=1
    do_hiresclim2=0
    do_climato=0
    do_log=1

    # -- do not change
    do_restart=0
    do_ifs_output=0
    do_nemo_output=0
    do_tm5_output=0
fi

# Group Hiresclim output: number of years to bundle in one archive (roughly 5
# for hires, 20 for low res)
group=20

# IN & OUT top dirs
runs_dir="${SCRATCH}/ecearth3"
ecfs_dir="ec:/${USER}/ECEARTH-RUNS/${exp}"

###################### End Hardcoded Options ########################

# All commands to be executed from the run top directory
cd ${runs_dir}/${exp}

nextleg=$(( leg + 1 ))
legnb=$(printf "%03d" ${leg})
legnbP1=$(printf "%03d" ${nextleg})

# -- check for last leg (works as long as EC-Earth3 is not running and processing the last finished leg)
is_last=0
##PLS not robust enough[ -d output/ifs/${legnbP1} ]  && is_last=0
##PLS not robust enough[ -d output/nemo/${legnbP1} ] && is_last=0
##PLS not robust enough
##PLS not robust enoughdo_log=${is_last}               # pack all logs when doing last leg

# -- summary
echo " *II* processing leg $legnb"
(( is_last )) && echo " *II* LAST LEG ASSUMED"
echo " *II* Regular:"
echo " *II*  all restart: $do_restart"
echo " *II*   ifs output: $do_ifs_output"
echo " *II*  nemo output: $do_nemo_output"
echo " *II*   tm5 output: $do_tm5_output"
echo " *II*"
echo " *II* Special:"
echo " *II*    hiresclim2: $do_hiresclim2"
echo " *II*   tm5_restart: $do_tm5_restart"

##############
# Utilities  #
##############
bckp_emcp () {
    emv -e $1  ${ecfs_dir}/$1
    echmod 444 ${ecfs_dir}/$1
}

maxsize=34359738368             # limit in bytes for emv as of October 2017 (32GB)

split_move () {
    # split if larger than what emv can handle (34359738368 bytes)
    local f=$1
    actualsize=$(du -b "$f" | cut -f 1)
    if (( $actualsize > $maxsize )); then
        nn=$(( $actualsize / $maxsize + 1))
        split -n $nn -a 1 -d $f ${f}_
        \rm -f $f
        for k in $(eval echo {0..$((nn-1))})
        do 
            bckp_emcp ${f}_${k}
        done
    else
        bckp_emcp $f
    fi
}

not_empty_dir () {
    [[ ! -d "$1" ]] && return 1
    [ -n "$(ls -A $1)" ] && return 0 || return 1
}

###############################
# RESTARTS (IFS, NEMO, OASIS) #
###############################
if (( do_restart ))
then
    if $(not_empty_dir restart/ifs/${legnbP1}) || (( is_last ))
    then
        echo; echo " *II* IFS RESTART ${legnbP1} ***"; echo

        if (( ! tar_restart ))
        then
            emkdir -p ${ecfs_dir}/restart/ifs/${legnbP1}
            echmod 755 ${ecfs_dir}/restart/ifs/${legnbP1}
        fi

        if (( is_last ))
        then
            if (( tar_restart ))
            then
                f=restart.ifs.${legnbP1}.tar
                tar -cf $f  srf* ece.info rcf
                split_move $f
            else
                for f in srf* ece.info rcf
                do
                    if [[ -f $f ]]; then
                        emv -e $f ${ecfs_dir}/restart/ifs/${legnbP1}/$f
                        echmod 444 ${ecfs_dir}/restart/ifs/${legnbP1}/$f
                    fi
                done
            fi
        else
            if (( tar_restart ))
            then
                # need to check if remote exists to trap cases of crash after
                # 'split_move' and before end of '\rm -f', for now let script stop
                f=$(echo restart/ifs/${legnbP1} | sed "s|/|.|g").tar
                tar -cf $f restart/ifs/${legnbP1}
                split_move $f
                \rm -f restart/ifs/${legnbP1}/*
            else
                for f in restart/ifs/${legnbP1}/*
                do
                    [[ -f $f ]] && split_move $f
                done
            fi
        fi
    fi
    
    if $(not_empty_dir restart/nemo/${legnbP1}) || (( is_last ))
    then
        echo; echo " *II* NEMO RESTART ${legnbP1} ***"; echo

        if (( ! tar_restart ))
        then 
            emkdir -p ${ecfs_dir}/restart/nemo/${legnbP1}
            echmod 755 ${ecfs_dir}/restart/nemo/${legnbP1}
        fi

        if (( is_last ))
        then
            if (( tar_restart ))
            then 
                f=restart.nemo.${legnbP1}.tar
                tar -cf $f ${exp}_????????_restart_oce_????.nc ${exp}_????????_restart_ice_????.nc
                split_move $f
            else
                for f in ${exp}_????????_restart_oce_????.nc ${exp}_????????_restart_ice_????.nc
                do
                    if [[ -f $f ]]; then
                        emv -e $f ${ecfs_dir}/restart/nemo/${legnbP1}/$f
                        echmod 444 ${ecfs_dir}/restart/nemo/${legnbP1}/$f
                    fi
                done
            fi
        else            
            if (( tar_restart ))
            then 
                # need to check if remote exists to trap cases of crash after
                # 'split_move' and before end of '\rm -f', for now let the script stop
                f=$(echo restart/nemo/${legnbP1} | sed "s|/|.|g").tar
                tar -cf $f restart/nemo/${legnbP1}
                split_move $f
                \rm -f restart/nemo/${legnbP1}/*                   
            else
                for f in restart/nemo/${legnbP1}/*
                do
                    [[ -f $f ]] && split_move $f
                done        
            fi
        fi
    fi

    if not_empty_dir restart/oasis/${legnbP1}
    then
        echo; echo " *II* OASIS RESTART ${legnbP1} ***"; echo

        if (( tar_restart ))
        then 
            # need to check if remote exists to trap cases of crash after
            # 'split_move' and before end of '\rm -f', for now let the script stop
            f=$(echo restart/oasis/${legnbP1} | sed "s|/|.|g").tar
            tar -cf $f restart/oasis/${legnbP1}
            split_move $f
            \rm -f restart/oasis/${legnbP1}/*
        else
            emkdir -p ${ecfs_dir}/restart/oasis/${legnbP1}
            echmod 755 ${ecfs_dir}/restart/oasis/${legnbP1}

            for f in restart/oasis/${legnbP1}/*
            do
                [[ -f $f ]] && split_move $f
            done        
        fi
    fi
fi

###############
# NEMO output #
###############
if (( do_nemo_output )) && not_empty_dir output/nemo/${legnb}
then
    echo; echo " *II* NEMO OUTPUT ${legnb} ***"; echo

    emkdir -p ${ecfs_dir}/output/nemo/${legnb}
    echmod 755 ${ecfs_dir}/output/nemo/${legnb}

    for ff in output/nemo/${legnb}/*
    do
        if [[ $ff =~ ${exp}.*\.nc$ ]]
        then
            gzip ${ff}
            split_move $ff.gz
        else
            [[ -f $ff ]] && split_move $ff
        fi
    done
fi

##########################
# TM5 output and restart #
##########################
if (( do_tm5_output )) && not_empty_dir output/tm5/${legnb}
then
    echo; echo " *II* TM5 OUTPUT ${legnb} ***"; echo

    f=$(echo output/tm5/${legnb} | sed "s|/|.|g").tar
    tar -cf $f output/tm5/${legnb}
    split_move $f
    \rm -f output/tm5/${legnb}/*

fi

if (( do_tm5_restart )) && not_empty_dir restart/tm5
then
    echo; echo " *II* TM5 restart ***"; echo
    emkdir -p ${ecfs_dir}/restart/tm5
    echmod 755 ${ecfs_dir}/restart/tm5

    # --- archives of 35 files is fine
    tm5grp=35

    ff=( $(find restart/tm5 -type f | sort) )
    nb=${#ff[@]}
    nn=$(( nb / tm5grp + 1 ))
    echo
    echo " making $nn archives of ${nb} years each"

    for k in $(eval echo {0..$((nn-1))})
    do
        is=$((k*tm5grp))
        nf=$tm5grp
        ie=$(( (k+1) * tm5grp - 1))
        (( ie > (nb-1) )) && ie=$((nb-1)) && nf=$(( ie - is + 1 ))
        d1=$(echo ${ff[$is]} | sed -nr "s|restart/tm5.*TM5_restart_(.*)_0000_glb300x200.nc|\1|"p)
        d2=$(echo ${ff[$ie]} | sed -nr "s|restart/tm5.*TM5_restart_(.*)_0000_glb300x200.nc|\1|"p)
        f=tm5-restart-${d1}-${d2}.tar
        echo " archive: $f"
        tar -cvf $f ${ff[*]:${is}:${nf}}
        split_move $f
        #\rm -f ${ff[*]:${is}:${nf}}
    done

fi

##############
# IFS output #
##############
if (( do_ifs_output )) && not_empty_dir output/ifs/${legnb}
then
    echo; echo " *II* IFS OUTPUT ${legnb} ***"; echo

    emkdir -p ${ecfs_dir}/output/ifs/${legnb}
    echmod 755 ${ecfs_dir}/output/ifs/${legnb}

    for f in output/ifs/${legnb}/*   # only GG not SH files are worth zipping
    do        
        # -- [crash cases] already compressed GG, and maybe with a split
        if [[ $f =~ ICMGG${exp}.*gz(_[0-9])?$ ]]
        then
            split_move $f

            # -- compress GG
        elif [[ $f =~ ICMGG${exp} ]]
        then
            gzip ${f}
            split_move $f.gz
        else
            # check on file, may have been emoved if a split was repeated
            [[ -f $f ]] && split_move $f
        fi
    done
fi

############################
# CLIMATOLOGY from EC-Mean # (default location assumed)
############################
if (( do_climato )) && not_empty_dir post
then
    echo; echo " *II* CLIMATO ***"; echo

    # -- 730M/period (AMIP)
    for k in post/clim*
    do
        if not_empty_dir $k
        then
            f=${exp}-$(basename ${k}.)tar.gz
            cd ..
            tar -zcvf $f ${exp}/${k}
            split_move $f
            #\rm -rf ${exp}/${k}
            cd -
        fi
    done
fi

#########################
# HIRESCLIM2 post ouput #
#########################
if (( do_hiresclim2 )) && not_empty_dir post/mon
then
    echo; echo " *II* HIRESCLIM2 ***"; echo

    # --- group 20 (use 7 for coupled HiRes) years together

    cd  post/mon

    ff=($(ls))
    nb=${#ff[*]}
    nn=$(( nb / group + 1 ))
    echo
    echo " making $nn archives of ${group} years each"

    for k in $(eval echo {0..$((nn-1))})
    do
        is=$((k*group))

        f=${exp}_${ff[${is}]#Post_}_hiresclim2.tar.gz

        echo " archive: $f"

        tar -zcvf $f ${ff[*]:${is}:${group}}
        split_move $f
    done

    cd -
fi

#######
# LOG #
#######
if (( do_log ))
then
    echo; echo " *II* LOG ***"; echo
    f=log.${exp}.upto.${legnb}.tar.gz
    tar -cvzf $f log
    split_move $f
fi

echo " *II* SUCCESS"
