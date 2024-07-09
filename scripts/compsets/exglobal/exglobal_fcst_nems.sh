#!/bin/ksh
################################################################################
####  UNIX Script Documentation Block
#                      .                                             .
# Script name:         exglobal_fcst.sh.ecf
# Script description:  Runs a global spectral model forecast
#
# Author:        Mark Iredell       Org: NP23         Date: 1999-05-01
#
# Abstract: This script runs a single or an ensemble of global spectral model
#           forecasts. The initial conditions and run parameters are either
#           passed in the argument list or imported.
#
# Script history log:
# 1999-05-01  Mark Iredell
# 2005-01-03  Sarah Lu : add namelist SOIL_VEG; set FSMCL(2:4)=FSMCL2; 
#                      : add FNVMNC,FNVMXC,FNSLPC,FNABSC
# 2006-2012   Shrinivas Moorthi 
#                      : Modified to run ESMF - Stand Alone version of ATM - Only filestyle "L" allowed 
#                      : Added a ESMF config file. The script can run up to 21 ENS members concurrently.
#                      : Added default PE$n values to 0
#                      : Added stochastic ensembles, semi-Lagrangian high frequency output, 
#                      : G3D outputs and many other upgrades related to model changes
#                      : Upgraded for the new physics and nst model
#                      : and rewrote some parts and added ensemble generality
# 2010-01     Weiyu Yang: modified for the ensemble GEFS.
# 2009-2012   Sarah Lu : ESMF_State_Namelist modified
#                      : Added GOCART_CLIM and GOCART_LUTS tracer added; (q, oz, cld) removed
#                      : modify phy_namelist.rc (set p_export/dp_export to 1)
#                      : add passive_tracer to atm_namelist.rc 
#                      : use wildcard to copy files from GOCART_CLIM to DATA
#                      : add AER, modify filename_base, file_io_form, file_io
#                      : add thermodyn_id and sfcpress_id to nam_dyn
#                      : add WRITE_DOPOST, GOCART_POSTOUT, POST_GRIBVERSION
#                      : change GOCART_POSTOUT to GOCART_AER2POST
#                      : modify how LATG is specified
# 2009-2012  Jun Wang  : add write grid component option
#                      : activate reduced grid option and digital filter option
#                      : link atm_namelist.rc to configure_file
#                      : Add restart
#                      : add option to output filtered 3hr output
#                      : add copy MAPL/CHEM config files,set default FILE_IO_FORM
#                      : add grib2 option for POST
#                      : add POST_NCEPGRB2TBL for post
#                      : set dp_import to 1 for NDSL
#                      : set sigio option
# 2010-2012 Henry Juang: add ndslfv, process_split, and mass_dp for NDSL
#                      : add JCAPG for NDSL, add option of IDEA, remove JCAPG
# 2013-07    Sarah Lu  : specify wgrib and nemsioget for multi-platform
# 2013-11  Xingren Wu  : add A2OI for Atm/Ocn/Ice coupling
# 2014-04  Xingren Wu  : add CPLFLX for Atm/Ocn/Ice coupling
# 2014-12  Kate Howard : Rework to run NEMS with GFS scripts
# 2014-2015 S. Moorthi : Clean up, fix slg option, gaea specific  etc
#                      : Clean up, unify gloabl and ngac scripts remove scheduler etc
#                      : Added THEIA option ; turned off ESMF Compliance check etc
#                      : added MICRO_PHY_DATA
# 2015-10 Fanglin Yang : debug and update to be able to run both fcst1 and fcst2 for NEMS GFS
#
# Usage:  exglobal_fcst.sh.ecf SIGI/GRDI SFCI SIGO FLXO FHOUT FHMAX IGEN D3DO NSTI NSTO FHOUT_HF FHMAX_HF
#
#   Input script positional parameters:
#     1             Input grd file 1
#                   defaults to $SIGI or $GRDI; one or the other is required
#     2             Input surface file
#                   defaults to $SFCI; one or the other is required
#     3             Output sigma file with embedded forecast hour '${FH}'
#                   defaults to $SIGO, then to ${COMOUT}/${SIGOSUF}f'${FH}'$SUFOUT
#     4             Output flux file with embedded forecast hour '${FH}'
#                   defaults to $FLXO, then to ${COMOUT}/${FLXOSUF}f'${FH}'$SUFOUT
#     5             Output frequency in hours
#                   defaults to $FHOUT, then to 3
#     6             Length of forecast in hours
#                   defaults to $FHMAX; otherwise FHSEG is required to be set
#     7             Output generating code
#                   defaults to $IGEN, defaults to 0
#     8             Output flux file with embedded forecast hour '${FH}'
#                   defaults to $D3DO, then to ${COMOUT}/d3df'${FH}'$SUFOUT
#     9             Input NST file
#     10            Output NST file
#     11            High frequency output interval ; default 1 hour
#     12            Maximum hour of high frequecny output
#
#   Imported Shell Variables:
#     SIGI/GRDI     Input sigma file
#                   overridden by $1; one or the other is required
#     SFCI          Input surface file
#                   overridden by $2; one or the other is required
#     SIGO          Output sigma file with embedded forecast hour '${FH}'
#                   overridden by $3; defaults to ${COMOUT}/${SIGOSUF}f'${FH}'$SUFOUT
#     FLXO          Output flux file with embedded forecast hour '${FH}'
#                   overridden by $4; defaults to ${COMOUT}/${FLXOSUF}f'${FH}'$SUFOUT
#     D3DO          Output d3d file with embedded forecast hour '${FH}'
#                   overridden by $4; defaults to ${COMOUT}/d3df'${FH}'$SUFOUT
#     NSTO          Output nst file with embedded forecast hour '${FH}'
#                   overridden by $4; defaults to ${COMOUT}/nstf'${FH}'$SUFOUT
#     FHOUT         Output frequency in hours
#                   overridden by $5; defaults to 3
#     FHMAX         Length of forecast in hours
#                   overridden by $6; either FHMAX or FHSEG must be set
#     IGEN          Output generating code
#                   overridden by $7; defaults to 0
#     FIXGLOBAL     Directory for global fixed files
#                   defaults to /nwprod/gsm.v12.0.0/fix/fix_am
#     EXECGLOBAL    Directory for global executables
#                   defaults to /nwprod/gsm.v12.0.0/exec
#     DATA          working directory
#                   (if nonexistent will be made, used and deleted)
#                   defaults to current working directory
#     COMOUT        output directory
#                   (if nonexistent will be made)
#                   defaults to current working directory
#     XC            Suffix to add to executables
#                   defaults to none
#     SUFOUT        Suffix to add to output filenames
#                   defaults to none
#     NCP           Copy command
#                   defaults to cp
#     SIGHDR        Command to read sigma header
#                   (required if JCAP, LEVS, or FHINI are not specified)
#                   defaults to ${EXECGLOBAL}/global_sighdr$XC
#     JCAP          Spectral truncation for model wave
#     LEVS          Number of levels
#                   defaults to the value in the input sigma file header
#     LEVR          Number of levels over which radiation is computed
#                   defaults to LEVS
#     FCSTEXEC      Forecast executable
#                   defaults to ${EXECGLOBAL}/global_fcst$XC
#     SIGI2         Second time level sigma restart file
#                   defaults to NULL
#     CO2CON        Input CO2 radiation (vertical resolution dependent)
#                   defaults to ${FIXGLOBAL}/global_co2con.l${LEVS}.f77
#     MTNVAR        Input mountain variance (horizontal resolution dependent)
#                   defaults to ${FIXGLOBAL}/global_mtnvar.t${JCAP}.f77
#     MTNRSL        A string representing topography resolution
#                   defaults to $JCAP
#     MTNRSLUF      A string representing unfiltered topography resolution
#                   defaults to $MTNRSL
#     O3FORC        Input ozone forcing (production/loss) climatology
#                   defaults to ${FIXGLOBAL}/global_o3prdlos.f77
#     O3CLIM        Input ozone climatology
#                   defaults to ${FIXGLOBAL}/global_o3clim.txt
#     FNGLAC        Input glacier climatology GRIB file
#                   defaults to ${FIXGLOBAL}/global_glacier.2x2.grb
#     FNMXIC        Input maximum sea ice climatology GRIB file
#                   defaults to ${FIXGLOBAL}/global_maxice.2x2.grb
#     FNTSFC        Input SST climatology GRIB file
#                   defaults to ${FIXGLOBAL}/global_sstclim.2x2.grb
#     FNSNOC        Input snow climatology GRIB file
#                   defaults to ${FIXGLOBAL}/global_snoclim.1.875.grb
#     FNZORC        Input roughness climatology GRIB file
#                   defaults to 'sib' (From sib vegetation-based lookup table.
#                   FNVETC must be set to sib file: ${FIXGLOBAL}/global_vegtype.1x1.grb)
#     FNALBC        Input albedo climatology GRIB file
#                   defaults to ${FIXGLOBAL}/global_albedo4.1x1.grb
#     FNAISC        Input sea ice climatology GRIB file
#                   defaults to ${FIXGLOBAL}/global_iceclim.2x2.grb
#     FNTG3C        Input deep soil temperature climatology GRIB file
#                   defaults to ${FIXGLOBAL}/global_tg3clim.2.6x1.5.grb
#     FNVEGC        Input vegetation fraction climatology GRIB file
#                   defaults to ${FIXGLOBAL}/global_vegfrac.1x1.grb
#     FNVETC        Input vegetation type climatology GRIB file
#                   defaults to ${FIXGLOBAL}/global_vegtype.1x1.grb
#     FNSOTC        Input soil type climatology GRIB file
#                   defaults to ${FIXGLOBAL}/global_soiltype.1x1.grb
#     FNSMCC        Input soil moisture climatology GRIB file
#                   defaults to ${FIXGLOBAL}/global_soilmcpc.1x1.grb
#     FNVMNC        Input min veg frac climatology GRIB file    
#                   defaults to ${FIXGLOBAL}/global_shdmin.0.144x0.144.grb
#     FNVMXC        Input max veg frac climatology GRIB file    
#                   defaults to ${FIXGLOBAL}/global_shdmax.0.144x0.144.grb
#     FNSLPC        Input slope type climatology GRIB file    
#                   defaults to ${FIXGLOBAL}/global_slope.1x1.grb
#     FNABSC        Input max snow albedo climatology GRIB file    
#                   defaults to ${FIXGLOBAL}/global_snoalb.1x1.grb
#     OROGRAPHY     Input orography GRIB file (horiz resolution dependent)
#                   defaults to ${FIXGLOBAL}/global_orography.t$JCAP.grb
#     OROGRAPHY_UF  Input unfiltered orography GRIB file (resolution dependent)
#                   defaults to ${FIXGLOBAL}/global_orography_uf.t$JCAP.grb
#     LONSPERLAT    Input txt file containing reduced grid information
#                   defaults to ${FIXGLOBAL}/global_lonsperlat.t$MTNRSL.txt}
#     FNMSKH        Input high resolution land mask GRIB file
#                   defaults to ${FIXGLOBAL}/seaice_newland.grb
#     FNTSFA        Input SST analysis GRIB file
#                   defaults to none
#     FNACNA        Input sea ice analysis GRIB file
#                   defaults to none
#     FNSNOA        Input snow analysis GRIB file
#                   defaults to none
#     AERODIR       Input aersol climatology directory
#                   defaults to ${FIXGLOBAL}
##########################################################################
#     FIX_RAD       Directory for global fixed files
#                   Defaults to $${FIXGLOBAL}
#     EMISDIR       Input earth's surface emissivity data directory
#                   defaults to ${FIX_RAD} - export IEMS=1 to activate
#     SOLCDIR       11 year cycle Solar constat data directory
#                   defaults to ${FIX_RAD} - export ISOL=1,2,3,4, or 10 to activate
#     VOLCDIR       Volcanic aerosol  data directory
#                   defaults to ${FIX_RAD} - export IAER=100,101, or 110 to activate
#     CO2DIR        Historical CO2 data directory
#                   defaults to ${FIX_RAD} - export ICO2=1 or 2 to activate
#                   ICO2=1 gives annual mean and ICO2=2 uses monthly 2D data
##########################################################################
#     GOCART_CLIM   Directory for gocart climo files
#                   Defaults to $${FIXGLOBAL}
#     GOCARTC_LUTS  Directory for gocart luts files
#                   Defaults to $${FIXGLOBAL}
#     SIGR1         Output first time level sigma restart file
#                   defaults to ${DATA}/sigr1 which is deleted
#     SIGR2         Output second time level sigma restart file
#                   defaults to ${DATA}/sigr2 which is deleted
#     SFCR          Output surface restart file
#                   defaults to ${DATA}/sfcr which is deleted
#     NSTR          Output nst restart file
#                   defaults to ${DATA}/nstr which is deleted
#     SFCO          Output surface file with embedded forecast hour '${FH}'
#                   defaults to ${COMOUT}/${SFCOSUF}f'${FH}'$SUFOUT
#     LOGO          Output log file with embedded forecast hour '${FH}'
#                   defaults to ${COMOUT}/logf'${FH}'$SUFOUT
#     INISCRIPT     Preprocessing script
#                   defaults to none
#     LOGSCRIPT     Log posting script
#                   defaults to none
#     ERRSCRIPT     Error processing script
#                   defaults to 'eval [[ $err = 0 ]]'
#     ENDSCRIPT     Postprocessing script
#                   defaults to none
#     FHINI         Starting forecast hour
#                   defaults to the value in the input sigma file header
#     FHSEG         Number of hours to integrate
#                   (only required if FHMAX is not specified)
#                   defaults to 0
#     DELTIM        Timestep in seconds
#                   defaults to 3600/($JCAP/20)
#     FHRES         Restart frequency in hours
#                   defaults to 24
#     FHZER         Zeroing frequency in hours
#                   defaults to 6
#     FHLWR         Longwave radiation frequency in seconds
#                   defaults to 3600
#     FHSWR         Shortwave radiation frequency in seconds
#                   defaults to 3600
#     FHROT         Forecast hour to Read One Time level
#                   defaults to 0
#     FHDFI         Half number of hours of digital filter initialization
#                   defaults to 0
#     FHCYC         Surface cycling frequency in hours
#                   defaults to 0 for no cycling
#     IDVC          Integer ID of the vertical coordinate type
#                   defaults to that in the header for the input upperair
#                   file. IDVC=1 for sigma; IDVC=2 for pressure/sigma hybrid
#     TFILTC        Time filter coefficient
#                   defaults to 0.85
#     DYNVARS       Other namelist inputs to the dynamics executable
#                   defaults to none set
#     PHYVARS       Other namelist inputs to the physics executable
#                   defaults to none set
#     TRACERVARS    Other namelist inputs to the forecast executable
#                   defaults to none set
#     FSMCL2        Scale in days to relax to soil moisture climatology
#                   defaults to 99999 for no relaxation
#     FTSFS         Scale in days to relax to SST anomaly to zero
#                   defaults to 90
#     FAISS         Scale in days to relax to sea ice to climatology
#                   defaults to 99999
#     FSNOL         Scale in days to relax to snow to climatology
#                   defaults to 99999
#     FSICL         Scale in days to relax to sea ice to climatology
#                   defaults to 99999
#     FZORL         Scale in days to relax to roughness climatology.
#                   defaults to 99999 because the 'sib' option sets
#                   roughness from a lookup table and is static.
#     CYCLEVARS     Other namelist inputs to the surface cycling
#                   defaults to none set
#     NTHREADS      Number of threads
#                   defaults to 1
#     SPECTRAL_LOOP Number of spectral loops
#                   defaults to 2
#     NTHSTACK      Size of stack per thread
#                   defaults to 64000000
#     FILESTYLE     File management style flag
#                   ('L' for symbolic links in $DATA is the only allowed style),
#     PGMOUT        Executable standard output
#                   defaults to $pgmout, then to '&1'
#     PGMERR        Executable standard error
#                   defaults to $pgmerr, then to '&1'
#     pgmout        Executable standard output default
#     pgmerr        Executable standard error default
#     REDOUT        standard output redirect ('1>' or '1>>')
#                   defaults to '1>', or to '1>>' to append if $PGMOUT is a file
#     REDERR        standard error redirect ('2>' or '2>>')
#                   defaults to '2>', or to '2>>' to append if $PGMERR is a file
#     VERBOSE       Verbose flag (YES or NO)
#                   defaults to NO
#
#   Exported Shell Variables:
#     PGM           Current program name
#     pgm
#     ERR           Last return code
#     err
#
#   Modules and files referenced:
#     scripts    : $INISCRIPT
#                  $LOGSCRIPT
#                  $ERRSCRIPT
#                  $ENDSCRIPT
#
#     programs   : $FCSTEXEC
#
#     input data : $1 or $SIGI
#                  $2 or $SFCI
#                  $SIGI2
#                  $FNTSFA
#                  $FNACNA
#                  $FNSNOA
#
#     fixed data : $CO2CON
#                  $MTNVAR
#                  $O3FORC
#                  $O3CLIM
#                  $FNGLAC
#                  $FNMXIC
#                  $FNTSFC
#                  $FNSNOC
#                  $FNZORC
#                  $FNALBC
#                  $FNAISC
#                  $FNTG3C
#                  $FNVEGC
#                  $FNVETC
#                  $FNSOTC
#                  $FNSMCC
#                  $FNVMNC
#                  $FNVMXC
#                  $FNSLPC
#                  $FNABSC
#                  $FNMSKH
#                  $OROGRAPHY
#                  $OROGRAPHY_UF
#                  $LONSPERLAT
#
#     output data: $3 or $SIGO
#                  $4 or $FLXO
#                  $SFCO
#                  $LOGO
#                  $SIGR1
#                  $SIGR2
#                  $SFCR
#                  $NSTR
#                  $PGMOUT
#                  $PGMERR
#
#     scratch    : ${DATA}/fort.11
#                  ${DATA}/fort.12
#                  ${DATA}/fort.14
#                  ${DATA}/fort.15
#                  ${DATA}/fort.24
#                  ${DATA}/fort.28
#                  ${DATA}/fort.29
#                  ${DATA}/fort.48
#                  ${DATA}/fort.51
#                  ${DATA}/fort.52
#                  ${DATA}/fort.53
#                  ${DATA}/SIG.F*
#                  ${DATA}/SFC.F*
#                  ${DATA}/FLX.F*
#                  ${DATA}/LOG.F*
#                  ${DATA}/D3D.F*
#                  ${DATA}/G3D.F*
#                  ${DATA}/NST.F*
#                  ${DATA}/sigr1
#                  ${DATA}/sigr2
#                  ${DATA}/sfcr
#                  ${DATA}/nstr
#                  ${DATA}/NULL
#
# Remarks:
#
#   Condition codes
#      0 - no problem encountered
#     >0 - some problem encountered
#
#  Control variable resolution priority
#    1 Command line argument.
#    2 Environment variable.
#    3 Inline default.
#
# Attributes:
#   Language: POSIX shell
#   Machine: WCOSS, GAEA, THEIA
#
####
################################################################################
#  Set environment.
export VERBOSE=${VERBOSE:-"NO"}
if [[ $VERBOSE = YES ]] ; then
  echo $(date) EXECUTING $0 $* >&2
  set -x
