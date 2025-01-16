#!/bin/bash
### basically the idea is to just check if directories exist that are specific to certain machines

if [[ -e /lfs/h1 ]] ; then
    export FMID=wcoss2
    export MACHINE=wcoss2
    export BUILD_TARGET=wcoss2
elif [[ -e /xcatpost && -e /scratch1 && -e /scratch2 ]] ; then
    export FMID=hera
    export MACHINE=hera
elif [[ -e /glade ]] ; then
    export FMID=derecho
    export MACHINE=derecho
else
    # cannot ID machine
    echo "cannot identify current machine... check config/detect_machine"
    exit 1
fi
export BUILD_TARGET=${BUILD_TARGET:-$MACHINE.intel}

# now check if config file exists
if [ ! -e $CONFIGDIR/$FMID.config ] ; then
    echo "machine configuration file not found for FMID: $FMID"
    exit 2
fi
