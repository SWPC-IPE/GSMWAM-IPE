#!/bin/bash

pwd=$(pwd)
bn=$(basename $1)

## set restart
export cycle=${2:-1}
if [[ $cycle == 1 ]] ; then
  export RESTART=.false.
else
  export RESTART=.true.
fi

## source config
CONFIG=$( echo $bn | cut -d'.' -f 1 )
. $pwd/config/workflow.sh $1

if [ $? != 0 ]; then echo "setup failed, exit"; exit; fi

## create job file
tmp=temp_job.sh
rm -rf $tmp
touch $tmp
chmod +x $tmp

## cp config to $ROTDIR if $cycle == 1
if [[ $cycle == 1 ]] || [[ ! -f $ROTDIR/$1 ]] ; then
	cp $1 $ROTDIR/.
fi

## set up PBS/LSF/whatever
echo "#!/bin/bash" > $tmp
# the below is a little hacky but it sure works
d=0
while
        d=$((d+1))
        eval SUBFLAG=\$SUBFLAG$d
        [[ -n "$SUBFLAG" ]]
do
        echo `eval echo $SUBFLAG` >> $tmp
done
## and now back to the regularly scheduled program
cat >> $tmp << EOF
do_plots(){
  mkdir plot_\$1 && cd plot_\$1

  cp $BASEDIR/IPELIB/scripts/Convert_mpi.batch .
  sed -i '/IPE_RUNDIR=/c\IPE_RUNDIR="'${ROTDIR}/'"' ./Convert_mpi.batch
  # Do the polar plots for IPE
  sed -i '/PLOTDIR=/c\PLOTDIR="'${PLOT_DIR}/${JOBNAME}/${CONFIG}/ipe/\${1}_plots/'"' ./Convert_mpi.batch
  if [[ \$1 = "polar" ]] ; then
    sed -i '/PLOTTYPE=/c\PLOTTYPE="-p"' ./Convert_mpi.batch
  elif [[ \$1 = "mercator" ]] ; then
    sed -i '/PLOTTYPE=/c\PLOTTYPE=""' ./Convert_mpi.batch
  fi

  ./Convert_mpi.batch $BASEDIR

  cd ..
}

submit_plots(){
  cd $ROTDIR && ln -fs $RUNDIR/IPE.inp .
  rm -rf make_plots && mkdir make_plots && cd make_plots

  do_plots "polar"
  do_plots "mercator"
}

cd $COMPSETDIR

## set restart
if [[ $cycle == 1 ]] ; then
  export RESTART=.false.
else
  export RESTART=.true.
fi

##-------------------------------------------------------
## source config file
##-------------------------------------------------------

. $pwd/config/workflow.sh $ROTDIR/$bn

##-------------------------------------------------------
## execute forecast
##-------------------------------------------------------

rm -rf $RUNDIR
mkdir -p $RUNDIR
cd $RUNDIR

export VERBOSE=YES

 . $EXGLOBALFCSTSH
if [ $? != 0 ]; then echo "forecast failed, exit"; exit; fi
echo "fcst done"



if [[ ${REGRESSION:-"NO"} = "YES" ]] ; then
  mkdir -p ${PLOT_DIR}/${JOBNAME}/${CONFIG}
  if [[ $cycle == 1 ]] ; then rm -rf ${PLOT_DIR}/${JOBNAME}/${CONFIG}/timepet.out ; fi
  python $SCRIPTSDIR/timepet/timepet.py $RUNDIR/PET350.ESMF_LogFile >> ${PLOT_DIR}/${JOBNAME}/${CONFIG}/timepet.out
fi

cd $COMPSETDIR
if [[ $((cycle+1)) -le ${3:-1} ]] ; then
  echo "resubmitting $1 for cycle $((cycle+1)) out of $3"
  . $pwd/submit.sh $ROTDIR/`basename $1` $((cycle+1)) $3

else
  echo "cycle $((cycle+1)) > $3, done!"
  if [[ ${REGRESSION:-"NO"} = "YES" ]] ; then
    echo "submitting plotting jobs!"
    python $SCRIPTSDIR/plot/timepet_plot.py -i ${PLOT_DIR}/${JOBNAME}/${CONFIG} -d ${CDATE} -t $DELTIM
    submit_plots
  fi

fi

if [[ ${DO_POST_WAM:-"NO"} = "YES" ]] ; then
    cd $POSTDIR
    export INPUT_PATH=$ROTDIR
    python convert.py $ROTDIR/input_parameters.${CDATE}.${cycle}.nc
fi

exit $status
EOF

$SCHEDULER_SUB < $tmp
mv $tmp $ROTDIR/jobcard_$cycle