fi
#
export COMPLIANCECHECK=${COMPLIANCECHECK:-OFF}
export ESMF_RUNTIME_COMPLIANCECHECK=$COMPLIANCECHECK:depth=4
#
export APRUN=${APRUN:-""}
export FCST_LAUNCHER=${FCST_LAUNCHER:-$APRUN}
export model=${model:-global}
export NEMSIO_IN=${NEMSIO_IN:-".true."}
export NEMSIO_OUT=${NEMSIO_OUT:-".true."}
export ENS_NUM=${ENS_NUM:-1}
export FM=${FM}

#  Command line arguments.
#if [ $NEMSIO_IN = .false. ] ; then
# export SIGI=${1:-${SIGI:-?}}
#else
# export GRDI=${1:-${GRDI:-?}}
# export SIGI=${1:-${GRDI:-?}}
#fi

export SFCI=${2:-${SFCI:-?}}
export SIGO=${3:-${SIGO}}
export FLXO=${4:-${FLXO}}
export FHOUT=${5:-${FHOUT:-3}}
export FHMAX=${6:-${FHMAX:-0}}
export IGEN=${7:-${IGEN:-0}}
export D3DO=${8:-${D3DO}}
export NSTI=${9:-${NSTI:-?}}
export NSTO=${10:-${NSTO}}
export FHOUT_HF=${11:-${FHOUT_HF:-0}}
export FHMAX_HF=${12:-${FHMAX_HF:-0}}
export AERO=${13:-${AERO}}

