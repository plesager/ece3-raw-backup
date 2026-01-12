#!/usr/bin/env bash

#SBATCH --qos=np
#SBATCH --output=qnd.%j.out
#SBATCH --time=48:00:00
#SBATCH --ntasks=1
#SBATCH --account=nlchekli
#SBATCH --cpus-per-task=2
  # 1 for ncap2, 2 for rsync (and qos=nf), 11 for others

localdir='/ec/res4/scratch/nldac/FOCI-project'
tapedir='ec:/nm6/ECEARTH-RUNS/fs01/cmor'
targetdir='/storage/pool02/foci/WP6/ec-earth3-aerchem/ssp370_20452055'

module load nco
cd $localdir

# -- Extract from tarballs
#with ntasks=11
# for k in {45..55}
# do
#     ( f=EC-Earth3-AerChem-FOCI-r1i2p1f1-6hrLev-20${k}-part0.tar
#       zg="./ScenarioMIP/EC-Earth-Consortium/EC-Earth3-AerChem/ssp370/r1i2p1f1/6hrLev/zg/gr/v20241208/zg_6hrLev_EC-Earth3-AerChem_ssp370_r1i2p1f1_gr_20${k}01010300-20${k}12312100.nc"
#       tar -xvf $f $zg
#       #MEMKILL  new=$(echo $zg | sed "s/0300-/0000-/g" | sed "s/2100\.nc/1800\.nc/g")
#       #MEMKILL  ncap2 -O -s "time=time-0.125" $zg $new
#       #MEMKILL  mv $new .
#     ) &
# done
# wait

# -- Fix time axis
flist=$(find ScenarioMIP -name "zg*nc" | sort)

for f in $flist
do
    g=$(basename $f | sed "s/0300-/0000-/g" | sed "s/2100\.nc/1800\.nc/g")
    [[ ! -f $g ]] && ncap2 -O -s "time=time-0.125" $f $g || echo skip $g  # can use only one cpu for that task
done

# -- Backup
#with ntasks=11
flist=$(find . -name "zg*1800.nc")
for f in $flist
do
    ecp $f $tapedir/$f &
done
wait

echo success backup

# -- Transfer
cd $localdir
find . -type f -name "zg*1800.nc" |
    parallel -j2 -X rsync -R -Hav ./{} foci@kamet4:$targetdir/

echo success
