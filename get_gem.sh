#!/bin/sh
#
# Finnish Meteorological Institute / Mikko Rauhala (2015-2017)
#
# SmartMet Data Ingestion Module for GEN Model
#

# Load Configuration
if [ -s /smartmet/cnf/data/gem.cnf ]; then
    . /smartmet/cnf/data/gem.cnf
fi

if [ -s gem.cnf ]; then
    . gem.cnf
fi

# Setup defaults for the configuration

if [ -z "$AREA" ]; then
    AREA=world
fi

if [ -z "$TOP" ]; then
    TOP=90
fi

if [ -z "$BOTTOM" ]; then
    BOTTOM=-90
fi

if [ -z "$LEFT" ]; then
    LEFT=0
fi

if [ -z "$RIGHT" ]; then
    RIGHT=360
fi

if [ -z "$INTERVALS" ]; then
    INTERVALS=("0 3 126" "132 6 192")
fi

while getopts  "a:b:di:l:r:t:" flag
do
  case "$flag" in
        a) AREA=$OPTARG;;
        d) DRYRUN=1;;
        i) INTERVALS=("$OPTARG");;
        l) LEFT=$OPTARG;;
        r) RIGHT=$OPTARG;;
        t) TOP=$OPTARG;;
        b) BOTTOM=$OPTARG;;
  esac
done

STEP=6
# Model Reference Time
RT=`date -u +%s -d '-3 hours'`
RT="$(( $RT / ($STEP * 3600) * ($STEP * 3600) ))"
RT_HOUR=`date -u -d@$RT +%H`
RT_DATE_HH=`date -u -d@$RT +%Y%m%d%H`
RT_DATE_HHMM=`date -u -d@$RT +%Y%m%d%H%M`
RT_ISO=`date -u -d@$RT +%Y-%m-%dT%H:%M:%SZ`

if [ -d /smartmet ]; then
    OUT=/smartmet/data/gem/$AREA
    DICTIONARY=/smartmet/cnf/dictionary_en.conf
    EDITOR=/smartmet/editor/in
    TMP=/smartmet/tmp/data/gem_${AREA}_${RT_DATE_HHMM}
    LOGFILE=/smartmet/logs/data/gem${RT_HOUR}.log
else
    OUT=$HOME/data/gem/$AREA
    DICTIONARY=/smartmet/cnf/dictionary_en.conf
    EDITOR=/smartmet/editor/in
    TMP=/tmp/gem_${AREA}_${RT_DATE_HHMM}
    LOGFILE=/smartmet/logs/data/gem${RT_HOUR}.log
fi

OUTNAME=${RT_DATE_HHMM}_gem_$AREA

UTCHOUR=`date -u +%H -d '-4 hours'`
RUN=`expr $UTCHOUR / 12 \* 12`
RUN=`printf %02d $RUN`
DATE=`date -u +%Y%m%d${RUN}00 -d '-4 hours'`
RUNDATE=`date -u +%Y%m%d -d '-4 hours'`

# Use log file if not run interactively
if [ $TERM = "dumb" ]; then
    exec &> $LOGFILE
fi

echo "Model Reference Time: $RT_ISO"
echo "Area: $AREA left:$LEFT right:$RIGHT top:$TOP bottom:$BOTTOM"
echo -n "Interval(s): "
for l in "${INTERVALS[@]}"
do
    echo -n "$l "
done
echo ""
echo "Temporary directory: $TMP"
echo "Output directory: $OUT"
echo "Output surface level file: ${OUTNAME}_surface.sqd"
echo "Output pressure level file: ${OUTNAME}_pressure.sqd"

VARS="PRATE_SFC_0 TMP_TGL_2 DPT_TGL_2 PRMSL_MSL_0 UGRD_TGL_10 VGRD_TGL_10 TCDC_SFC_0 SNOD_SFC_0 PRES_SFC_0 CWAT_EATM_0 VVEL_ISBL_250 VVEL_ISBL_500 VVEL_ISBL_700 VVEL_ISBL_850"
LVLVARS="TMP_ISBL HGT_ISBL UGRD_ISBL VGRD_ISBL DEPR_ISBL SPFH_ISBL"
LEVELS="1015 1000 985 970 950 925 900 875 850 800 750 700 650 600 550 500 450 400 350 300 275 250 225 200 175 150 100 50"

if [ -z "$DRYRUN" ]; then
    mkdir -p $TMP/grb
    mkdir -p $OUT/{surface,pressure}/querydata
fi

function runBacground()
{
    downloadStep $1 &
    ((dnum=dnum+1))
    if [ $(($dnum % 10)) == 0 ]; then
	wait
    fi
}

function testFile()
{
    if [ -s $1 ]; then
    # check return value, break if successful (0)
    gdalinfo $1 &>/dev/null
        if [ $? = 0 ]; then
            return 0
    else
            rm -f $1
            return 1
        fi
    else
        return 1
    fi
}

