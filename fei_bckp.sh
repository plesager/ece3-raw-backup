#! /usr/bin/env bash

#SBATCH --qos=np
#SBATCH --cpus-per-task=25
#SBATCH --output=feibckp.%j.out
#SBATCH --time=2-00:00:00
#SBATCH --ntasks=1
#SBATCH --account=nlchekli

set -ue

srcdir=/scratch/nktr/cmorised-results/extremeX/CMIP6/CMIP/EC-Earth-Consortium/EC-Earth3/AISE
archive='ec:/rufl/extremeX/AISE'

mkdir -p  $SCRATCH/AISE

# chunk of 25 look alright 

for leg in {76..100}
do
    ( leg3d=$(printf "%03d" $leg)

      subdir=s${leg3d}-r${leg}i2p1f1 

      f1=${subdir}-6hrPlevPt.tar
      f2=${subdir}-others.tar
      
      tar -cf $SCRATCH/AISE/$f1 $srcdir/$subdir/6hrPlevPt

      tar -cf $SCRATCH/AISE/$f2 \
          $srcdir/$subdir/6hrPlev \
          $srcdir/$subdir/Amon \
          $srcdir/$subdir/day \
          $srcdir/$subdir/LImon \
          $srcdir/$subdir/Lmon

      ls -lt $SCRATCH/AISE/$f1
      ls -lt $SCRATCH/AISE/$f2
      
      emv -e $SCRATCH/AISE/$f1 $archive/$f1
      echmod 444 $archive/$f1
      
      emv -e $SCRATCH/AISE/$f2 $archive/$f2
      echmod 444 $archive/$f2

      els -l $archive/$f1
      els -l $archive/$f2

    )&
done
wait

