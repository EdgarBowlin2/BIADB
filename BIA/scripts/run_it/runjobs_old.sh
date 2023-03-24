#!/bin/bash
#-------------------------------------------------------------------------------
#- RunJobs.sh - Script Execution Management                                    -
#-------------------------------------------------------------------------------
#- Edgar Bowlin                                                    4-14-2021   -
#-------------------------------------------------------------------------------
#- Script Execution Management will set environment variables, execute scripts,-
#- monitor progress, and report the outcome, emailing the results to an input  -
#- distribution list, if requested.                                            -
#-------------------------------------------------------------------------------

#set -x
. ~/.bash_profile > /dev/null
. ~/scripts/functions/functions.sh > /dev/null

start_time=$(get_timestamp)
ORACLE_SID=.`ps -ef | grep pmon | grep -vE grep | grep -vE ASM | cut -d_ -f3`

export BLACKOUT=0
export EMAIL=0
export IMPORTANT=0
export JOB_CATEGORY=A
# Check parameters
while getopts 'c:m:p:r:t:b:e:i' OPTION
do
  case $OPTION in
  c)    export COMMAND_LINE=${OPTARG}
        ;;
  m)    export MESSAGE_SUBJECT=${OPTARG}
        ;;
  p)    export PASS_PARMS=${OPTARG}
        ;;
  r)    export RECIPIENTS=${OPTARG}
        ;;
  b)    export BLACKOUT=1
        ;;
  t)    export JOB_CATEGORY=${OPTARG}
        ;;
  e)  export EMAIL=1
        ;;
  i)  export IMPORTANT=1
        ;;
  ?)    COMMAND_LINE=run_it/run_it_errorV2
        ;;
   esac
done


shift $(($OPTIND - 1))
STATUS=0

echo [ -z $COMMAND_LINE ] && echo NOT EMPTY || echo EMPTY

### Check for required parameters
if [ -z "$COMMAND_LINE" ]; then
  echo COMMAND_LINE not found
  COMMAND_LINE=run_it/run_it_errorV2
fi

export COMMAND_NAME=`basename ${SCRIPT_DIR}${COMMAND_LINE}`

echo SCRIPT_DIR=$SCRIPT_DIR

### Set Default Values
dtStamp=`date +%m%d%y.%H%M`
RUN_DIR=${SCRIPT_DIR}/run_it

if [ -z $MESSAGE_SUBJECT ]; then
  export MESSAGE_SUBJECT="${COMMAND_NAME}"
fi

if [ -z $JOB_CATEGORY ]; then
  export JOB_CATEGORY=I
fi

export FULL_COMMAND=${SCRIPT_DIR}/${COMMAND_LINE}   # KEEP
export FULL_COMMAND=/home/oracle/scripts/test/test.sh

echo [ -f ${SCRIPT_DIR}/${COMMAND_LINE} ] && echo FOUND || echo NOT FOUND

if [ -f ${SCRIPT_DIR}/${COMMAND_LINE} ]; then
  echo "Valid Script"
else
  echo "Invalid Script"
  COMMAND_LINE=run_it/run_it_errorV2
fi

# If a recipient list file was specified on the command line
# use it, otherwise default to DBAHeader.txt
if [ -f ${RUN_DIR}/${RECIPIENTS} ]; then
  export RECIPIENTS=${RUN_DIR}/${RECIPIENTS}
else
  export RECIPIENTS=${RUN_DIR}/DBAHeader.txt
fi

# Is the Job blacked out?
if [ $BLACKOUT -eq 1 ]; then
  EXEC_LOG=${SCRIPT_DIR}/run_it/blackout.txt
  export RETURNED_STATUS=BLACKOUT
  echo Job_Category $JOB_CATEGORY
  echo Returned_status $RETURNED_STATUS
  run_it_db_log # V2 - log the blackout
  echo "subject:BLACKOUT ${MESSAGE_SUBJECT} on ${HOST}." | cat - ${RECIPIENTS} ${EXEC_LOG} | /usr/sbin/sendmail -t
  exit
fi

# LOG_DIR= --set in profile
EXEC_LOG=${LOG_DIR}/run_it.${COMMAND_NAME}$ORACLE_SID.${dtStamp}.log

echo LOG is $EXEC_LOG

#Run the passed command
${SCRIPT_DIR}/${COMMAND_LINE} ${PASS_PARMS} $* 2>&1 | tee ${EXEC_LOG}
STATUS=${PIPESTATUS[0]} #PIPESTATUS is a 0 based array of all the stati of the previous piped commands
end_time=$(get_timestamp)  # V2

if [ ${STATUS} -ne 0 ]; then
  echo "subject:FAILED ${MESSAGE_SUBJECT} on ${HOST}." | cat - ${RECIPIENTS} ${EXEC_LOG} | /usr/sbin/sendmail -t
  export RETURNED_STATUS=FAILED
  run_it_db_log # V2 - log the failure
  exit 1
else
  export RETURNED_STATUS=SUCCEEDED
  if [ "$JOB_CATEGORY" = "A" -o $EMAIL -eq 1 ]; then
     echo "subject:SUCCEEDED ${MESSAGE_SUBJECT} on ${HOST}." | cat - ${RECIPIENTS} ${EXEC_LOG}  | /usr/sbin/sendmail -t
  fi
  run_it_db_log # V2 - log the success

  echo $?
 fi  
