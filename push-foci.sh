#!/usr/bin/env bash

#SBATCH --qos=nf
#SBATCH --cpus-per-task=2
#SBATCH --output=focipush.%j.out
#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --account=nlchekli

# Use 7 cpus-per-task for USECASE=1, and 2 cpus-per-task for USECASE=2

# The 6-hourly EC-Earth output on ECFS below:
# 
#    ec:/nm6/ECEARTH-RUNS/fs01/cmor
# 
# The files are gathered into large (favoured by the tape system) tarballs with typical names like:
# 
#    EC-Earth3-AerChem-FOCI-r1i2p1f1-<TABLE>-<YYYY>.tar
# 
# where TABLE refers to the name of the group of data (CMIP6 convention), and YYYY to the simulated year.
# 
# Few TABLEs are too large to fit in one tarball, so you will find some suffix "-partX.tar" with X=0,1,2.
# 
# Since you only need the 6hr output, you can quickly find their name with:
# 
#   els  ec:/nm6/ECEARTH-RUNS/fs01/cmor/*6hr* 
# 
# I'm not sure if this is needed for WRF, but the 'tos' variable (ocean temperature) is available in the 3hr table only.
#

USECASE=2

# --- Dirs
tapedir='ec:/nm6/ECEARTH-RUNS/fs01/cmor'
localdir='/ec/res4/scratch/nldac/FOCI-project'
targetdir='/storage/pool02/foci/WP6/ec-earth3-aerchem/ssp370_20452055'

# --- Part 1 ---  retrieve from tape

if [[ $USECASE -eq 1 ]]
then

    mkdir -p $localdir

    for YYYY in {2045..2055}; do
        echo $YYYY
        for f in \
            EC-Earth3-AerChem-FOCI-r1i2p1f1-6hrLev-${YYYY}-part0.tar \
                                                   EC-Earth3-AerChem-FOCI-r1i2p1f1-6hrLev-${YYYY}-part1.tar \
                                                   EC-Earth3-AerChem-FOCI-r1i2p1f1-6hrLev-${YYYY}-part2.tar \
                                                   EC-Earth3-AerChem-FOCI-r1i2p1f1-6hrPlev-${YYYY}.tar \
                                                   EC-Earth3-AerChem-FOCI-r1i2p1f1-AER6hrPt-${YYYY}-part0.tar \
                                                   EC-Earth3-AerChem-FOCI-r1i2p1f1-AER6hrPt-${YYYY}-part1.tar \
                                                   EC-Earth3-AerChem-FOCI-r1i2p1f1-3hr-${YYYY}.tar
        do
            ecp $tapedir/$f $localdir/$f &
        done
        wait
    done
    
elif [[ $USECASE -eq 2 ]]
then
    cd $localdir
    find . -type f |
        parallel -j2 -X rsync -R -Hav ./{} foci@kamet4:$targetdir/
fi
