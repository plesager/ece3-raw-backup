#! /usr/bin/env bash

#SBATCH --qos=nf
#SBATCH --cpus-per-task=24
#SBATCH --output=bckp.%j.out
#SBATCH --time=12:00:00
#SBATCH --ntasks=1

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

. ./config.cfg
archive=${ecfs_dir}/${exp}

######################### Hardcoded options #########################
#tar_restart=1

if (( leg ))
then
    # This applies to all legs
    
    # -- set to 0 if you want to ignore these data
    do_restart=1
    do_ifs_output=1
    do_nemo_output=1
    do_tm5_output=1
    do_lpjg_output=1

    # -- do not change
    do_tm5_restart=0
    do_hiresclim2=0
    do_climato=0
    do_log=0
    do_co2boxism_output=0
else
    # Special case of leg 0. Typically done only once. Useful for
    # tarball of TM5 restarts, log files, and output of hiresclim
    # post-processing.

    # -- set to 0 if you want to ignore these data
    do_tm5_restart=1
    do_hiresclim2=1
    do_climato=0
    do_log=1
    do_co2boxism_output=1

    # -- do not change
    do_restart=0
    do_ifs_output=0
    do_nemo_output=0
    do_tm5_output=0
    do_lpjg_output=0
fi

# Group Hiresclim output: number of years to bundle in one archive (roughly 5
# for hires, 20 for low res)
group=20

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
echo " *II*  lpjg output: $do_lpjg_output"
echo " *II*"
echo " *II* Special:"
echo " *II*    hiresclim2: $do_hiresclim2"
echo " *II*   tm5_restart: $do_tm5_restart"
echo " *II*       climato: $do_climato"
echo " *II*           log: $do_log"
echo " *II* co2box/pism output: $do_co2boxism_output"

##############
# Utilities  #
##############
bckp_emcp () {
    emv -e $1  ${archive}/$1
    echmod 444 ${archive}/$1
}

#maxsize=34359738368             # limit in bytes for emv as of October 2017 - cca (32GB)
maxsize=137438953472             # limit in bytes for emv as of October 2023 - hpc2020 (137GB)

