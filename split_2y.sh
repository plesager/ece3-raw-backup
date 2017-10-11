#! /usr/bin/env bash

#PBS -N split2y
#PBS -q ns
#PBS -l EC_billing_account=nlchekli
#PBS -j oe
##PBS -o split2y.out

set -e
module load cdo

# Can be resubmitted as often as needed, data already split will be skipped.

# INPUT - Top source dir where data were saved in chunk of 2 years, 4-letter
# name of the experiment (as appears in file names), and start year of the run

indir=/scratch/ms/spiec4i/c4p/ECEarth/RUNS/IFS144_NEMO144
expin=ECE3
YEAR_ZERO=1990

# OUTPUT - Destination dir where data will be in chunk of 1 year, and new name
# of the experiment

outdir=/scratch/ms/nl/nm6/ECEARTH-RUNS
expout=exp4


echo "******* NEMO ********"

for f in $indir/output/nemo/*
do
    if [ -d $f ]
    then
        echo $f
        nb=10#$(basename $f)

        dest1=$outdir/$expout/output/nemo/$(printf %03d $(( nb*2 -1 )))
        dest2=$outdir/$expout/output/nemo/$(printf %03d $(( nb*2 )))
        
        mkdir -p $dest1
        mkdir -p $dest2
        
        for k in $f/*
        do
            if [ -e $k ]
            then
                root=$(basename $k)
                
                # extract info from filename:
                fn=($(echo $root | sed -r "s|(.*)_([0-9]+)_([0-9]+)_(.*)\.nc|\1 \2 \3 \4|"))
                headn=$(echo ${fn[0]} | sed "s|${expin}|${expout}|")
                yyyy1=${fn[1]:0:4}
                yyyy2=${fn[2]:0:4}
                tailn=${fn[3]}
                
                [[ -e ${dest1}/${headn}_${yyyy1}0101_${yyyy1}1231_${tailn}.nc ]] && continue
                
                # split - gives two YYYY.nc4 files
                cdo splityear $k $SCRATCH/${headn}_
                
                mv $SCRATCH/${headn}_${yyyy1}.nc4 ${dest1}/${headn}_${yyyy1}0101_${yyyy1}1231_${tailn}.nc
                mv $SCRATCH/${headn}_${yyyy2}.nc4 ${dest2}/${headn}_${yyyy2}0101_${yyyy2}1231_${tailn}.nc
            fi
        done
    fi
done


echo; echo "******* IFS ********"

for f in $indir/output/ifs/*
do
    if [ -d $f ]
    then
        echo $f
        nb=10#$(basename $f)

        dest1=$outdir/$expout/output/ifs/$(printf %03d $(( nb*2 -1 )))
        dest2=$outdir/$expout/output/ifs/$(printf %03d $(( nb*2 )))

        mkdir -p $dest1
        mkdir -p $dest2

        y1=$(( YEAR_ZERO + nb*2 - 2 ))
        y2=$(( YEAR_ZERO + nb*2 - 1 ))

        for k in $f/ICM??${expin}+${y1}*
        do
            if [ -e $k ]
            then
                bn=$(basename $k)
                [[ -e $dest1/${bn/$expin/$expout} ]] && continue
                cp -v $k $dest1/${bn/$expin/$expout}
            fi
        done

        for k in $f/ICM??${expin}+${y2}*
        do
            if [ -e $k ]
            then
                bn=$(basename $k)
                [[ -e $dest2/${bn/$expin/$expout} ]] && continue
                cp -v $k $dest2/${bn/$expin/$expout}
            fi
        done
    fi
done

echo
echo "*II* SUCCESS"
echo
