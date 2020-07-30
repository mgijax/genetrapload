#!/bin/sh 
#
#  genetrapload.sh
###########################################################################
#
#  Purpose:  This script controls the execution of the Gene Trap Load
#
#  Usage:
#
#      genetrapload.sh [ -a ]
#
#          where -a means to exclude the ALO Marker load
#
#  Env Vars:
#
#      See the configuration file
#
#  Inputs:
#
#      - Common configuration file -
#		/usr/local/mgi/live/mgiconfig/master.config.sh
#      - Gene Trap load configuration file - genetrapload.config
#      - One or more GenBank input files 
#
#  Outputs:
#
#      - An archive file
#      - Log files defined by the environment variables ${LOG_PROC},
#        ${LOG_DIAG}, ${LOG_CUR} and ${LOG_VAL}
#      - BCP files for for inserts to each database table to be loaded
#      - SQL script file for updates
#      - Records written to the database tables
#      - Exceptions written to standard error
#      - Configuration and initialization errors are written to a log file
#        for the shell script
#
#  Exit Codes:
#
#      0:  Successful completion
#      1:  Fatal error occurred
#      2:  Non-fatal error occurred
#
#  Assumes:  Nothing
#
#  Implementation:  
#
#  Notes:  None
#
###########################################################################

#
#  Set up a log file for the shell script in case there is an error
#  during configuration and initialization.
#
cd `dirname $0`/..
LOG=`pwd`/genetrapload.log
rm -f ${LOG}

RUN_ALOMARKER=yes

