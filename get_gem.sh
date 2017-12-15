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
    INTERVALS=("0 3 120" "126 6 168")
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

STEP=12
# Model Reference Time
RT=`date -u +%s -d '-3 hours'`
RT="$(( $RT / ($STEP * 3600) * ($STEP * 3600) ))"
RT_HOUR=`date -u -d@$RT +%H`
RT_DATE=`date -u -d@$RT +%Y%m%d`
RT_DATE_HH=`date -u -d@$RT +%Y%m%d%H`
RT_DATE_HHMM=`date -u -d@$RT +%Y%m%d%H%M`
RT_ISO=`date -u -d@$RT +%Y-%m-%dT%H:%M:%SZ`

if [ -d /smartmet ]; then
    BASE=/smartmet
else
    BASE=$HOME/smartmet
fi

OUT=$BASE/data/gem/$AREA
EDITOR=$BASE/editor/in
TMP=$BASE/tmp/data/gem_${AREA}_${RT_DATE_HHMM}
LOGFILE=$BASE/logs/data/gem_${AREA}_${RT_HOUR}.log

OUTNAME=${RT_DATE_HHMM}_gem_$AREA

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
    mkdir -p $EDITOR
fi

function log {
    echo "$(date -u +%H:%M:%S) $1"
}

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
        grib_count $1 &>/dev/null
        if [ $? = 0 ] && [ $(grib_count $1) -gt 0 ]; then
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

    STEPSTARTTIME=$(date +%s)
    step=$(printf '%03d' $1)
    FILE=CMC_glb_${GETPAR}_latlon.24x.24_${RT_DATE}${RT_HOUR}_P${step}.grib2

    if $(testFile ${TMP}/grb/${FILE}); then
        log "Cached file: $FILE size: $(stat --printf="%s" ${TMP}/grb/${FILE}) messages:: $(grib_count ${TMP}/grb/${FILE})"
        break;
    else
	while [ 1 ]; do
	    ((count=count+1))
	    log "Downloading (try: $count) ${FILE}"
	    URL=http://dd.weather.gc.ca/model_gem_global/25km/grib2/lat_lon/${RT_HOUR}/$step/${FILE}
	    STARTTIME=$(date +%s)
	    curl -s -S -o $TMP/grb/${FILE} $URL
            ENDTIME=$(date +%s)
            if $(testFile ${TMP}/grb/${FILE}); then
                log "Downloaded file: $FILE size: $(stat --printf="%s" ${TMP}/grb/${FIL\
E}) messages: $(grib_count ${TMP}/grb/${FILE}) time: $(($ENDTIME - $STARTTIME))s wait: $((($ENDTIME - $STEPSTARTTIME) - ($ENDTIME - $STEPSTARTTIME)))s"
                if [ -n "$GRIB_COPY_DEST" ]; then
                    rsync -ra ${TMP}/grb/${FILE} $GRIB_COPY_DEST/$RT_DATE_HH/
                fi
                break;
            fi

	    if [ $count = 60 ]; then break; fi; # break if max count
	    sleep 60
	done
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

if [ -n "$GRIB_COPY_DEST" ]; then
    ls -1 $TMP/grb/ > $TMP/${RT_DATE_HH}.txt
    rsync -a $TMP/${RT_DATE_HH}.txt $GRIB_COPY_DEST/
fi

log ""
log "Download size $(du -hs $TMP/grb/|cut -f1) and $(ls -1 $TMP/grb/|wc -l) files."

log "Converting grib files to qd files..."
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
log "Creating Wind and Weather objects: ${OUTNAME}_pressure.sqd"
qdversionchange -w 0 7 < $TMP/${OUTNAME}_pressure.sqd.tmp > $TMP/${OUTNAME}_pressure.sqd
log "Creating Wind and Weather objects: ${OUTNAME}_surface.sqd"
qdversionchange -a 7 < $TMP/${OUTNAME}_surface.sqd.tmp > $TMP/${OUTNAME}_surface.sqd

#
# Copy files to SmartMet Workstation and SmartMet Production directories
#
# Pressure level
if [ -s $TMP/${OUTNAME}_pressure.sqd ]; then
    log "Testing ${OUTNAME}_pressure.sqd"
    if qdstat $TMP/${OUTNAME}_pressure.sqd; then
        log  "Compressing ${OUTNAME}_pressure.sqd"
        lbzip2 -k $TMP/${OUTNAME}_pressure.sqd
        log "Moving ${OUTNAME}_pressure.sqd to $OUT/pressure/querydata/"
        mv -f $TMP/${OUTNAME}_pressure.sqd $OUT/pressure/querydata/
        log "Moving ${OUTNAME}_pressure.sqd.bz2 to $EDITOR/"
        mv -f $TMP/${OUTNAME}_pressure.sqd.bz2 $EDITOR/
    else
        log "File $TMP/${OUTNAME}_pressure.sqd is not valid qd file."
    fi
fi

# Surface
if [ -s $TMP/${OUTNAME}_surface.sqd ]; then
    log "Testing ${OUTNAME}_surface.sqd"
    if qdstat $TMP/${OUTNAME}_surface.sqd; then
        log "Compressing ${OUTNAME}_surface.sqd"
        lbzip2 -k $TMP/${OUTNAME}_surface.sqd
        log "Moving ${OUTNAME}_surface.sqd to $OUT/surface/querydata/"
        mv -f $TMP/${OUTNAME}_surface.sqd $OUT/surface/querydata/
        log "Moving ${OUTNAME}_surface.sqd.bz2 to $EDITOR"
        mv -f $TMP/${OUTNAME}_surface.sqd.bz2 $EDITOR/
    else
        log "File $TMP/${OUTNAME}_surface.sqd is not valid qd file."
    fi
fi

rm -f $TMP/*.txt
rm -f $TMP/*_gem_*
rm -f $TMP/grb/CMC*
rmdir $TMP/grb
rmdir $TMP

