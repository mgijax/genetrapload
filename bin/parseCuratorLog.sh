#!/bin/sh
#
#  parseCuratorLog.sh
###########################################################################
#
#  Purpose:  This script  parses the curator logs and prepares a formatted
#            report
#
#  Usage:
#
#      parseCuratorLog.sh
#
#  Env Vars:
#
#       OUTPUTDIR
#	RPTDIR
#	LOGC, LOCD, LOGP
#
#  Inputs:
#
#      - Common configuration file -
#		/usr/local/mgi/live/mgiconfig/master.config.sh
#      - curator log
#
#  Outputs:
#
#      - writes to ${LOG_PROC} ${LOG_DIAG} ${LOG_CUR} and 
#	 assumes these logs are open and writable
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
LOG=`pwd`/parseCuratorLog.log
rm -f ${LOG}

#
#  Verify the argument(s) to the shell script.
#
if [ $# -ne 0 ]
then
    echo "Usage: $0" | tee -a ${LOG}
    exit 1
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
echo "parseCuratorLog.sh Sourcing config file"

. ${CONFIG_LOAD}
echo "parseCuratorLog.sh looking in log directory ${LOGDIR}"
#
# create the report basename
#

REPORT=${RPTDIR}/cur.report

#
#  Make sure the master configuration file is readable
#

if [ ! -r ${CONFIG_MASTER} ]
then
    echo "Cannot read configuration file: ${CONFIG_MASTER}"
    exit 1
fi


##################################################################
##################################################################
#
# main
#
##################################################################
##################################################################

# repeats
echo "ALOs Repeated in the Input" > ${REPORT}.repeatedALO
cat ${LOGDIR}/genetrapload.cur.log | grep "This ALO is repeated in the input:"  | sort | uniq >> ${REPORT}.repeatedALO

# resolving exception
echo "Unresolved ALO Attributes" >  ${REPORT}.resErrors.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Cannot resolve attribute type(s)/value(s)"  | sort >> ${REPORT}.resErrors.skip

# uniq set of resolving errors
echo "Uniq Set of Unresolved ALO Attributes"  >  ${REPORT}.resErrors.uniq.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Cannot resolve attribute type(s)/value(s)"  | sort | uniq >> ${REPORT}.resErrors.uniq.skip

# derivations
echo "Comparing Incoming Derivation Attributes to Those in the Database" > ${REPORT}.derivCompare
cat ${LOGDIR}/genetrapload.cur.log | grep "DERIV_COMPARE:" | sort | uniq >> ${REPORT}.derivCompare

echo "Required Derivation Attribute is Null" > ${REPORT}.derivNullAttrib.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Required attribute is null:" | sort | uniq >> ${REPORT}.derivNullAttrib.skip

echo "Derivations not Resolved " > ${REPORT}.derivNotResolve.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Cannot find Derivation in the database for raw cell line library:"  | sort | uniq >> ${REPORT}.derivNotResolve.skip

cat ${LOGDIR}/genetrapload.cur.log | grep "Creator Not Resolved:"  | sort | uniq >> ${REPORT}.derivNotResolve.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Creator Not Specified"  | sort | uniq >> ${REPORT}.derivNotResolve.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Parent Cell Line Not Resolved:"  | sort | uniq >> ${REPORT}.derivNotResolve.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Parent Cell Line Not Specified"  | sort | uniq >> ${REPORT}.derivNotResolve.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Vector Name Not Resolved:"  | sort | uniq >> ${REPORT}.derivNotResolve.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Vector Name Not Specified"  | sort | uniq >> ${REPORT}.derivNotResolve.skip

echo "Derivation updated in the Database" >${REPORT}.MCLDerivationsUpdated
cat ${LOGDIR}/genetrapload.cur.log | grep "Updating MCL derivation" | sort | uniq >> ${REPORT}.MCLDerivationsUpdated

# cell line
echo "Cell Line ID found in Allele Nomen" > ${REPORT}.cellLineIdInAlleleNomen.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Cell Line ID in allele nomen:" | sort | uniq >> ${REPORT}.cellLineIdInAlleleNomen.skip

echo "Mutant Cell Line in DB associated w/No Allele or Multi Alleles" >  ${REPORT}.mclAssocNoOrMultiAlleles
cat ${LOGDIR}/genetrapload.cur.log | grep "MCL in database associated with no allele or multiple alleles:" | sort | uniq >> ${REPORT}.mclAssocNoOrMultiAlleles

echo "Comparing Incoming Cell Line Attributes to Those in the Database" > ${REPORT}.mclCompare
cat ${LOGDIR}/genetrapload.cur.log | grep "MCL_COMPARE:" | sort | uniq >> ${REPORT}.mclCompare

# allele
echo "Comparing Incoming Allele Attributes to Those in the Database" > ${REPORT}.alleleCompare
cat ${LOGDIR}/genetrapload.cur.log | grep "ALLELE_COMPARE:" | sort | uniq >> ${REPORT}.alleleCompare

cat ${LOGDIR}/genetrapload.cur.log | grep "MCLs in database and not in input for allele symbol" | sort | uniq > ${REPORT}.JED

# allele mutation
echo "Mutation Discrepancies" > ${REPORT}.mutationDiscrep
cat ${LOGDIR}/genetrapload.cur.log | grep "Allele Key" | sort | uniq >> ${REPORT}.mutationDiscrep

# sequence association
echo "Sequences Associated with a different Allele" >  ${REPORT}.seqAssocWithAllele.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Sequence associated with allele:" | sort | uniq >> ${REPORT}.seqAssocWithAllele.skip

echo "Sequences Associated with a Marker" >  ${REPORT}.seqAssocWithMarker.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Sequence associated with marker:" | sort | uniq >> ${REPORT}.seqAssocWithMarker.skip

echo "Sequence Objects not in Database" >  ${REPORT}.seqNotInMGI.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "SeqID does not have a sequence object in the database:" | sort | uniq >> ${REPORT}.seqNotInMGI.skip

#
# gene trap only
#
echo "Sequence Tag Id Does not Have a Vector End Component" >  ${REPORT}.seqTagIdMissingVectorEnd.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Sequence Tag Id does not have a vector end component:" | sort | uniq >> ${REPORT}.seqTagIdMissingVectorEnd.skip

echo "Creator Not Found in Input" >  ${REPORT}.creatorNotFound.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Creator not found for seqID:" | sort | uniq >> ${REPORT}.creatorNotFound.skip

echo "Sequence Tag Method not Found in Input" > ${REPORT}.seqTagMethodNotFound.skip
cat ${LOGDIR}/genetrapload.cur.log | grep "Sequence Tag Method not found for seqID:" | sort | uniq >> ${REPORT}.seqTagMethodNotFound.skip

echo "Vector Name not Found in Input" > ${REPORT}.vectorNameNotFoundInInput
cat ${LOGDIR}/genetrapload.cur.log | grep "Vector Name not found for seqID:" | sort | uniq >> ${REPORT}.vectorNameNotFoundInInput

echo "Sequence Keys Updated to Active Status" > ${REPORT}.seqsUpdatedToActive
cat ${LOGDIR}/genetrapload.cur.log | grep "SeqKey updated to ACTIVE:" | sort | uniq >> ${REPORT}.seqsUpdatedToActive

exit 0