#
#  Verify the argument(s) to the shell script.
#
if [ $# -gt 0 ]
then
    if [ $# -eq 1 -a "$1" = "-a" ]
    then
        RUN_ALOMARKER=no
    else
        echo "Usage: $0 [ -a ]" | tee -a ${LOG}
        exit 1
    fi
fi

#
#  Establish the configuration file name.
#
CONFIG_LOAD=`pwd`/genetrapload.config
#
#  Make sure the configuration file is readable.
#
if [ ! -r ${CONFIG_LOAD} ]
then
    echo "Cannot read configuration file: ${CONFIG_LOAD}" | tee -a ${LOG}
    exit 1
fi

#
# source config file
#
echo "Sourcing config file"

. ${CONFIG_LOAD}
#
#  Make sure the master configuration file is readable
#

if [ ! -r ${CONFIG_MASTER} ]
then
    echo "Cannot read configuration file: ${CONFIG_MASTER}"
    exit 1
fi

echo "javaruntime:${JAVARUNTIMEOPTS}"
echo "classpath:${CLASSPATH}"
echo "dbserver:${MGD_DBSERVER}"
echo "database:${MGD_DBNAME}"

#
#  Source the DLA library functions.
#
if [ "${DLAJOBSTREAMFUNC}" != "" ]
then
    if [ -r ${DLAJOBSTREAMFUNC} ]
    then
	. ${DLAJOBSTREAMFUNC}
    else
	echo "Cannot source DLA functions script: ${DLAJOBSTREAMFUNC}"
	exit 1
    fi
else
    echo "Environment variable DLAJOBSTREAMFUNC has not been defined."
    exit 1
fi

#
# if true first time logging unresolved files
#
FIRST_UNRESOLVED=true

#
# Function that runs to java load
#

runALOLoad ()
{
    #
    # log time and input files to process
    #
    echo "\n`date`" | tee -a ${LOG_PROC} ${LOG_DIAG}
    echo "Files read from stdin: ${APP_CAT_METHOD} ${APP_INFILES}" \
	| tee -a ${LOG_DIAG} ${LOG_PROC}

    # drop cell line update trigger if configured to do so
    if [ ${UPDATE_MCLDERIVATION} = true ]
    then
	${MGD_DBSCHEMADIR}/trigger/ALL_CellLine_drop.object | tee -a ${LOG_DIAG}
    fi

    #
    # run genetrapload
    # -Xrunhprof:cpu=samples,depth=6
    # -Xrunhprof:cpu=times
    # /net/balin/export/netbeans-5.0/nb5.0/modules/profiler-ea-vm/bin/java 
    ${APP_CAT_METHOD}  ${APP_INFILES}  | \
	${JAVA} \
	${JAVARUNTIMEOPTS} \
	-classpath ${CLASSPATH} \
	-DSINGLE_HITS_ALL=${SINGLE_HITS_ALL} \
	-DBEST_HITS_ALL=${BEST_HITS_ALL} \
	-DCONFIG=${CONFIG_MASTER},${CONFIG_LOAD} \
	-DJOBKEY=${JOBKEY} ${DLA_START}
    STAT=$?

    # re-create cell line update trigger if configured to do so
    if [ ${UPDATE_MCLDERIVATION} = true ]
    then
	${MGD_DBSCHEMADIR}/trigger/ALL_CellLine_create.object | \
		tee -a ${LOG_DIAG}
    fi

    # created triggers prior to checking status, if genetrapload fails we want
    # the triggers on the table 
    checkStatus ${STAT} "Gene Trap ALO Load"

    # check if file exists  and is > size 0
    if [ -s "${UNRESOLVED_FILE_NAME}" ]
    then
        logUnresolvedFiles
	STAT=$?
	checkStatus ${STAT} "Log Unresolved Files in radar"
    fi
}

#
# Function that runs the ALO Marker association load
#
runMarkerAssocLoad()
{
    echo "\n`date`" | tee -a ${LOG_PROC} ${LOG_DIAG}
    echo "Running ALO Marker Association Load" | tee -a ${LOG_PROC} ${LOG_DIAG}
    ${ALOMRKLOAD}/bin/alomrkload.sh
    STAT=$?
    checkStatus ${STAT} "ALO Marker Association Load"

}

#
# Function that logs the unresolved file in RADAR
#

logUnresolvedFiles()
{

    #    
    # create a new, unique file name for the unresolved sequences
    #
    echo "Creating unique unresolved file name" | tee -a ${LOG_PROC} ${LOG_DIAG}
    if [ ! -f ${FILECOUNTER} ]
    then
	fileCounter=1
	echo ${fileCounter} > ${FILECOUNTER}
    else
	fileCounter=`cat ${FILECOUNTER}`
	fileCounter=`expr ${fileCounter} + 1`
	echo ${fileCounter} > ${FILECOUNTER}
    fi

    #
    # move the original file name to the new file name
    #
    echo "Moving ${UNRESOLVED_FILE_NAME} to \
	${UNRESOLVED_FILE_NAME}.${fileCounter}"
    mv ${UNRESOLVED_FILE_NAME} ${UNRESOLVED_FILE_NAME}.${fileCounter}

    #
    # reset the variable value
    #
    UNRESOLVED_FILE_NAME=${UNRESOLVED_FILE_NAME}.${fileCounter}
    echo "UNRESOLVED_FILE_NAME = ${UNRESOLVED_FILE_NAME}"

    #
    # log the file in radar in the DOWNLOADDIR
    #
    echo "Logging the unresolved file in RADAR" | tee -a ${LOG_PROC} ${LOG_DIAG}
    ${RADAR_DBUTILS}/bin/logFileToProcess.csh ${RADAR_DBSCHEMADIR} \
	${UNRESOLVED_FILE_NAME} ${DOWNLOADDIR} ${LOAD_FILETYPE}
    STAT=$?
    checkStatus ${STAT} "logFileToProcess.csh ${LOAD_FILETYPE} for unresolved file"

    #
    # move file from ${OUTPUTDIR} (under /data/loads) to ${DOWNLOADDIR}
    # under /data/downloads so the downstream processes can find them
    #
    mv -f ${UNRESOLVED_FILE_NAME} ${DOWNLOADDIR}

    #
    # log single and best the first time only
    #
    echo "FIRST_UNRESOLVED:  ${FIRST_UNRESOLVED}" | tee -a ${LOG_DIAG}
    if [ ${FIRST_UNRESOLVED} = true ] 
    then
	# we need original files in output dir in case there are repeats
	# to process. 11/3/09 changed from mv to cp 
	echo  "Copying  ${BEST_HITS_ALL} to ${BEST_HITS_ALL}.${fileCounter}" \
	    | tee -a ${LOG_DIAG}
	cp ${BEST_HITS_ALL} ${BEST_HITS_ALL}.${fileCounter}
	echo "Moving ${SINGLE_HITS_ALL} to ${SINGLE_HITS_ALL}.${fileCounter}" \
	    | tee -a ${LOG_DIAG}
	cp ${SINGLE_HITS_ALL} ${SINGLE_HITS_ALL}.${fileCounter}

	#
	# reset the variable values
	# 11/3/09 don't do this, add ".${fileCounter}" to variable name when 
	# logging in radar and moving to DOWNLOADDIR below. 
	#BEST_HITS_ALL=${BEST_HITS_ALL}.${fileCounter}
	#SINGLE_HITS_ALL=${SINGLE_HITS_ALL}.${fileCounter}
	
	echo "Logging the best hits file ${BEST_HITS_ALL} in RADAR" | \
	    tee -a ${LOG_PROC} ${LOG_DIAG}
	${RADAR_DBUTILS}/bin/logFileToProcess.csh ${RADAR_DBSCHEMADIR} \
	    ${BEST_HITS_ALL}.${fileCounter} ${DOWNLOADDIR} ${BEST_HITS_FILETYPE}
	STAT=$?
	checkStatus ${STAT} "logFileToProcess.csh ${BEST_HITS_FILETYPE} for unresolved file"

	echo "Logging the single hits file ${SINGLE_HITS_ALL} in RADAR" | \
	    tee -a ${LOG_PROC} ${LOG_DIAG}
        ${RADAR_DBUTILS}/bin/logFileToProcess.csh ${RADAR_DBSCHEMADIR} \
	    ${SINGLE_HITS_ALL}.${fileCounter} ${DOWNLOADDIR} ${SINGLE_HITS_FILETYPE}
        STAT=$?
        checkStatus ${STAT} "logFileToProcess.csh ${SINGLE_HITS_FILETYPE} for unresolved file"

	#
        # move file best and single hits files from ${OUTPUTDIR}
        # (under /data/loads) to ${DOWNLOADDIR} under /data/downloads
        # so the downstream processes can find them
        #
        mv -f ${BEST_HITS_ALL}.${fileCounter} ${DOWNLOADDIR}
        mv -f ${SINGLE_HITS_ALL}.${fileCounter} ${DOWNLOADDIR}

	FIRST_UNRESOLVED=false
    fi
}
##################################################################
##################################################################
#
# main
#
##################################################################
##################################################################
#
# createArchive including OUTPUTDIR, startLog, getConfigEnv, get job key
#
preload ${OUTPUTDIR}

#
# rm all files/dirs from OUTPUTDIR RPTDIR
#
cleanDir ${OUTPUTDIR} ${RPTDIR}

# if we are processing the non-cums (incremental mode)
# get a set of files, 1 file or set < configured value in MB (compressed)

echo "checking APP_RADAR_INPUT: ${APP_RADAR_INPUT}"

if [ ${APP_RADAR_INPUT} = true ]
then
    echo 'Getting files to Process' | tee -a ${LOG_DIAG}
    # set the input files to empty string
    APP_INFILES=""
    APP_INFILE_BEST_HITS=""
    APP_INFILE_SINGLE_HITS=""

    # get load input files 
    APP_INFILES=`${RADAR_DBUTILS}/bin/getFilesToProcess.csh \
	${RADAR_DBSCHEMADIR} ${JOBSTREAM} ${LOAD_FILETYPE}`
    STAT=$?
    checkStatus ${STAT} "getFilesToProcess.csh ${LOAD_FILETYPE}"
    echo "APP_INFILES=${APP_INFILES}"

    # if no input files report and shutdown gracefully
    if [ "${APP_INFILES}" = "" ]
    then
	echo "No files to process" | tee -a ${LOG_DIAG} ${LOG_PROC}
	# but we still want to run the marker assoc load
        if [ $RUN_ALOMARKER = yes ]
        then
	    runMarkerAssocLoad
	    shutDown
	    exit 0
        fi
    fi
   
    # get best hits input files
    APP_INFILE_BEST_HITS=`${RADAR_DBUTILS}/bin/getFilesToProcess.csh \
        ${RADAR_DBSCHEMADIR} ${JOBSTREAM} ${BEST_HITS_FILETYPE}`
    STAT=$?
    checkStatus ${STAT} "getFilesToProcess.csh ${BEST_HITS_FILETYPE}"
    echo "APP_INFILE_BEST_HITS=${APP_INFILE_BEST_HITS}"

    # get single hits input files
    APP_INFILE_SINGLE_HITS=`${RADAR_DBUTILS}/bin/getFilesToProcess.csh \
        ${RADAR_DBSCHEMADIR} ${JOBSTREAM} ${SINGLE_HITS_FILETYPE}`
    STAT=$?
    checkStatus ${STAT} "getFilesToProcess.csh ${SINGLE_HITS_FILETYPE}"
    echo "APP_INFILE_SINGLE_HITS=${APP_INFILE_SINGLE_HITS}"
    echo 'Done getting files to Process' | tee -a ${LOG_DIAG}

fi

# create a single file from the 0..n single hits files from radar
SINGLE_HITS_ALL=${OUTPUTDIR}/single_hits.all
echo "single hits all ${SINGLE_HITS_ALL}"
# there may not be a single hits file, i.e. small set of sequences blatted
if [ "${APP_INFILE_SINGLE_HITS}" != "" ]
then
    /usr/local/bin/cat ${APP_INFILE_SINGLE_HITS} > ${SINGLE_HITS_ALL}
else
    # here it's easier to have empty file than detecting non-existent file
    # in the java code that reads this file
    touch ${SINGLE_HITS_ALL}
fi

# create a single file from the 0..n best hits files from radar
BEST_HITS_ALL=${OUTPUTDIR}/best_hits.all
echo "best hits all ${BEST_HITS_ALL}"
# may not be a best hits file i.e. small set of sequences blatted and
# no best hits file
if [ "${APP_INFILE_BEST_HITS}" != "" ]
then
    /usr/local/bin/cat ${APP_INFILE_BEST_HITS} > ${BEST_HITS_ALL}
else
    touch  ${BEST_HITS_ALL}
fi

# save APP_INFILES to new variable, when repeats are processed APP_INFILES 
# is reset. Use FILES_PROCESSED to log processed files
FILES_PROCESSED=${APP_INFILES}

# if we get here then APP_INFILES not set in configuration this is an error
if [ "${APP_INFILES}" = "" ]
then
    # set STAT for endJobStream.py called from postload in shutDown
    STAT=1
    checkStatus ${STAT} "APP_RADAR_INPUT=${APP_RADAR_INPUT}. \
	Check that APP_INFILES has been configured."

fi

#
# run the ALO load
#

#
# truncate the sequences processed file
#
if [ -f ${SEQUENCES_PROCESSED} ]
then
    echo "Truncating: " % ${SEQUENCES_PROCESSED}
    rm ${SEQUENCES_PROCESSED}
    touch ${SEQUENCES_PROCESSED}
fi

#
# run gene trap ALO Loader
#
runALOLoad

#
# Update sequences processed to active status if needed
# Note: do this only once as all sequences processed the first time
# are written to the SEQUENCES_PROCESSED file which this script reads
#

echo "Updating deleted sequences to ACTIVE status" | \
    tee -a ${LOG_PROC} ${LOG_DIAG}
${GENETRAPLOAD}/bin/updateGeneTrapSeqStatus.py
STAT=$?
checkStatus ${STAT} "Updating Deleted Sequences"

#
# run any repeat files if configured to do so
#
ctr=1
echo "APP_PROCESS_REPEATS=${APP_PROCESS_REPEATS}" | tee -a ${LOG_DIAG}
if [ ${APP_PROCESS_REPEATS} = true ]
then
    while [ -s ${REPEAT_FILE_NAME} ]
    # while repeat file exists and is not length 0
    do
	# rename the repeat file
	mv ${REPEAT_FILE_NAME} ${APP_REPEAT_TO_PROCESS}

	# set the cat method
	APP_CAT_METHOD=/usr/bin/cat

	# set the input file name
	APP_INFILES=${APP_REPEAT_TO_PROCESS}
        
	# run the load
	runALOLoad

	echo "saving repeat file ${APP_REPEAT_TO_PROCESS}.${ctr}"
	mv ${APP_REPEAT_TO_PROCESS} ${APP_REPEAT_TO_PROCESS}.${ctr}
        ctr=`expr ${ctr} + 1`
    done

fi

# if input was from radar log the files we processed 
if [ ${APP_RADAR_INPUT} = true ]
then
    echo "Logging processed files" >> ${LOG_DIAG}
    for file in ${FILES_PROCESSED}
    do
	${RADAR_DBUTILS}/bin/logProcessedFile.csh ${RADAR_DBSCHEMADIR} \
	    ${JOBKEY} ${file} ${LOAD_FILETYPE}
	STAT=$?
	checkStatus ${STAT} "logProcessedFile.csh ${file}"
    done
 
    for file in ${APP_INFILE_BEST_HITS}   
    do
	${RADAR_DBUTILS}/bin/logProcessedFile.csh ${RADAR_DBSCHEMADIR} \
		${JOBKEY} ${file} ${BEST_HITS_FILETYPE}
	STAT=$?
	checkStatus ${STAT} "logProcessedFile.csh ${APP_INFILE_BEST_HITS}"
    done

    for file in ${APP_INFILE_SINGLE_HITS}
    do
	${RADAR_DBUTILS}/bin/logProcessedFile.csh ${RADAR_DBSCHEMADIR} \
		${JOBKEY} ${file} ${SINGLE_HITS_FILETYPE}
	STAT=$?
	checkStatus ${STAT} "logProcessedFile.csh ${APP_INFILE_SINGLE_HITS}"
    done

    echo 'Done logging processed files' >> ${LOG_DIAG}

fi

#
# parse the curation log into a readable format
#
echo "Parsing Gene Trap ALO Load Curator Log" | tee -a ${LOG_PROC} ${LOG_DIAG}
${GENETRAPLOAD}/bin/parseCuratorLog.sh
STAT=$?

# this is not a fatal error, so don't use checkStatus
if [ ${STAT} -ne 0 ]
then
    echo "Parsing Curator Log Failed. Return Status: ${STAT}" | tee -a ${LOG_PROC} ${LOG_DIAG}
else
    echo "Parsing Curator Log completed successfully" | tee -a ${LOG_PROC} ${LOG_DIAG}
fi

#
# run Gene Trap Coordinate load
#
echo "\n`date`" | tee -a ${LOG_PROC} ${LOG_DIAG}
echo "Running Gene Trap Coordinate Load" 
${GTCOORDLOAD}/bin/gtcoordload.sh 
STAT=$?
checkStatus ${STAT} "Gene Trap Coordinate Load"

#
# run ALO Marker Association load
#
if [ $RUN_ALOMARKER = yes ]
then
    #
    # Run Sequence/Coordinate, Seq/Marker and Marker/Location Cache Loads since we've loaded
    # coordinates. Mrk/Loc cache load relies on seq/coord and seq/marker cache tables
    # and alomrkload uses seq/coord and mrk/location cache tables
    #
    echo "\n`date`" | tee -a ${LOG_PROC} ${LOG_DIAG}
    echo "Running Sequence Coordinate Cache Load" | tee -a ${LOG_PROC} ${LOG_DIAG}
    ${SEQCACHELOAD}/seqcoord.csh
    STAT=$?
    checkStatus ${STAT} "Sequence Coordinate Cache Load"

    echo "\n`date`" | tee -a ${LOG_PROC} ${LOG_DIAG}
    echo 'Running Sequence Marker Cache Load' | tee -a ${LOG_PROC} ${LOG_DIAG}
    ${SEQCACHELOAD}/seqmarker.csh
    STAT=$?
    checkStatus ${STAT} "Sequence Marker Cache Load"

    echo "\n`date`" | tee -a ${LOG_PROC} ${LOG_DIAG}
    echo "Running Marker Location Cache Load" | tee -a ${LOG_PROC} ${LOG_DIAG}
    ${MRKCACHELOAD}/mrklocation.csh
    STAT=$?
    checkStatus ${STAT} "Marker Location Cache Load"

    runMarkerAssocLoad
fi

#
# run postload cleanup and email logs
#
shutDown

exit 0

