#!/usr/local/bin/python

# Program:
# Purpose:
# User Requirements Satisfied by This Program:
# System Requirements Satisfied by This Program:
#       Usage:
#       Uses:
#       Envvars:
#       Inputs:
#       Outputs:
#       1. Updates sequences that have been processed by the gene trap
#          alo load to status = 'Active' if their status is 'Deleted'
#
#       Exit Codes:
#       Other System Requirements:
# Assumes:
# Implementation:
#       Modules:

import sys
import db
import os
import string
import time

#
# global variables
#

# for time stamping
STARTTIME = time.time()

# term key for deleted sequence status
DELETED = 316343

# update statement to update a sequence to ACTIVE
updateStatement = '''UPDATE SEQ_Sequence SET _SequenceStatus_key = 316342
            WHERE _Sequence_key = %d'''

# full path to file of sequence keys processed by the java load
seqFilePath = os.environ['SEQUENCES_PROCESSED']

# full path to diagnostic log
curLogPath = os.environ['LOG_CUR']
logCur = open(curLogPath, 'a')

# all dbGSS sequences in MGI with their statuses
# {sequenceKey:statusKey, ...}
deletedList = []

# Purpose:
# Returns:
# Assumes:
# Effects:
# Throws:
# Notes: (opt)
# Example: (opt)

def bailout (msg):
    print msg
    sys.exit(1)

def preprocess ():
    global deletedList

    results = db.sql('''SELECT s._Sequence_key, s._SequenceStatus_key
	FROM SEQ_Sequence s
	WHERE division = "GSS"
	and _SequenceStatus_key = 316343''', 'auto')
    for s in results:
	seqKey = s['_Sequence_key']
	deletedList.append(seqKey)
def process ():
    global deletedList
    cmds = []
    if not os.path.exists(seqFilePath):
	    bailout("Cannot find sequence file: %s" % seqFilePath)
    inFile = open(seqFilePath, 'r')
    ctr = 0
    for line in inFile.readlines():
	ctr = ctr + 1
	if ctr % 10000 == 0:
	    print "Processed %s input records" % ctr
        seqKey = int(string.strip(line))
	if seqKey in deletedList:
	    cmds.append (updateStatement % seqKey)
	    logCur.write('SeqKey updated to ACTIVE: %s\n' % seqKey)
    inFile.close()
    return cmds

def updateDatabase (cmds):
    dbServer = os.environ['MGD_DBSERVER']
    dbName = os.environ['MGD_DBNAME']
    dbUser = os.environ['MGD_DBUSER']
    dbPasswordFile = os.environ['MGD_DBPASSWORDFILE']
    dbPassword = string.strip(open(dbPasswordFile,'r').readline())
    db.set_sqlLogin(dbUser, dbPassword, dbServer, dbName)

    # process in batches of 100
    total = len(cmds)

    try:
	    db.useOneConnection(1)
	    while cmds:
		    print 'Current running time (secs): %s' % (time.time() - STARTTIME)
		    db.sql (cmds[:100], 'auto')
		    cmds = cmds[100:]
	    db.useOneConnection(0)
    except:
	    bailout ('Failed during database updates')

    print 'Processed %d updates to SEQ_Sequence._SequenceStatus_key' % total
    print 'Total running time (secs): %s' % (time.time() - STARTTIME)
    return

#
# Main
#

print "Loading dbGSS sequence lookup"
preprocess ()

print "Creating update commands"
cmds = process ()

print "Updating database"
print "Total updates: %s " % len(cmds)
updateDatabase (cmds)

logCur.close()
