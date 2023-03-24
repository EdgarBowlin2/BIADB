#!/bin/bash
################################################################################
#
#   Name:       report_dropin.sh
#   Create:     20-FEB-2019
#   Author:     Joel Marsh
#   Platform:   Linux
#   Purpose:    Report framework for multiple queries yeilding a single HTML
#               email report
#
#   Parameters: db_name, report_subdir
#
#   Prereqs:    -
#               -
#               -
#
#   Change:
#sqlplus log in changes made to accomodate rrc-prodtest
#
################################################################################

########################################
#init scripts
########################################

. ~/.bash_profile > /dev/null
. $SCRIPT_DIR/functions.sh > /dev/null  

########################################
#constants
########################################

basedir=$SCRIPT_DIR/monitor
email=do_not_reply@va.gov

########################################
#parameters
########################################

db_name=$1
dir_name=$2

ORACLE_SID=$db_name

########################################
# verify parameters
########################################

if [ -z $ORACLE_SID ]; then
    echo "Error... SID not found!"
    printf "Usage: report_dropin.sh <DB Name> <Report Directory> \n"
    exit 1
fi

if [ ! -d $basedir/${dir_name} ]; then
    echo "Error... $basedir/$dir_name not found!"
    exit 1
fi

#if [ ! -f $HOME/$ORACLE_SID.env ]; then
#    echo "Error... Invalid SID!"
#    exit 1
#fi

#echo "sid: "$ORACLE_SID
#. ~/$ORACLE_SID.env > /dev/null

########################################
#variables
########################################

reportdir=${basedir}/${dir_name}
reportout=${reportdir}/${dir_name}.html
#dtStamp=`date +%m%d%y.%H%M`
dtStamp=`date +%Y%m%d`
export day=`date +"%A"`

cd ${reportdir}
rm -f ${reportout}
rm -f *.csv
cat ${basedir}/reporthead.html > ${reportout}

########################################
#checks
########################################

#check database status, exit if not open
dbstatus $ORACLE_SID

##########################################################
# Run OPTIONAL email subject query
##########################################################

if [ -f subject.sql ]; then
   sqlplus -s /@${ORACLE_SID} @subject.sql > subject.txt
fi

if [ ! -f subject.txt ]; then
   echo "Error... subject.txt not found!"
echo "CWD=`pwd`"
   exit 1
fi

##########################################################
# Run report queries
##########################################################

for i in `cat runorder.txt`; do
   if [ -f ${i} ]; then
      echo "  - Starting Report SQL Script: ${i}"
      outroot=`echo ${i} | cut -d"." -f1`
      title=`head -n 1 ${i} | cut -d"-" -f3`
      echo "<br><h3 align=\"center\">${title}</h3>" > ${outroot}.title.html
      sqlplus -s /@${ORACLE_SID} >${outroot}.html <<EOF
         @${basedir}/sqlplushtmlparams.sql;
         @${i};
         exit;
EOF
      SQL_STATUS=$?
      if [ $SQL_STATUS -ne 0 ]; then
         echo "*** SQL script reported errors.  Please investigate.  Exiting..."
         exit 1
      else
         echo "SQL script completed"
         cat ${outroot}.title.html >> ${reportout}
         cat ${outroot}.html >> ${reportout}
      fi
  fi
  echo ""
done

################################################################
# csv file attachments
################################################################

if [ `ls -1 *.csv.sql 2>/dev/null | wc -l` -gt 0 ]; then
   for i in `ls -1 *.csv.sql`; do
    sqlplus -s /@${ORACLE_SID} <<EOF
      @$i;
      exit;
EOF
    SQL_STATUS=$?
    if [ $SQL_STATUS -ne 0 ]; then
      echo "*** SQL script reported errors.  Please investigate.  Exiting..."
      exit 1
    fi
done
fi

################################################################
# Assemble and send email
################################################################
cat ${basedir}/reporttail.html >> ${reportout}
if [ `ls -1 *.csv.sql 2>/dev/null | wc -l` -gt 0 ]; then
  echo "Zipping the files.... "
  rm -f ${dir_name}*.zip
  zip ${dir_name}.${dtStamp}.zip *.csv

  echo "Zip Complete "

  cat ${reportout} | mutt -s "`cat subject.txt`" `cat addresses.txt` -e "set content_type=text/html" -a ${dir_name}.${dtStamp}.zip
else
  cat ${reportout} | mutt -s "`cat subject.txt`" `cat addresses.txt` -e "set content_type=text/html"
fi
exit 0