# DHOU 02/28/2008 Modified for general case
# DHOU 01/07/2008 Added two input for the GEFS_Cpl module
# FHM_FST is the FHMAX for the integration before the first stop
# FH_INC is the FHMAX_increase for the integration before next stop
export FH_INC=${FH_INC:-100000000}
export ENS_SPS=${ENS_SPS:-.false.}
export ADVANCECOUNT_SETUP=${ADVANCECOUNT_SETUP:-0}
export HOUTASPS=${HOUTASPS:-10000}

export SPS_PARM1=${SPS_PARM1:-"0.005 10.0 0.005 10.0 0.0 0.0 0.0 0.0 0.0 0.0"}
export SPS_PARM2=${SPS_PARM2:-"0.105 0.03 0.12 42.0 0.0 0.0 0.0 0.0 0.0 0.0"}
export SPS_PARM3=${SPS_PARM3:-"0.2 0.34 -0.34 3.0 0.0 0.0 0.0 0.0 0.0 0.0"}

[[ $ENS_NUM -lt 2 ]]&&ENS_SPS=.false.
if [ $ENS_SPS = .false. ] ; then export FH_INC=$FHMAX ; fi

#  Directories.
export gsm_ver=${gsm_ver:-v14.0.0}
export BASEDIR=${BASEDIR:-/nwprod}
export NWPROD=${NWPROD:-$BASEDIR}
export FIXSUBDA=${FIXSUBDA:-fix/fix_am}
export FIXGLOBAL=${FIXGLOBAL:-$NWPROD/gsm.$gsm_ver/$FIXSUBDA}
export FIX_RAD=${FIX_RAD:-$FIXGLOBAL}
export FIX_IDEA=${FIX_IDEA:-$FIXGLOBAL}
export FIX_NGAC=${FIX_NGAC:-$NWPROD/fix/fix_ngac}
export PARMSUBDA=${PARMSUBDA:-parm/parm_am}
export PARMGLOBAL=${PARMGLOBAL:-$NWPROD/gsm.$gsm_ver/$PARMSUBDA}
export PARM_NGAC=${PARM_NGAC:-$NWPROD/parm/parm_ngac}
export EXECGLOBAL=${EXECGLOBAL:-$NWPROD/exec}
export DATA=${DATA:-$(pwd)}
export COMOUT=${COMOUT:-$(pwd)}

#  Filenames.
MN=${MN:-""}
export XC=${XC}
export SUFOUT=${SUFOUT}

#  Executables.
export NCP=${NCP:-"/bin/cp -p"}
export NDATE=${NDATE:-$NWPROD/util/exec/ndate}
export MDATE=${MDATE:-$NWPROD/util/exec/mdate}

export NEMSIOGET=${NEMSIOGET:-/nwprod/ngac.v1.0.0/exec/nemsio_get}
if [ $NEMSIO_IN = .true. ]; then
 export JCAP=${JCAP:-$($NEMSIOGET ${GRDI}$FM jcap |grep -i "jcap" |awk -F"= " '{print $2}' |awk -F" " '{print $1}')}
 export LEVS=${LEVS:-$($NEMSIOGET ${GRDI}$FM levs|grep -i "levs" |awk -F"= " '{print $2}' |awk -F" " '{print $1}')}
 export LEVR=${LEVR:-$LEVS}
 export LONF=${LONF:-$($NEMSIOGET ${GRDI}$FM LONF|grep -i "lonf" |awk -F"= " '{print $2}' |awk -F" " '{print $1}')}
 if [[ ${RESTART:-".false."} = .true. ]] ; then
  export LATG=${LATG:-$($NEMSIOGET ${GRDI}$FM LATF|grep -i "latf" |awk -F"= " '{print $2}' |awk -F" " '{print $1}')}
 else
  export LATG=${LATG:-$($NEMSIOGET ${GRDI}$FM LATG|grep -i "latg" |awk -F"= " '{print $2}' |awk -F" " '{print $1}')}
 fi
 export LONR=${LONR:-$LONF}
 export LATR=${LATR:-$LATG}
 export NTRAC=${NTRAC:-$($NEMSIOGET ${GRDI}$FM NTRAC|grep -i "NTRAC" |awk -F"= " '{print $2}' |awk -F" " '{print $1}')}
 export IDVC=${IDVC:-$($NEMSIOGET ${GRDI}$FM IDVC |grep -i "IDVC" |awk -F"= " '{print $2}' |awk -F" " '{print $1}')}
 export IDVM=${IDVM:-$($NEMSIOGET ${GRDI}$FM IDVM |grep -i "IDVM" |awk -F"= " '{print $2}' |awk -F" " '{print $1}')}
 export FHINI=${FHINI:-$($NEMSIOGET ${GRDI}$FM NFHOUR |grep -i "NFHOUR" |awk -F"= " '{print $2}' |awk -F" " '{print $1}')}
else


 export SFCHDR=${SFCHDR:-${EXECGLOBAL}/global_sfchdr$XC}
 export CHGSFCFHREXEC=${CHGSFCFHREXEC:-/swpc/save/swpc.spacepara/util/chgsfcfhr/chgsfcfhr}
 export SIGHDR=${SIGHDR:-${EXECGLOBAL}/global_sighdr$XC}
 export JCAP=${JCAP:-$(echo jcap|$SIGHDR ${SIGI}$FM)}
 export LEVS=${LEVS:-$(echo levs|$SIGHDR ${SIGI}$FM)}
 export LEVR=${LEVR:-$LEVS}
 export LONR=${LONR:-$(echo lonr|$SIGHDR ${SIGI}$FM)}
 export LATR=${LATR:-$(echo latr|$SIGHDR ${SIGI}$FM)}
 export LONF=${LONF:-$(echo lonf|$SIGHDR ${SIGI}$FM)}
 export LATG=${LATG:-$(echo latf|$SIGHDR ${SIGI}$FM)}
 export NTRAC=${NTRAC:-$(echo ntrac|$SIGHDR ${SIGI}$FM)}
 export IDVC=${IDVC:-$(echo idvc|$SIGHDR ${SIGI}$FM)}
 export IDVM=${IDVM:-$(echo idvm|$SIGHDR ${SIGI}$FM)}
 export FHINI=${FHINI:-$(echo ifhr|$SIGHDR ${SIGI}$FM)}
fi

export LONB=${LONB:-$LONF}
export LATB=${LATB:-$LATG}
export THERMODYN_ID=${THERMODYN_ID:-$((IDVM/10))}
export SFCPRESS_ID=${SFCPRESS_ID:-$((IDVM-(IDVM/10)*10))}
export NMTVR=${NMTVR:-14}
export LSOIL=${LSOIL:-4}
export NTOZ=${NTOZ:-2}
export NTCW=${NTCW:-3}
export NCLD=${NCLD:-1}
export NGPTC=${NGPTC:-30}