function downloadStep()
{

    if [ $1 = 0 ] && [ $GETPAR = "PRATE_SFC_0" ] ; then break; fi; 

    TEPSTARTTIME=$(date +%s)
    step=$(printf '%03d' $1)
    FILE=CMC_glb_${GETPAR}_latlon.24x.24_${RUNDATE}${RUN}_P${step}.grib2

    if [ ! -s $TMP/grb/${FILE} ]; then

	while [ 1 ]; do
	    ((count=count+1))
	    echo "Downloading (try: $count) ${FILE}"
	    URL=http://dd.weather.gc.ca/model_gem_global/25km/grib2/lat_lon/$RUN/$step/${FILE}
	    /usr/bin/time -f "Downloaded (in %e s) $FILE" wget --no-verbose --retry-connrefused --read-timeout=30 --tries=20 -O $TMP/grb/.${FILE} "http://dd.weather.gc.ca/model_gem_global/25km/grib2/lat_lon/$RUN/$step/${FILE}"
	    if [ $? = 0 ]; then break; fi; # check return value, break if successful (0)
	    if [ $count = 60 ]; then break; fi; # break if max count
	    sleep 60
	done
	mv -f $TMP/grb/.${FILE} $TMP/grb/${FILE}
    else
	echo Cached $TMP/grb/${FILE}
    fi 
}

# Download first leg 
for i in $(seq $LEG1_START $LEG1_STEP $LEG1_END)
do
    for LVL in $LEVELS
    do
	for VAR in $LVLVARS
	do
	    GETPAR=${VAR}_${LVL}
	    runBacground $i
	done
    done
    for VAR in $VARS
    do
	GETPAR=${VAR}
	runBacground $i
    done
done

# Download second leg
for i in $(seq $LEG2_START $LEG2_STEP $LEG2_END)
do
    for LVL in $LEVELS
    do
	for VAR in $LVLVARS
	do
	    GETPAR=${VAR}_${LVL}
	    runBacground $i
	done
    done
    for VAR in $VARS
    do
	GETPAR=${VAR}
	runBacground $i
    done
done

echo "Converting grib files to qd files..."
gribtoqd $GRIBTOQD_ARGS -r 12 -n -t -G $LEFT,$BOTTOM,$RIGHT,$TOP -p "47,GEM Surface,GEM Pressure" -o $TMP/$OUTNAME.sqd $TMP/grb/
mv -f $TMP/$OUTNAME.sqd_levelType_1 $TMP/${OUTNAME}_surface.sqd
mv -f $TMP/$OUTNAME.sqd_levelType_100 $TMP/${OUTNAME}_pressure.sqd

#
# Post process some parameters 
#
echo -n "Calculating parameters: pressure..."
cp -f $TMP/${OUTNAME}_pressure.sqd $TMP/${OUTNAME}_pressure.sqd.tmp
echo -n "surface..."
cp -f $TMP/${OUTNAME}_surface.sqd $TMP/${OUTNAME}_surface.sqd.tmp
echo "done"

#
# Create querydata totalWind and WeatherAndCloudiness objects
#
echo -n "Creating Wind and Weather objects: pressure..."
qdversionchange -w 0 7 < $TMP/${OUTNAME}_pressure.sqd.tmp > $TMP/${OUTNAME}_pressure.sqd
echo -n "surface..."
qdversionchange -a 7 < $TMP/${OUTNAME}_surface.sqd.tmp > $TMP/${OUTNAME}_surface.sqd
echo "done"

#
# Copy files to SmartMet Workstation and SmartMet Production directories
# Bzipping the output file is disabled until all countries get new SmartMet version
# Pressure level
if [ -s $TMP/${OUTNAME}_pressure.sqd ]; then
echo -n "Compressing pressure data..."
bzip2 -k $TMP/${OUTNAME}_pressure.sqd
echo "done"
echo -n "Copying file to SmartMet Workstation..."
mv -f $TMP/${OUTNAME}_pressure.sqd $OUT/pressure/querydata/${OUTNAME}_pressure.sqd
mv -f $TMP/${OUTNAME}_pressure.sqd.bz2 $EDITOR/
echo "done"
fi

# Surface
if [ -s $TMP/${OUTNAME}_surface.sqd ]; then
echo -n "Compressing surface data..."
bzip2 -k $TMP/${OUTNAME}_surface.sqd
echo "done"
echo -n "Copying file to SmartMet Production..."
mv -f $TMP/${OUTNAME}_surface.sqd $OUT/surface/querydata/${OUTNAME}_surface.sqd
mv -f $TMP/${OUTNAME}_surface.sqd.bz2 $EDITOR/
echo "done"
fi

rm -f $TMP/*_gem_*
rm -f $TMP/grb/CMC*
rmdir $TMP/grb
rmdir $TMP

echo "Created files: ${OUTNAME}_surface.sqd and ${OUTNAME}_surface.sqd"
