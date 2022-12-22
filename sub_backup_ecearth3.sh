#! /usr/bin/env bash

 #######################################################################
 # For hpc-bologna that uses SLURM scheduler                           #
 #######################################################################
 # Notes:                                                              #
 # - This scripts requires two arguments:                              #
 #      - 1st argument: experiment ID                                  #
 #      - 2nd argument: leg                                            #
 #         For leg:                                                    #
 #             - use leg number without zero-padding                   #
 #		 e.g., 1, 15 etc. to bckp restarts  	       	       #
 #               and raw output                                        #
 #             - use 0 as leg number to backup EXP log files and       #
 #               tm5 restarts                                          #
 # - Account can be changed below                                      #
 # - Dependency can be changed below                                   #
 #######################################################################

exp=$1
leg_nozeros=$2
#Add zero-padding
leg=$(printf "%03d" $leg_nozeros)

ACCOUNT=$EC_billing_account
DEPENDENCY=


# SBATCH --qos=nf
# SBATCH --account=<ACCOUNT>
# SBATCH --depend=afterok:<DEPENDENCY>
#### SBATCH --output log/bckp_<exp>_<leg>.out
# SBATCH --time=24:00:00



if [ "$#" -eq 2 ]; then

    set -e

    # location of script to be submitted and its log 
    OUT=$SCRATCH/tmp_ece3_bckp
    mkdir -p $OUT/log


    ######################### Hardcoded options #########################
    tar_restart=1


    if [ ${leg} = '000' ]
    then
        # The following only ONCE (i.e no loop over that script!)
        #   as a safeguard, it is required to have leg=0 
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
    else 
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
    fi







    # Group Hiresclim output: number of years to bundle in one archive (roughly 5
    # for hires, 20 for low res)
    group=20

    # IN & OUT top dirs
    #runs_dir="${SCRATCH}/ECEARTH-RUNS/"
    runs_dir="${SCRATCH}/ecearth3/"
    ecfs_dir="ec:/${USER}/ECEARTH-RUNS/${exp}"

    #####################################################################
    # All commands to be executed from the run top directory
    cd ${runs_dir}/${exp}

    #nextleg=$(( leg + 1 ))
    nextleg=$(( leg_nozeros + 1 ))
    #legnb=$(printf %03d ${leg})
    legnb=$leg
    legnbP1=$(printf %03d ${nextleg})

    # -- check for last leg (works as long as code is not still running and processing the last finished leg)
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

    ############
    # RESTARTS #
    ############
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

else
  echo
  echo '  Illegal number of arguments: the script requires two arguments:'
  echo '   1st argument: experiment ID'
  echo '   2nd argument: leg without zero-padding'
  echo '  For instance:'
  echo '   sbatch  --job-name=bckp_EXP1_001 ' $0 ' EXP1 1'
  echo '  Or use:'
  echo '   for exp in EXP1; do for leg in {0..15}; do sbatch --job-name=bckp_${exp}_${leg}  ' $0 ' ${exp}  ${leg}; done; done'
  echo
fi