export ADIAB=${ADIAB:-.false.}
export nsout=${nsout:-0}
export LDFIFLTO=${LDFIFLTO:-.false.}
export LDFI_GRD=${LDFI_GRD:-.false.}
export DFILEVS=${DFILEVS:-$LEVS}
export NUM_FILE=${NUM_FILE:-3}
export QUILTING=${QUILTING:-.true.}
export REDUCED_GRID=${REDUCED_GRID:-.true.}
export PASSIVE_TRACER=${PASSIVE_TRACER:-.false.}
export NST_FCST=${NST_FCST:-0}
export IAER=${IAER:-0}
export GOCART=${GOCART:-0}
export NGRID_A2OI=${NGRID_A2OI:-20}
export A2OI_OUT=${A2OI_OUT:-.false.}
export CPLFLX=${CPLFLX:-.false.}
export NDSLFV=${NDSLFV:-.false.}
export EXPLICIT=${EXPLICIT:-.false.}
export MASS_DP=${MASS_DP:-.false.}
export PROCESS_SPLIT=${PROCESS_SPLIT:-.false.}
export dp_import=${dp_import:-1}
export p_import=${p_import:-1}
export dpdt_import=${dpdt_import:-0}
if [ $NDSLFV = .true. ] ; then
 export MASS_DP=.true.
 export PROCESS_SPLIT=.false.
 export dp_import=1
fi
export ZFLXTVD=${ZFLXTVD:-.false.}
export SEMI_IMPLICIT_TEMP_PROFILE=${SEMI_IMPLICIT_TEMP_PROFILE:-.false.}
#
export FCSTEXEC=${FCSTEXEC:-${EXECGLOBAL}/${model}_fcst$XC}
export GRDI2=${GRDI2:-NULL}
export SIGI2=${SIGI2:-NULL}
export CO2CON=${CO2CON:-${FIXGLOBAL}/global_co2con.l${LEVS}.f77}
export MTNRSL=${MTNRSL:-$JCAP}
export MTNRSLUF=${MTNRSLUF:-$MTNRSL}
export MTNVAR=${MTNVAR:-${FIXGLOBAL}/global_mtnvar.t$MTNRSL.f77}
export O3FORC=${O3FORC:-${FIXGLOBAL}/global_o3prdlos.f77}
export O3CLIM=${O3CLIM:-${FIXGLOBAL}/global_o3clim.txt}
export FNGLAC=${FNGLAC:-${FIXGLOBAL}/global_glacier.2x2.grb}
export FNMXIC=${FNMXIC:-${FIXGLOBAL}/global_maxice.2x2.grb}
#export FNTSFC=${FNTSFC:-${FIXGLOBAL}/cfs_oi2sst1x1monclim19822001.grb}
export FNTSFC=${FNTSFC:-${FIXGLOBAL}/RTGSST.1982.2012.monthly.clim.grb}
export FNSNOC=${FNSNOC:-${FIXGLOBAL}/global_snoclim.1.875.grb}
#export FNZORC=${FNZORC:-${FIXGLOBAL}/global_zorclim.1x1.grb}
export FNZORC=${FNZORC:-sib}
export FNALBC=${FNALBC:-${FIXGLOBAL}/global_albedo4.1x1.grb}
#export FNAISC=${FNAISC:-${FIXGLOBAL}/cfs_ice1x1monclim19822001.grb}
export FNAISC=${FNAISC:-${FIXGLOBAL}/CFSR.SEAICE.1982.2012.monthly.clim.grb}
export FNTG3C=${FNTG3C:-${FIXGLOBAL}/global_tg3clim.2.6x1.5.grb}
export FNVEGC=${FNVEGC:-${FIXGLOBAL}/global_vegfrac.0.144.decpercent.grb}
export FNVETC=${FNVETC:-${FIXGLOBAL}/global_vegtype.1x1.grb}
export FNSOTC=${FNSOTC:-${FIXGLOBAL}/global_soiltype.1x1.grb}
#export FNSMCC=${FNSMCC:-${FIXGLOBAL}/global_soilmcpc.1x1.grb}
export FNSMCC=${FNSMCC:-${FIXGLOBAL}/global_soilmgldas.t${JCAP}.${LONR}.${LATR}.grb}
export FNVMNC=${FNVMNC:-${FIXGLOBAL}/global_shdmin.0.144x0.144.grb}
export FNVMXC=${FNVMXC:-${FIXGLOBAL}/global_shdmax.0.144x0.144.grb}
export FNSLPC=${FNSLPC:-${FIXGLOBAL}/global_slope.1x1.grb}
export FNABSC=${FNABSC:-${FIXGLOBAL}/global_snoalb.1x1.grb}
export FNMSKH=${FNMSKH:-${FIXGLOBAL}/seaice_newland.grb}
export OROGRAPHY=${OROGRAPHY:-${FIXGLOBAL}/global_orography.t$MTNRSL.grb}
export OROGRAPHY_UF=${OROGRAPHY_UF:-${FIXGLOBAL}/global_orography_uf.t$MTNRSLUF.grb}
export LONSPERLAT=${LONSPERLAT:-${FIXGLOBAL}/global_lonsperlat.t${JCAP_TMP}.$LONB_TMP.$LATB_TMP.txt}
export LONSPERLAR=${LONSPERLAR:-$LONSPERLAT}
export FNTSFA=${FNTSFA}
export FNACNA=${FNACNA}
export FNSNOA=${FNSNOA}
#
export AERODIR=${AERODIR:-${FIX_RAD}}
export EMISDIR=${EMISDIR:-${FIX_RAD}}
export SOLCDIR=${SOLCDIR:-${FIX_RAD}}
export VOLCDIR=${VOLCDIR:-${FIX_RAD}}
export CO2DIR=${CO2DIR:-${FIX_RAD}}
export GOCART_CLIM=${GOCART_CLIM:-${FIX_RAD}}
export GOCART_LUTS=${GOCART_LUTS:-${FIX_RAD}}
#export ALBDIR=${ALBDIR:-${FIX_RAD}}
export IEMS=${IEMS:-0}
export ISOL=${ISOL:-0}
export IAER=${IAER:-0}
export ICO2=${ICO2:-0}
export IALB=${IALB:-0}
#
LOCD=${LOCD:-""}
export COMENS=$COMOUT'$LOCD'
export GRDR1=${GRDR1:-${COMENS}/grdr1}
export GRDR2=${GRDR2:-${COMENS}/grdr2}
export SIGR1=${SIGR1:-${COMENS}/sigr1}
export SIGR2=${SIGR2:-${COMENS}/sigr2}
export SFCR=${SFCR:-${COMENS}/sfcr}
export NSTR=${NSTR:-${COMENS}/nstr}

export SIGS1=${SIGS1:-${COMENS}/sigs1}
export SIGS2=${SIGS2:-${COMENS}/sigs2}
export SFCS=${SFCS:-${COMENS}/sfcs}
export NSTS=${NSTS:-${COMENS}/nsts}

## History Files
export SIGO=${SIGO:-${COMENS}/${SIGOSUF}f'${FHIAU}''${MN}'$SUFOUT}
export SFCO=${SFCO:-${COMENS}/${SFCOSUF}f'${FHIAU}''${MN}'$SUFOUT}
export FLXO=${FLXO:-${COMENS}/${FLXOSUF}f'${FHIAU}''${MN}'$SUFOUT}
export LOGO=${LOGO:-${COMENS}/logf'${FHIAU}''${MN}'$SUFOUT}
export D3DO=${D3DO:-${COMENS}/d3df'${FHIAU}''${MN}'$SUFOUT}
export NSTO=${NSTO:-${COMENS}/${NSTOSUF}f'${FHIAU}''${MN}'$SUFOUT}
export AERO=${AERO:-${COMOUT}/aerf'${FH}''${MN}'$SUFOUT}
export PLASO=${PLASO:-'IPE_State.apex.${TIMESTAMP}.h5'}

export INISCRIPT=${INISCRIPT}
export ERRSCRIPT=${ERRSCRIPT:-'eval [[ $err = 0 ]]'}
export LOGSCRIPT=${LOGSCRIPT}
export ENDSCRIPT=${ENDSCRIPT}

