#!/bin/bash
re='^[0-9]+$' # used to check for integers

check_var() {
	eval val=\$$1
	echo "checking for $1: $val"
	if [ -z $val ] || [ ! -e $val ] ; then # makes sure the variable has been set and the path/file exists
		echo "   $1 not found! exiting." && exit 1
	fi
}

## should probably compartmentalize this file
echo "running checks for $FMID"
echo $TASKS

## basic directory/executable checks
# NEMS specific
[[ $NEMS = .true. ]] && for var in SIGHDR SFCHDR NEMSIOGET FIXGLOBAL MTNVAR O3FORC O3CLIM OROGRAPHY OROGRAPHY_UF LONSPERLAT LONSPERLAR ; do
	check_var $var
done
# globally needed
for var in NDATE MDATE BASE_NEMS FCSTEXEC EXGLOBALFCSTSH ; do
	check_var $var
done

if [[ $NEMS = .true. ]] ; then
# WAM frequency checks
echo "checking properties of the frequency options (FHOUT, FHRES, FHDFI, FHCYC, FHZER)"
if [ -z $FHOUT ] || [ $FHOUT -gt $FHSEG ] ; then
	echo "   FHOUT is invalid, setting to $FHSEG"
	export FHOUT=$FHSEG
fi
# rule 1: positive DELTIM
if [ -z $DELTIM ] || [ $DELTIM -le 0 ] ; then
	echo "   invalid DELTIM (must be positive)! exiting." ; exit 1
fi
# rule 2: FHOUT positive, multiple of DELTIM to within $tol
if [ -z $FHOUT ] || [ $FHOUT -le 0 ] || [ $(((FHOUT*3600%DELTIM)/DELTIM)) != 0 ] ; then
	echo "   FHOUT invalid: must be positive and a multiple of DELTIM! exiting." ; exit 1
fi
# rule 3: FHSWR positive, multiple of DELTIM to within $tol
if [ -z $FHSWR ] || [ $FHSWR -le 0 ] || [ $(((FHSWR%DELTIM)/DELTIM)) != 0 ] ; then
	echo "   FHSWR invalid: must be positive and a multiple of DELTIM! exiting." ; exit 1
fi
# rule 4: FHLWR, same as rule 3, but also a multiple of FHSWR
if [ -z $FHLWR ] || [ $FHLWR -le 0 ] || [ $(((FHLWR%DELTIM)/DELTIM)) != 0 ] || [ $((FHLWR%FHSWR)) != 0 ] ; then
	echo "   FHLWR invalid: must be positive, a multiple of DELTIM, and a multiple of FHSWR! exiting." ; exit 1
fi
# rule 5: FHZER, same as rule 3, but also a multiple of FHOUT
if [ -z $FHZER ] || [ $FHZER -le 0 ] || [ $(((FHZER*3600%DELTIM)/DELTIM)) != 0 ] || [ $((FHZER%FHOUT)) != 0 ] ; then
	echo "   FHZER invalid: must be positive, a multiple of DELTIM, and a multiple of FHOUT! exiting." ; exit 1
fi
# rule 6: FHRES, same as rule 3, but also a multiple of FHLWR and FHZER
if [ -z $FHRES ] || [ $FHRES -le 0 ] || [ $(((FHRES*3600%DELTIM)/DELTIM)) != 0 ] || [ $((FHRES*3600%FHLWR)) != 0 ] || [ $((FHRES%FHZER)) != 0 ] ; then
	echo "   FHRES invalid: must be positive, a multiple of DELTIM, FHLWR, and FHZER! exiting." ; exit 1
fi
# rule 7: FHDFI, same as rule 3, but also a multiple of FHLWR and <= FHRES
if [ -z $FHDFI ] || [ $FHDFI -lt 0 ] || [ $(((FHDFI*3600%DELTIM)/DELTIM)) != 0 ] || [ $((FHDFI*3600%FHLWR)) != 0 ] || [ $FHDFI -gt $FHRES ] ; then
	echo "   FHDFI invalid: must be non-negative, a multiple of DELTIM, FHLWR, and <= FHRES! exiting." ; exit 1
fi
# rule 8: FHCYC, same as rule 3, but also a multiple of FHLWR
if [ -z $FHCYC ] || [ $FHCYC -lt 0 ] || [ $(((FHCYC%DELTIM)/DELTIM)) != 0 ] || [ $((FHCYC*3600%FHLWR)) != 0 ] ; then
	echo "   FHCYC invalid: must be non-negative, a multiple of DELTIM, and a multiple of FHLWR! exiting." ; exit 1
fi
fi # NEMS loop

