#!/bin/bash

#      



# Source last repository revision in full backup as variable $LAST_REVISION



source /etc/svnbackup/last_revision



# Script Variables

 

DUMP_NAME="/var/svnbackup/svnbackup-differential-"$LAST_REVISION".dump"

 

# Commands to run

 

svnadmin dump /var/www/svn/dev/ -r $LAST_REVISION:HEAD --incremental > $DUMP_NAME



# End