split_move () {
    # split if larger than what emv can handle
    local f=$1
    actualsize=$(du -b "$f" | cut -f 1)
    if (( $actualsize > $maxsize )); then
        nn=$(( $actualsize / $maxsize + 1))
        split -n $nn -a 1 -d $f ${f}_
        \rm -f $f
        for k in $(eval echo {0..$((nn-1))})
        do 
            bckp_emcp ${f}_${k} # TODO parallelize may be tricky
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

        if (( is_last ))
        then
            ( f=restart.ifs.${legnbP1}.tar
              tar -cf $f  srf* ece.info rcf
              split_move $f
            ) &
        else
            ( f=$(echo restart/ifs/${legnbP1} | sed "s|/|.|g").tar
                  tar -cf $f restart/ifs/${legnbP1}
                  split_move $f
                  \rm -f restart/ifs/${legnbP1}/*
            ) &
        fi
    fi
    
    if $(not_empty_dir restart/nemo/${legnbP1}) || (( is_last ))
    then
        echo; echo " *II* NEMO RESTART ${legnbP1} ***"; echo

        if (( is_last ))
        then
            ( f=restart.nemo.${legnbP1}.tar
              tar -cf $f ${exp}_????????_restart_oce_????.nc ${exp}_????????_restart_ice_????.nc
              split_move $f
            ) &
        else            
            ( f=$(echo restart/nemo/${legnbP1} | sed "s|/|.|g").tar
              tar -cf $f restart/nemo/${legnbP1}
              split_move $f
              \rm -f restart/nemo/${legnbP1}/*
            ) &
        fi
    fi

    if $(not_empty_dir restart/lpjg/${legnbP1}) || (( is_last ))
    then
        echo; echo " *II* LPJG RESTART ${legnbP1} ***"; echo

        ( f=$(echo restart/lpjg/${legnbP1} | sed "s|/|.|g").tar
          tar -cf $f restart/lpjg/${legnbP1}
          split_move $f
          \rm -rf restart/lpjg/${legnbP1}/*
        ) &
    fi

    if not_empty_dir restart/oasis/${legnbP1}
    then
        echo; echo " *II* OASIS/CO2BOX/FWF/PISM RESTART ${legnbP1} ***"; echo

        ( f=$(echo restart/oasis/${legnbP1} | sed "s|/|.|g").tar
          tar -cvf $f restart/{oasis,co2box,fwf,pism_grtes}/${legnbP1} 
          split_move $f
          \rm -f restart/{oasis,co2box,fwf,pism_grtes}/${legnbP1}/*
        ) &
    fi

fi
wait

###############
# NEMO output #
###############
if (( do_nemo_output )) && not_empty_dir output/nemo/${legnb}
then
    echo; echo " *II* NEMO OUTPUT ${legnb} ***"; echo

    emkdir -p ${archive}/output/nemo/${legnb}
    echmod 755 ${archive}/output/nemo/${legnb}

    for ff in output/nemo/${legnb}/*
    do
        ( if [[ $ff =~ ${exp}.*\.nc$ ]]
          then
              gzip ${ff}
              split_move $ff.gz
          else
              [[ -f $ff ]] && split_move $ff
          fi
        ) &
    done
fi

###############
# LPJG output #
###############
if (( do_lpjg_output )) && not_empty_dir output/lpjg/${legnb}
then
    echo; echo " *II* LPJG OUTPUT ${legnb} ***"; echo

    ( f=$(echo output/lpjg/${legnb} | sed "s|/|.|g").tar
      tar -cf $f output/lpjg/${legnb}
      split_move $f
      \rm -rf output/lpjg/${legnb}/*
    ) &
fi

######################
# PISM/CO2BOX output #
######################
if (( do_co2boxism_output ))
then
    if not_empty_dir output/co2box
    then
        echo; echo " *II* CO2BOX  OUTPUT  ***"; echo
        ( f=output.co2box.tgz
          tar -zcf $f output/co2box
          split_move $f
          for d in  output/co2box/*; do rm -rf $d; done
        ) &
    fi
    if not_empty_dir output/pism_grtes
    then
        echo; echo " *II* PISM_GRTES  OUTPUT ***"; echo
        ( f=output.pism_grtes.tgz
          tar -zcf $f output/pism_grtes
          split_move $f
          for d in  output/pism_grtes/*; do rm -rf $d; done
        ) &
    fi
    wait
fi

##########################
# TM5 output and restart #
##########################
if (( do_tm5_output )) && not_empty_dir output/tm5/${legnb}
then
    echo; echo " *II* TM5 OUTPUT ${legnb} ***"; echo

    ( f=$(echo output/tm5/${legnb} | sed "s|/|.|g").tar
      tar -cf $f output/tm5/${legnb}
      split_move $f
      \rm -f output/tm5/${legnb}/*
    ) &
fi

#wait for nemo, lpjg, and tm5 output done
wait

if (( do_tm5_restart )) && not_empty_dir restart/tm5
then
    echo; echo " *II* TM5 restart ***"; echo
    emkdir -p ${archive}/restart/tm5
    echmod 755 ${archive}/restart/tm5

    # --- archives of 35 files is fine
    tm5grp=35

    ff=( $(find restart/tm5 -type f | sort) )
    nb=${#ff[@]}
    nn=$(( nb / tm5grp + 1 ))
    echo
    echo " making $nn archives of ${nb} years each"

    for k in $(eval echo {0..$((nn-1))})
    do
        ( is=$((k*tm5grp))
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
        ) &
    done
    wait
fi

##############
# IFS output #
##############
if (( do_ifs_output )) && not_empty_dir output/ifs/${legnb}
then
    echo; echo " *II* IFS OUTPUT ${legnb} ***"; echo

    emkdir -p ${archive}/output/ifs/${legnb}
    echmod 755 ${archive}/output/ifs/${legnb}

    for f in output/ifs/${legnb}/*   # only GG not SH files are worth zipping
    do
        (
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
        ) &
    done
    wait
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
    nn=$(( nb / group + (nb % group > 0) ))
    echo
    echo " making $nn archives of ${group} years each"

    for k in $(eval echo {0..$((nn-1))})
    do
        ( is=$((k*group))

          f=${exp}_${ff[${is}]#Post_}_hiresclim2.tar.gz

          echo " archive: $f"

          tar -zcvf $f ${ff[*]:${is}:${group}}
          split_move $f
        ) &
    done
    wait
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

    set +e
    f=extra_rst001.tar.gz
    tar -zcvf $f restart/lpjg/001 output/nemo/ofx-data restart/pism_grtes/001 restart/co2box/001
    split_move $f
    rm -rf restart/lpjg/001 output/nemo/ofx-data restart/pism_grtes/001 restart/co2box/001
    set -e
fi
wait
echo " *II* SUCCESS"
