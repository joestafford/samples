#!/bin/bash

#      

# Script Variables

 

DUMP_NAME="/var/svnbackup/svnbackup-full-"$(date +%Y-%m-%d)".dump"

 

# Commands to run



rm -f /var/svnbackup/svnbackup*.dump 

svnadmin dump /var/www/svn/dev/ > $DUMP_NAME

 

tac $DUMP_NAME | grep -m1 --binary-files=text "Revision-number" | sed 's/Revision-number\:\ /LAST_REVISION=/g' > /etc/svnbackup/last_revision

 

# End