#  Other variables.
export FHSEG=${FHSEG:-0}
export FHMAX=${FHMAX:-$((10#$FHINI+10#$FHSEG))}
export DELTIM=${DELTIM:-$((3600/(JCAP/20)))}
export DTPHYS=${DTPHYS:-$((DELTIM/2))}
export FHRES=${FHRES:-24}
export FHZER=${FHZER:-6}
export FHLWR=${FHLWR:-3600}
export FHSWR=${FHSWR:-3600}
export FHROT=${FHROT:-0}
export FHDFI=${FHDFI:-1}

export FHCYC=${FHCYC:-0}

export nhours_dfini=${nhours_dfini:-$FHDFI}
export GB=${GB:-0}
export gfsio_in=${gfsio_in:-.false.}
if [ $gfsio_in = .true. ] ; then export GB=1 ; fi

#        WAM-IPE related namelist variables
#        ------------------------------
export IDEA=${IDEA:-.false.}
export WAM_IPE_COUPLING=${WAM_IPE_COUPLING:-.false.}
export HEIGHT_DEPENDENT_G=${HEIGHT_DEPENDENT_G:-.false.}
export INPUT_PARAMETERS=${INPUT_PARAMETERS:-fixderive}
export FIX_F107=${FIX_F107:-120.0}
export FIX_KP=${FIX_KP:-3.0}
export F107_KP_SIZE=${F107_KP_SIZE:-$((60*37+1))}
export F107_KP_DATA_SIZE=${F107_KP_DATA_SIZE:-$((60*37+1))}
export F107_KP_SKIP_SIZE=${F107_KP_SKIP_SIZE:-0}
export F107_KP_INTERVAL=${F107_KP_INTERVAL:-10800}
export IPEFREQ=${IPEFREQ:-3600}
export IPEFMAX=${IPEFMAX:-$((FHMAX*3600))}

## wam_control_in
export JH0=${JH0:-1.75}
export JH_tanh=${JH_tanh:-0.5}
export JH_semiann=${JH_semiann:-0.5}
export JH_ann=${JH_ann:-0.0}
export JH_st0=${JH_st0:-25000.0}
export JH_st1=${JH_st1:-5000.0}

export skeddy0=${skeddy0:-"70.0"}
export skeddy_semiann=${skeddy_semiann:-"-10.0"}
export skeddy_ann=${skeddy_ann:-0.0}

export tkeddy0=${tkeddy0:-280.0}
export tkeddy_semiann=${tkeddy_semiann:-0.0}
export tkeddy_ann=${tkeddy_ann:-0.0}

## for post
export WRITE_DOPOST=${WRITE_DOPOST:-.false.}
export GOCART_AER2POST=${GOCART_AER2POST:-.false.}
export POST_GRIBVERSION=${POST_GRIBVERSION:-grib1}
export POSTCTLFILE=${POSTCTLFILE:-$PARM_NGAC/ngac_postcntrl.parm}
export POST_PARM=${POST_PARM:-$PARM_NGAC/ngac_postcntrl.xml}
export POST_AVBLFLDSXML=${POST_AVBLFLDSXML:-$PARM_NGAC/ngac_post_avblflds.xml}
export POST_NCEPGRB2TBL=${POST_NCEPGRB2TBL:-$NWPROD/lib/sorc/g2tmpl/params_grib2_tbl_new}

## copy/link post related files
if [[ $WRITE_DOPOST = .true. ]] ; then
 if [[ $POST_GRIBVERSION = grib1 ]] ; then
   #ln -sf ${POSTCTLFILE} fort.14
   ${NCP} ${POSTCTLFILE} fort.14
 elif [[ $POST_GRIBVERSION = grib2 ]] ; then
   ${NCP} ${POST_PARM}        postcntrl.xml
   ${NCP} ${POST_AVBLFLDSXML} post_avblflds.xml
   ${NCP} ${POST_NCEPGRB2TBL} params_grib2_tbl_new
 fi
 ln -sf griddef.out fort.110
 MICRO_PHYS_DATA=${MICRO_PHYS_DATA:-${POST_LUTDAT:-$NWPROD/$PARMSUBDA/nam_micro_lookup.dat}}
 ${NCP} $MICRO_PHYS_DATA ./eta_micro_lookup.dat
fi
#
# Total pe = WRT_GROUP*WRTPE_PER_GROUP + fcst pes
#
export WRT_GROUP=${WRT_GROUP:-1}
export WRTPE_PER_GROUP=${WRTPE_PER_GROUP:-1}
export WRITE_NEMSIOFLAG=${WRITE_NEMSIOFLAG:-.true.}
export QUILTING=${QUILTING:-.true.}
export GOCART_AER2POST=${GOCART_AER2POST:-.false.}
if [ $NEMSIO_IN = .true. ]; then
  export FILE_IO_FORM=${FILE_IO_FORM:-"'bin4' 'bin4' 'bin4'"}
else
  export FILE_IO_FORM=${FILE_IO_FORM:-"'grib' 'grib' 'grib'"}
fi

#
export LWRTGRDCMP=${LWRTGRDCMP:-".true."}
if [ $NEMSIO_OUT = .false. -a $WRITE_DOPOST = .false. ] ; then
  export LWRTGRDCMP=.false.
fi
# number of output files, default =3, for adiab num_file=1
ioform_sig=${ioform_sig:-bin4}
ioform_sfc=${ioform_sfc:-bin4}
ioform_flx=${ioform_flx:-bin4}
if [[ $ADIAB = .true. ]] ; then
  export NUM_FILE=1 ;
  export FILENAME_BASE="'SIG.F'"
  export FILE_IO_FORM="'bin4'"
else
  export FILENAME_BASE="'SIG.F' 'SFC.F' 'FLX.F'"
  export FILE_IO_FORM=${FILE_IO_FORM:-"'bin4' 'bin4' 'bin4'"}
  export NUM_FILE=3

  if [ $NST_FCST -gt 0 ] ; then
    export FILENAME_BASE=${FILENAME_BASE}" 'NST.F'"
    export FILE_IO_FORM=${FILE_IO_FORM}" 'bin4'"
    export NUM_FILE=$((NUM_FILE+1))
    if [ $NST_FCST -eq 1 ]; then
      NST_SPINUP=1
    fi
  fi
  if [ $GOCART == 1 ] ; then
    export FILENAME_BASE=${FILENAME_BASE}" 'AER.F'"
    export FILE_IO_FORM=${FILE_IO_FORM}" 'grib'"
    export NUM_FILE=$((NUM_FILE+1))
  fi
  echo "NUM_FILE=$NUM_FILE,GOCART=$GOCART,NST_FCST=$NST_FCST,FILENAME_BASE=$FILENAME_BASE"
fi
export NST_SPINUP=${NST_SPINUP:-0}


#wanghj
export NST_FCST=${NST_FCST:-0}
export NST_SPINUP=${NST_SPINUP:-0}
export NST_RESERVED=${NST_RESERVED:-0}
export ZSEA1=${ZSEA1:-0}
export ZSEA2=${ZSEA2:-0}

export nstf_name="$NST_FCST,$NST_SPINUP,$NST_RESERVED,$ZSEA1,$ZSEA2"
export NST_ANL=${NST_ANL:-.false.}



#
if [ $IDVC = 1 ] ; then
 export HYBRID=.false.
 export GEN_COORD_HYBRID=.false.
elif [ $IDVC = 2 ] ; then
 export HYBRID=.true.
 export GEN_COORD_HYBRID=.false.
elif [ $IDVC = 3 ] ; then
 export HYBRID=.false.
 export GEN_COORD_HYBRID=.true.
fi
export TFILTC=${TFILTC:-0.85}
export DYNVARS=${DYNVARS:-""}
export PHYVARS=${PHYVARS:-""}
export TRACERVARS=${TRACERVARS:-""}
export FSMCL2=${FSMCL2:-99999}
export FTSFS=${FTSFS:-90}
export FAISS=${FAISS:-99999}
export FSNOL=${FSNOL:-99999}
export FSICL=${FSICL:-99999}
export CYCLVARS=${CYCLVARS}
export POSTGPVARS=${POSTGPVARS}
export NTHREADS=${NTHREADS:-1}
export SEMILAG=${SEMILAG:-${semilag:-.false.}}
export OMP_NUM_THREADS=${OMP_NUM_THREADS:-${NTHREADS:-1}}
export SPECTRAL_LOOP=${SPECTRAL_LOOP:-2}
export FILESTYLE=${FILESTYLE:-'L'}
export PGMOUT=${PGMOUT:-${pgmout:-'&1'}}
export PGMERR=${PGMERR:-${pgmerr:-'&2'}}
export MEMBER_NAMES=${MEMBER_NAMES:-''}

export REDOUT=${REDOUT:-'1>'}
export REDERR=${REDERR:-'2>'}
export print_esmf=${print_esmf:-.false.}

################################################################################
#  Preprocessing
$INISCRIPT
pwd=$(pwd)
if [[ -d $DATA ]] ; then
   mkdata=NO
else
   mkdir -p $DATA
   mkdata=YES
fi
cd $DATA||exit 99
[[ -d $COMOUT ]]||mkdir -p $COMOUT
################################################################################
#  Make forecast
export PGM='$FCST_LAUNCHER $DATA/$(basename $FCSTEXEC)'
export pgm=$PGM
$LOGSCRIPT
${NCP:-cp} $FCSTEXEC $DATA

#------------------------------------------------------------
if [ $FHROT -gt 0 ] ; then export RESTART=.true. ; fi
export RESTART=${RESTART:-.false.}
if [ $RESTART = .false. ] ; then # when restarting should not remove - Weiyu
  rm -f NULL
fi

if [[ $NEMS = .true. ]] ; then
  if [ $NEMSIO_IN = .true. ]; then
    idate=` $NEMSIOGET $GRDI idate  | tr -s ' ' | cut -d' ' -f 3-7`
    iyear=` echo $idate | cut -d' ' -f 1`
    imonth=`printf "%02d" $(echo $idate | cut -d' ' -f 2)`
    iday=`  printf "%02d" $(echo $idate | cut -d' ' -f 3)`
    ihour=` printf "%02d" $(echo $idate | cut -d' ' -f 4)`
    export CDATE=${iyear}${imonth}${iday}${ihour}
    nfhour=`$NEMSIOGET $GRDI nfhour | tr -s ' ' | cut -d' ' -f 3`
    export FDATE=`$NDATE $nfhour $CDATE`
  else
    export CDATE=`$SIGHDR $SIGI idate`
    export FDATE=`$NDATE \`$SIGHDR $SIGI fhour | cut -d'.' -f 1\` $CDATE`
  fi
else
  FDATE=$(echo $CIPEDATE | cut -c1-10)
fi

GDATE=$($NDATE -6 $CDATE)

FH=$((10#$FHINI))
[[ $FH -lt 10 ]]&&FH=0$FH
if [[ $FHINI -gt 0 ]] ; then
   if [ $FHOUT_HF -ne $FHOUT -a $FH -lt $FHMAX_HF ] ; then
    FH=$((10#$FHINI+10#$FHOUT_HF))
   else
    FH=$((10#$FHINI+10#$FHOUT))
   fi
   [[ $FH -lt 10 ]]&&FH=0$FH
fi
while [[ 10#$FH -le $FHMAX ]] ; do
   if [[ $FH -le $HOUTA ]] ; then
     FNSUB=$NMSUB
   else
     FNSUB=""
   fi
   if [ $DOIAU = YES ]; then
     if [ 10#$FH -lt 10#6 ]; then
       FHIAU=$((10#6-10#$FH))
       FHIAU=m$FHIAU
     else
       FHIAU=$((10#$FH-10#6))
       [[ $FHIAU -lt 10 ]]&&FHIAU=0$FHIAU
     fi
   else
     FHIAU=$FH
   fi
   eval rm -f ${LOGO}${FNSUB}
   if [ $FHOUT_HF -ne $FHOUT -a $FH -lt $FHMAX_HF ] ; then
     ((FH=10#$FH+10#$FHOUT_HF))
   else
     ((FH=10#$FH+10#$FHOUT))
   fi
   [[ $FH -lt 10 ]]&&FH=0$FH
done
if [[ $FILESTYLE = "L" ]] ; then
   #ln -fs $CO2CON fort.15
   #ln -fs $MTNVAR fort.24
   #ln -fs $O3FORC fort.28
   #ln -fs $O3CLIM fort.48

   ${NCP} $CO2CON fort.15
   ${NCP} $MTNVAR fort.24
   ${NCP} $O3FORC fort.28
   ${NCP} $O3CLIM fort.48
else
  echo 'FILESTYLE' $FILESTYLE 'NOT SUPPORTED'
  exit 222
fi

#for m in 01 02 03 04 05 06 07 08 09 10 11 12
#do
# ln -fs $AERODIR/global_aeropac3a.m$m.txt aeropac3a.m$m
#done

AEROSOL_FILE=${AEROSOL_FILE:-global_climaeropac_global.txt}
EMMISSIVITY_FILE=${EMMISSIVITY_FILE:-global_sfc_emissivity_idx.txt}

#ln -fs $AERODIR/$AEROSOL_FILE     aerosol.dat
#ln -fs $EMISDIR/$EMMISSIVITY_FILE sfc_emissivity_idx.txt
#ln -fs $OROGRAPHY                 orography
#ln -fs $OROGRAPHY_UF              orography_uf
#ln -fs $LONSPERLAT                lonsperlat.dat
#ln -fs $LONSPERLAR                lonsperlar.dat
${NCP} $AERODIR/$AEROSOL_FILE     aerosol.dat
${NCP} $EMISDIR/$EMMISSIVITY_FILE sfc_emissivity_idx.txt
${NCP} $OROGRAPHY                 orography
${NCP} $OROGRAPHY_UF              orography_uf
${NCP} $LONSPERLAT                lonsperlat.dat
${NCP} $LONSPERLAR                lonsperlar.dat

if [ $NEMS = .true. ] ; then
if [ $IEMS -gt 0 ] ; then
 EMMISSIVITY_FILE=${EMMISSIVITY_FILE:-global_sfc_emissivity_idx.txt}
 #ln -fs $EMISDIR/$EMMISSIVITY_FILE sfc_emissivity_idx.txt
  ${NCP} $EMISDIR/$EMMISSIVITY_FILE sfc_emissivity_idx.txt
fi
if [ $ISOL -gt 0 ] ; then
 cd $SOLCDIR
 for file in `ls | grep solarconstant` ; do
  ${NCP} $file $DATA/$(echo $file |sed -e "s/global_//g")
 done
fi
if [ $IAER -gt 0 ] ; then
 cd $VOLCDIR
 for file in `ls | grep volcanic_aerosols` ; do
  ${NCP:-cp} $file $DATA/$(echo $file |sed -e "s/global_//g")
 done
 cd $DATA
 #${NCP:-cp} $GOCART_CLIM/* $DATA
 ${NCP:-cp} $GOCART_LUTS/NCEP_AEROSOL.bin $DATA
fi
if [ $ICO2 -gt 0 ] ; then
 cd $CO2DIR
 for file in `ls | grep co2historicaldata` ; do
  ${NCP:-cp} $file $DATA/$(echo $file |sed -e "s/global_//g")
 done
 CO2_seasonal_cycle=${CO2_seasonal_cycle:-global_co2monthlycyc1976_2006.txt}
 ${NCP} $CO2_seasonal_cycle $DATA/co2monthlycyc.txt
fi
fi
cd $DATA
export PHYVARS="IEMS=$IEMS,ISOL=$ISOL,IAER=$IAER,ICO2=$ICO2,$PHYVARS"

#
#     For one member case i.e. control
#     --------------------------------
mins=$((DELTIM/60))
secs=$((DELTIM-(DELTIM/60)*60))
[[ $mins -lt 10 ]] &&mins=0$mins
[[ $secs -lt 10 ]] &&secs=0$secs
export FHINI=$((FHINI+0))
export FHROT=$((FHROT+0))

FH=$((10#$FHINI))
[[ $FH -lt 10 ]]&&FH=0$FH
if [[ $FHINI -gt 0 ]] ; then
  if [ $FHOUT_HF -ne $FHOUT -a $FH -lt $FHMAX_HF ] ; then
    FH=$((10#$FHINI+10#$FHOUT_HF))
  else
    FH=$((10#$FHINI+10#$FHOUT))
  fi
  [[ $FH -lt 10 ]]&&FH=0$FH
fi
#        For Initial Conditions
#        ----------------------
if [ $FHINI -eq  $FHROT ]; then
  if [ $NEMSIO_IN = .true. ]; then
    ln -fs $GRDI  grid_ini
    ln -fs $SIGI  sig_ini
  else
    ln -fs $SIGI  sig_ini
  fi
  ln -fs $SFCI  sfc_ini
  ln -fs $NSTI  nst_ini
  ln -fs $PLASI IPE_State.apex.${CIPEDATE}.h5
  if [ $FHROT -gt 0 ] ; then
    export RESTART=.true.
    ln -fs $GRDI  grid_ini
    ln -fs $GRDI2 grid_ini2
    ln -fs $SIGI2 sig_ini2
    if [ $WAM_IPE_COUPLING = .true. ];then
      export RESTART_AND_COUPLED=.true.
      ln -fs $RSTR  WAM_IPE_RST_rd
    fi
  else
    export RESTART=.false.
  fi
else
  ln -fs $GRDI  grid_ini
  ln -fs $GRDI2 grid_ini2
  ln -fs $SIGI  sig_ini
  ln -fs $SIGI2 sig_ini2
  ln -fs $SFCI  sfc_ini
  ln -fs $NSTI  nst_ini
  ln -fs $PLASI IPE_State.apex.${CIPEDATE}.h5
  if [ $WAM_IPE_COUPLING = .true. ];then
    export RESTART_AND_COUPLED=.true.
    ln -fs $RSTR  WAM_IPE_RST_rd
  fi
  export RESTART=.true.
fi
#        For output
#        ----------
while [[ $NEMS = .true. ]] && [[ 10#$FH -le $FHMAX ]] ; do
  if [[ $FH -le $HOUTA ]] ; then
    FNSUB=$NMSUB
  else
    FNSUB=""
  fi
  if [ $DOIAU = YES ]; then
    if [ "10#$FH" -lt "10#6" ]; then
      FHIAU=$((10#6-10#$FH))
      FHIAU=m$FHIAU
    else
      FHIAU=$((10#$FH-10#6))
      [[ $FHIAU -lt 10 ]]&&FHIAU=0$FHIAU
    fi
  else
    FHIAU=$FH
  fi
  if [ $FH -eq 00 ] ; then
    SUF2=:${mins}:${secs}
  else
    SUF2=""
  fi
  eval ln -fs ${SIGO}$FNSUB SIG.F${FH}$SUF2
  eval ln -fs ${SFCO}$FNSUB SFC.F${FH}$SUF2
  eval ln -fs ${FLXO}$FNSUB FLX.F${FH}$SUF2
  eval ln -fs ${LOGO}$FNSUB LOG.F${FH}$SUF2
  eval ln -fs ${D3DO}$FNSUB D3D.F${FH}$SUF2
  eval ln -fs ${NSTO}$FNSUB NST.F${FH}$SUF2
  eval ln -fs ${AERO}$FNSUB AER.F${FH}$SUF2

  if [ $FHOUT_HF -ne $FHOUT -a $FH -lt $FHMAX_HF ] ; then
    ((FH=10#$FH+10#$FHOUT_HF))
  else
    ((FH=10#$FH+10#$FHOUT))
  fi
  [[ $FH -lt 10 ]]&&FH=0$FH

done
# IPE
if [[ $IPE = .true. ]] ; then
  export CIPEDATE=${CIPEDATE:-$CDATE${IPEMINUTES:-00}}
  STEPS=$(((10#$FHMAX-10#$FHINI)*60*60/IPEFREQ))
  STEP=1
  while [[ $STEP -le $STEPS ]] ; do
    TIMESTAMP=`$MDATE $((STEP*IPEFREQ/60)) $CIPEDATE`
    eval $NLN ${COMOUT}/${PLASO} ${PLASO}
    STEP=$((STEP+1))
  done
fi
if [[ $SWIO = .true. ]] ; then
  for iomodel in $SWIO_MODELS; do
    eval prefix=\$${iomodel}_PREFIX
    eval cadence=\$${iomodel}_CADENCE
    if [[ -n "$cadence" ]] ; then
      STEPS=$(((10#$FHMAX-10#$FHINI)*60*60/cadence))
      STEP=1
      while [ $STEP -le $STEPS ] ; do
        TIMESTAMP=`$MDATE $((STEP*cadence/60)) ${FDATE}00`
        $NLN ${COMOUT}/${prefix}.${TIMESTAMP:0:8}_${TIMESTAMP:8}00.nc ${DATA}/.
        STEP=$((STEP+1))
      done
    fi
  done
fi
eval ln -fs $FORT1051 fort.1051
eval ln -fs $GRDR1 GRDR1
eval ln -fs $GRDR2 GRDR2
eval ln -fs $SIGR1 SIGR1
eval ln -fs $SIGR2 SIGR2
eval ln -fs $SFCR  SFCR
eval ln -fs $NSTR  NSTR
eval ln -fs $RSTR  WAM_IPE_RST_wrt

# Create Configure file (i.e. .rc file) here
# PE$n are to be imported from outside.  If PE$n are not set from outside, the
# model would give equal processors for all ensembel members.
#
c=1
while [ $c -le $ENS_NUM ] ; do
 eval export PE$c=\${PE$c:-0}
 c=$((c+1))
done

export wgrib=${wgrib:-$NWPROD/util/exec/wgrib}

INI_YEAR=$(echo $FDATE   | cut -c1-4)
INI_MONTH=$(echo $FDATE  | cut -c5-6)
INI_DAY=$(echo $FDATE    | cut -c7-8)
INI_HOUR=$(echo $FDATE   | cut -c9-10)

export C_YEAR=$(echo $CDATE     | cut -c1-4)
export C_MONTH=$(echo $CDATE    | cut -c5-6)
export C_DAY=$(echo $CDATE      | cut -c7-8)
export C_HOUR=$(echo $CDATE     | cut -c9-10)

## copy configure files needed for NEMS GFS
${NCP} ${MAPL:-$PARM_NGAC/MAPL.rc}                    MAPL.rc
${NCP} ${CHEM_REGISTRY:-$PARM_NGAC/Chem_Registry.rc}  Chem_Registry.rc

## copy configure files and fixed files needed for GOCART
if [ $GOCART == 1 ] ; then
 ${NCP} ${CONFIG_DU:-$PARM_NGAC/DU_GridComp.rc}             DU_GridComp.rc
 ${NCP} ${CONFIG_SU:-$PARM_NGAC/SU_GridComp.rc}             SU_GridComp.rc
 ${NCP} ${CONFIG_OC:-$PARM_NGAC/OC_GridComp.rc}             OC_GridComp.rc
 ${NCP} ${CONFIG_OCx:-$PARM_NGAC/OC_GridComp---full.rc}     OC_GridComp---full.rc
 ${NCP} ${CONFIG_BC:-$PARM_NGAC/BC_GridComp.rc}             BC_GridComp.rc
 ${NCP} ${CONFIG_SS:-$PARM_NGAC/SS_GridComp.rc}             SS_GridComp.rc
 ${NCP} ${AOD_REGISTRY:-$PARM_NGAC/Aod-550nm_Registry.rc}   Aod_Registry.rc
#jw  ${NCP} ${AOD_REGISTRY:-$PARM_NGAC/Aod-550nm_Registry.rc}   $DATA/Aod-550nm_Registry.rc
 ${NCP} $PARM_NGAC/AEROSOL_LUTS.dat                         .

 ln -sf $FIX_NGAC  ngac_fix
fi


if [ $DOIAU = YES ]; then
  export DYNVARS=$DYNVARS$IAUVARS
  export PHYVARS=$PHYVARS$IAUVARS
  export RESTART=.false.
  export FHRES=3
  #export FHOUT=1 # ???
  export FHZER=3
  export IAU=.true.
  SWIO_IDATE=$($NDATE +6 $CDATE)0000
else
  export IAU=.false.
fi

SWIO_IDATE=${SWIO_IDATE:-${CDATE}0000}
SWIO_SDATE=${FDATE}0000
SWIO_EDATE=$($NDATE $((FHMAX-$FHROT)) $FDATE)0000

export CDUMP=${CDUMP:-"compset_run"}
export SWIO_IDATE=${SWIO_IDATE:0:8}_${SWIO_IDATE:8}
export SWIO_SDATE=${SWIO_SDATE:0:8}_${SWIO_SDATE:8}
export SWIO_EDATE=${SWIO_EDATE:0:8}_${SWIO_EDATE:8}


# Mostly IDEA-related stuff in this section
#--------------------------------------------------------------
if [ $IDEA = .true. ]; then
  ${NLN} $COMOUT/wam_fields_${CDATE}_${cycle}.nc $DATA/wam_fields.nc
  ${NLN} $COMOUT/input_parameters.${CDATE}.${cycle}.nc $DATA/input_parameters.nc

  export START_UT_SEC=$((10#$INI_HOUR*3600))
  export END_TIME=$((IPEFMAX+$START_UT_SEC))
  export MSIS_TIME_STEP=${MSIS_TIME_STEP:-900}
  if [ $INPUT_PARAMETERS = realtime ] ; then
    $BASE_NEMS/../scripts/interpolate_input_parameters/parse_realtime.py -s $($MDATE -$((36*60)) ${FDATE}00) \
                                                                         -d $((60*(36+ 10#$FHMAX - 10#$FHINI))) \
                                                                         -p $DCOM $REALTIME_DERIVE
  elif [ $INPUT_PARAMETERS = conops2 ] ; then
    start=$($MDATE -$((36*60)) ${FDATE}00)
    duration=$((2160+15))
    $BASE_NEMS/../scripts/interpolate_input_parameters/parse_realtime.py -s $start -d $duration -p $DCOM
    $BASE_NEMS/../scripts/interpolate_input_parameters/realtime_wrapper.py -e ${SWIO_EDATE:0:8}${SWIO_EDATE:9:4} -p $DCOM -d 15 &

  else
    # work from the database
    echo "$FIX_F107"   >> temp_fix
    echo "$FIX_KP"     >> temp_fix
    echo "$FIX_SWVEL"  >> temp_fix
    echo "$FIX_SWDEN"  >> temp_fix
    echo "$FIX_SWBY"   >> temp_fix
    echo "$FIX_SWBZ"   >> temp_fix
    echo "$FIX_GWATTS" >> temp_fix
    echo "$FIX_HPI"    >> temp_fix
    $BASE_NEMS/../scripts/interpolate_input_parameters/interpolate_input_parameters.py -d $((36+ 10#$FHMAX - 10#$FHINI)) \
                                                                                       -s $($NDATE -36 $FDATE) \
                                                                                       -p $PARAMETER_PATH \
                                                                                       -m $INPUT_PARAMETERS \
                                                                                       -f temp_fix $HISTORICAL_NEW_F107
    rm -rf temp_fix
    if [ ! -e input_parameters.nc ] ; then
       echo "failed, no f107 file" ; exit 1
    fi
  fi
  LEN_F107=`wc -l wam_input_f107_kp.txt | cut -d' ' -f 1`
  F107_KP_SIZE=$((LEN_F107-5))
  F107_KP_DATA_SIZE=$F107_KP_SIZE
  F107_KP_INTERVAL=60
  F107_KP_SKIP_SIZE=$((36*60*60/$F107_KP_INTERVAL))
  [[ $NEMS = .true. ]] && F107_KP_READ_IN_START=$((FHINI*60*60/$F107_KP_INTERVAL))
  export F107_KP_READ_IN_START=${F107_KP_READ_IN_START:-0}
  export f107_kp_size=$((F107_KP_SIZE+$FHINI*60*60/$F107_KP_INTERVAL))
  # global_idea fix files
  ${NLN} $FIX_IDEA/global_idea* .
  # RT_WAM .nc files
  ${NLN} $FIX_IDEA/*.nc .
  ${NLN} $IPE_IC_DIR/ionprof .
  ${NLN} $IPE_IC_DIR/tiros_spectra .

  # IPE section
  if [ $IPE = .true. ]; then
    [[ $NEMS = .false. ]] && export READ_APEX_NEUTRALS="F"
    export READ_APEX_NEUTRALS=${READ_APEX_NEUTRALS:-"T"}
    export mesh_fill=${mesh_fill:-"1"}
    export DYNAMO_EFIELD=${DYNAMO_EFIELD:-"T"}
    export COLFAC=${COLFAC:-1.3}
    export OFFSET1_DEG=${OFFSET1_DEG:-5.0}
    export OFFSET2_DEG=${OFFSET2_DEG:-20.0}
    export POTENTIAL_MODEL=${POTENTIAL_MODEL:-2}
    export HPEQ=${HPEQ:-0.0}
    export TRANSPORT_HIGHLAT_LP=${TRANSPORT_HIGHLAT_LP:-30}
    export PERP_TRANSPORT_MAX_LP=${PERP_TRANSPORT_MAX_LP:-151}
    export VERTICAL_WIND_LIMIT=${VERTICAL_WIND_LIMIT:-100.0}

    # IPE fix files
    #${NLN} $BASE_NEMS/../IPELIB/run/coeff* ${DATA}
    $NLN $IPEGRID ${DATA}/$IPEGRIDFILENAME
    ${NLN} $IPE_IC_DIR/wei96* ${DATA}
    ${NLN} $IPE_IC_DIR/*.dat ${DATA}
    ${NLN} $IPE_IC_DIR/*.bin ${DATA}

    # don't know what this is
    export FILE_IO_FORM="'grib' 'bin4' 'grib'"

    # used for ipe namelist
    export DOY=`date -d ${INI_MONTH}/${INI_DAY}/${INI_YEAR} +%j`


    $NLN $PARMDIR/GPTLnamelist .
    envsubst < $PARMDIR/IPE.inp > IPE.inp

  fi # IPE

fi # IDEA

if [[ $DATAPOLL = "YES" ]] ; then
  if [[ $WAM_IPE_COUPLING = .true. ]] ; then
    if [[ $SWIO = .true. ]] ; then
      NEMS_CONF=${NEMS_CONF:-$PARMDIR/nems.configure.WAM-IPE_DATAPOLL_io}
    else
      NEMS_CONF=${NEMS_CONF:-$PARMDIR/nems.configure.WAM-IPE_DATAPOLL}
    fi
  else # standaloneWAM
    if [[ $SWIO = .true. ]] ; then
      NEMS_CONF=${NEMS_CONF:-$PARMDIR/nems.configure.standaloneWAM_DATAPOLL_io}
    else
      NEMS_CONF=${NEMS_CONF:-$PARMDIR/nems.configure.standaloneWAM_DATAPOLL}
    fi
  fi
else
  if [[ $WAM_IPE_COUPLING = .true. ]] ; then
    if [[ $SWIO = .true. ]] ; then
      NEMS_CONF=${NEMS_CONF:-$PARMDIR/nems.configure.WAM-IPE_io}
    else
      NEMS_CONF=${NEMS_CONF:-$PARMDIR/nems.configure.WAM-IPE}
    fi
  else # standaloneWAM
    if [[ $SWIO = .true. ]] ; then
      NEMS_CONF=${NEMS_CONF:-$PARMDIR/nems.configure.standaloneWAM_io}
    else
      NEMS_CONF=${NEMS_CONF:-$PARMDIR/nems.configure.standaloneWAM}
    fi
  fi
fi

envsubst < $NEMS_CONF > $DATA/nems.configure

if [[ $NEMS = .true. ]] ; then
  export dyncore=${dyncore:-gfs}
  export atm_model=${atm_model:-gsm}
  export coupling_interval_fast_sec=${coupling_interval_fast_sec:-""}
  export liope=${liope:-".false."}

  $NLN $PARMDIR/med.rc .

  envsubst < $PARMDIR/atmos.configure > atmos.configure

  envsubst < $PARMDIR/atm_namelist.rc > atm_namelist.rc

  # addition import/export variables for stochastic physics
  export sppt_import=${sppt_import:-0}
  export sppt_export=${sppt_export:-0}
  export shum_import=${shum_import:-0}
  export shum_export=${shum_export:-0}
  export skeb_import=${skeb_import:-0}
  export skeb_export=${skeb_export:-0}
  export vc_import=${vc_import:-0}
  export vc_export=${vc_export:-0}

  cat atm_namelist.rc > dyn_namelist.rc
  envsubst < $PARMDIR/dyn_namelist.rc >> dyn_namelist.rc

  cat atm_namelist.rc > phy_namelist.rc
  envsubst < $PARMDIR/phy_namelist.rc >> phy_namelist.rc

  # additional namelist parameters for stochastic physics.  Default is off
  export SPPT=${SPPT:-"0.0,0.0,0.0,0.0,0.0"}
  export ISEED_SPPT=${ISEED_SPPT:-0}
  export SPPT_LOGIT=${SPPT_LOGIT:-.TRUE.}
  export SPPT_TAU=${SPPT_TAU:-"21600,2592500,25925000,7776000,31536000"}
  export SPPT_LSCALE=${SPPT_LSCALE:-"500000,1000000,2000000,2000000,2000000"}

  export SHUM=${SHUM:-"0.0, -999., -999., -999, -999"}
  export ISEED_SHUM=${ISEED_SHUM:-0}
  export SHUM_TAU=${SHUM_TAU:-"2.16E4, 1.728E5, 6.912E5, 7.776E6, 3.1536E7"}
  export SHUM_LSCALE=${SHUM_LSCALE:-"500.E3, 1000.E3, 2000.E3, 2000.E3, 2000.E3"}

  export SKEB=${SKEB:-"0.0, -999., -999., -999, -999"}
  export ISEED_SKEB=${ISEED_SKEB:-0}
  export SKEB_TAU=${SKEB_TAU:-"2.164E4, 1.728E5, 2.592E6, 7.776E6, 3.1536E7"}
  export SKEB_LSCALE=${SKEB_LSCALE:="1000.E3, 1000.E3, 2000.E3, 2000.E3, 2000.E3"}
  export SKEB_VFILT=${SKEB_VFILT:-40}
  export SKEB_DISS_SMOOTH=${SKEB_DISS_SMOOTH:-12}

  export VC=${VC:-0.0}
  export ISEED_VC=${ISEED_VC:-0}
  export VCAMP=${VCAMP:-"0.0, -999., -999., -999, -999"}
  export VC_TAU=${VC_TAU:-"4.32E4, 1.728E5, 2.592E6, 7.776E6, 3.1536E7"}
  export VC_LSCALE=${VC_LSCALE:-"1000.E3, 1000.E3, 2000.E3, 2000.E3, 2000.E3"}
  [[ $LEVR -gt $LEVS ]] && export LEVR=$LEVS

  # GSM/WAM namelists
  envsubst < $PARMDIR/atm_namelist > atm_namelist
  $NLN $PARMDIR/gwp_in .
  $NLN $PARMDIR/ion_in .
  $NLN $PARMDIR/solar_in .
  envsubst < $PARMDIR/wam_control_in > wam_control_in

  $NLN atm_namelist.rc ./model_configure

  # special IAU handling for surface analysis
  if [ $DOIAU = YES ]; then
    export CDATE_SFC=${CDATE_SFC:-$(echo idate|$SFCHDR ${SFCI}$FM)}
    export FHINI_SFC=${FHINI_SFC:-$(echo fhour|$SFCHDR ${SFCI}$FM)}
    eval $CHGSFCFHREXEC $SFCI $CDATE_SIG $FHINI
  fi
  # envsubst in the appropriate SWIO rc files
  if [[ $SWIO = .true. ]] ; then
    for iomodel in $SWIO_MODELS; do
      infile=`sed -n -e '/^'"$iomodel"'_attributes/,/ConfigFile/ p' nems.configure | tail -n 1 | sed 's/^[ \t]*//' | cut -d' ' -f3`
      envsubst < $PARMDIR/$infile > $infile
    done
  fi
fi # NEMS

module list
eval $FCSTENV $PGM $REDOUT$PGMOUT $REDERR$PGMERR

export ERR=$?
export err=$ERR
$ERRSCRIPT||exit 2

 if [ $DOIAU = YES ]; then
    eval $CHGSFCFHREXEC $SFCI $CDATE_SFC $FHINI_SFC
 fi

[[ -f $COMOUT/`eval echo "$PLASO"` ]] && eval ln -fs ${COMOUT}/${PLASO} $IPER

################################################################################
#  Postprocessing
cd $pwd
[[ $mkdata = YES ]]&&rmdir $DATA
$ENDSCRIPT

if [[ "$VERBOSE" = "YES" ]] ; then
   echo $(date) EXITING $0 with return code $err >&2
fi
return $err