# wam.config checks
if [ $IDEA = .true. ] ; then
	# WAM-specific directory checks
	[[ $NEMS = .true. ]] && for var in FIX_IDEA GRIDSDIR DATADIR ; do
		check_var $var
	done

	[[ $MODE = "realtime" ]] && for var in WAMINDIR ; do
		check_var $var
	done

	echo "checking to make sure CDATE is a valid length: $CDATE"
	if [ ${#CDATE} != 10 -a $MODE != "operational" ] ; then # y10k problem!
		echo "   $CDATE is ${#CDATE} characters long, needs to be 10 (YYYYMMDDHH)! exiting." ; exit 1
	fi

	# ipe.config checks
	if [ $IPE = .true. ] ; then
		echo "checking to make sure NPROCIPE is valid: $NPROCIPE"
		valid=0
		for i in "${VALID_IPE_PET[@]}" ; do
			if [ $NPROCIPE = $i ] ; then valid=1 ; fi
		done
		[ $valid = 0 ] && echo "   Could not match NPROCIPE to range of supported number of MPI ranks. Exiting." && exit 1

		if [ ! -z $CIPEDATE ] ; then
			echo "checking to make sure CIPEDATE is a valid length: $CIPEDATE"
			if [ ${#CIPEDATE} != 12 ] ; then # also y10k problem!
				echo "   $CIPEDATE is ${#CIPEDATE} characters long, needs to be 13 (YYYYMMDDHHmm)! exiting." ; exit 1
			fi
		fi
		echo "checking for IPEGRID: $IPEGRID"
		if [ ! -e $IPEGRID ] ; then
			echo "   IPEGRID not found! exiting." ; exit 1
		fi
		echo "checking to make sure IPE output frequency is valid (IPEFREQ): $IPEFREQ"
		if [ $IPEFREQ -gt $((FHSEG*3600)) ] ; then # IPEFREQ > model run time
			echo "   IPEFREQ too high... setting IPEFREQ to $((FHSEG*3600))"
			export IPEFREQ=$((FHSEG*3600))
		elif [ $IPEFREQ -lt $DELTIM_IPE ] ; then # IPEFREQ < model integration step time
			echo "   setting IPEFREQ to DELTIM_IPE"
			export IPEFREQ=$DELTIM_IPE
		elif [ ! $(($IPEFREQ % $DELTIM_IPE)) = '0' ] ; then # IPEFREQ not a multiple of DELTIM_IPE
			echo "   $IPEFREQ is not a multiple of DELTIM_IPE: $DELTIM_IPE"
			echo "   setting IPEFREQ to 3600 (hourly)"
			export IPEFREQ=3600
		fi
	fi
fi

# check for ROTDIR
echo "checking for ROTDIR: $ROTDIR"
if [ -z $ROTDIR  ] || [ ! -d $ROTDIR ] ; then
	echo "   ROTDIR not found. creating $ROTDIR"
	mkdir -p $ROTDIR
fi
echo "checking for RESTARTDIR: $RESTARTDIR"
if [ -z $RESTARTDIR  ] || [ ! -d $RESTARTDIR ] ; then
        echo "   RESTARTDIR not found. creating $RESTARTDIR"
        mkdir -p $RESTARTDIR
fi

[[ $MODE = "operational" ]] && . $CONFIGDIR/operational.config && . $CONFIGDIR/coldstart.config

# check if WAM ICs are in place if GSM running
[[ $NEMS = .true. ]] && if [ $RESTART = .false. ] ; then # cold start
	echo "checking for atmospheric/surface initial conditions in ROTDIR: $SEARCH$CDATE"
	if [[ `find -L $ROTDIR -maxdepth 1 -type f -iname "$SEARCH$CDATE" | wc -l` -lt 1 ]] ; then
		echo "   ICs not found in ROTDIR. checking for IC_DIR"
		if [[ -n $IC_DIR ]] ; then
			echo "   IC_DIR has been set to $IC_DIR"
			if [[ `find -L $IC_DIR -type f -iname "$SEARCH$CDATE" | wc -l` -lt 2 ]] ; then
				echo "   but ICs for $CDATE are not found! exiting." ; exit 1
			else
				echo "   found ICs! copying over."
				$NCP $IC_DIR/$SEARCH$CDATE $ROTDIR/.
				$NCP $IC_DIR/wam_input_f107_kp.txt $ROTDIR/.
			fi
		else # IC_DIR is unset, we don't know where to look
			echo "   IC_DIR has not been set: cannot find initial conditions! exiting." ; exit 1
		fi
	fi
	# now we check to see that the surface idate&fhour match the atmospheric idate&fhour
	echo "making sure our ICs match idate and fhour"
	export ATMIN=`find -L $ROTDIR -maxdepth 1 -type f -iname "$ATM*$CDATE" | head -1`
	export SFCIN=`find -L $ROTDIR -maxdepth 1 -type f -iname "sfca03*$CDATE" | head -1`
#	if [ $NEMSIO_IN = .true. ] ; then
#		if [ $($NEMSIOGET $ATMIN fhour) != $($NEMSIOGET $SFCIN fhour) ] || \
#		   [ $($NEMSIOGET $ATMIN idate) != $($NEMSIOGET $SFCIN idate) ] ; then
#			echo "   $ATMIN and $SFCIN do not have matching fhour and idate! exiting." ; exit 1
#		fi
#	else
#		if [ $($SIGHDR $ATMIN fhour) != $($SFCHDR $SFCIN fhour) ] || \
#		   [ $($SIGHDR $ATMIN idate) != $($SFCHDR $SFCIN idate) ] ; then
#			echo "   $ATMIN and $SFCIN do not have matching fhour and idate! exiting." ; exit 1
#		fi
#	fi
else # restart conditions
	echo "checking for atmospheric/surface restart files in RESTARTDIR $RESTARTDIR"
	NFHOUR_ARR=()
	IDATE_ARR=()
	for file in $SIGR1 $SIGR2 $SFCR $GRDR1 $GRDR2 $FORT1051; do
		if [[ ! -f $file ]] ; then # file not found
			echo "   restart file $file not found! exiting." ; exit 1
		else # file found
			# it's good that we found the file, but we also want to be sure these files are compatible.
			# in other words, we want to have idate and fhour that all match.
			if [ $file != $FORT1051 ] ; then # $FORT1051 is binary
			# we pull the nemsio nfhour and idate into arrays:
			nfhour=`$NEMSIOGET ${file} nfhour | tr -s ' ' | cut -d' ' -f 3   | sed -e 's/\s//g'`
			idate=` $NEMSIOGET ${file} idate  | tr -s ' ' | cut -d' ' -f 3-7 | sed -e 's/\s//g'`
			# likely unnecessary to separate out the array addition, but we do it anyway
	                NFHOUR_ARR+=("$nfhour")
	                IDATE_ARR+=("$idate")
			fi
	        fi
	done
        if [ $IPE = ".true." ]; then
		for file in $RSTR ; do
			[[ ! -f $file ]] && echo "   restart file $file not found! exiting." && exit 1
		done
        fi
	# count the number of unique entries in our arrays
	uniq_fhour=($(echo "${NFHOUR_ARR[@]}" | tr ' ' '\n' | sort -u | wc -l))
	uniq_idate=($(echo "${IDATE_ARR[@]}" | tr ' ' '\n' | sort -u | wc -l))
	# if they are not one, we have disagreeing restart files
	if [ ! $uniq_fhour = 1 ] || [ ! $uniq_idate = 1 ] ; then
		echo "   there's an issue with your restart files; check the idate and nfhour to make sure they match! exiting." ; exit 1
	fi
fi # end restart block

# now do the IPE initial conditions
if [ $IPE = .true. ] ; then
	echo "looking for IPE initial conditions"
	# if user has not defined CIPEDATE, RESTART=.false. and $CDATE is good
	export CIPEDATE=${CIPEDATE:-$CDATE${IPE_MINUTES:-00}}
	IPESEARCH="${IPEBASESEARCH}.h5"
	IPEFNAME="${IPEBASESEARCH}${CIPEDATE}.h5"
	export PLASI=${PLASI:-$ROTDIR/$IPEFNAME}
	echo "searching ROTDIR, then RESTARTDIR, then IPE_IC_DIR for $IPESEARCH"
	# then we search ROTDIR, then RESTARTDIR, then IPE_IC_DIR
	if [[ -f `find -L $ROTDIR -maxdepth 1 -type f -iname "$IPEFNAME" | head -1` ]] ; then
		echo "   found in ROTDIR"
	elif [[ -f `find -L $RESTARTDIR -maxdepth 1 -type f -iname "$IPESEARCH" | head -1` ]] ; then
		echo "   found in RESTARTDIR, copying to ROTDIR"
		$NCP $RESTARTDIR/$IPESEARCH $ROTDIR/$IPEFNAME
	# IPE_IC_DIR has been defaulted to IC_DIR if IC_DIR is defined
	elif [ -n ${IPE_IC_DIR} ] && [[ -f `find -L $IPE_IC_DIR -type f -iname "$IPESEARCH" | head -1` ]] ; then
		echo "   found in IPE_IC_DIR, copying to ROTDIR"
		$NCP $IPE_IC_DIR/$IPESEARCH $ROTDIR/$IPEFNAME
	else # can't find any matching IPE initial conditions
		echo "   can't find your IPE files... check the filename convention! exiting." ; exit 1
	fi
fi

if [[ $WAM_IPE_COUPLING = .true. ]] ; then
	echo "checking properties of DELTIM and DELTIM_IPE"
	if [[ $((DELTIM_IPE%DELTIM)) != 0 ]] ; then
		echo "   DELTIM_IPE must be a multiple of DELTIM! exiting." ; exit 1
	fi
fi

echo "our enviroment seems to be good, moving to submit the job"

return 0
