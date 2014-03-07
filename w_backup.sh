#!/bin/bash
##
## MySQL Weekly Backup Script
##
##
export_dir="/data/backup/mysql/weekly"
myopts="-Bse" # add username/password if not using ~/.my.cnf
timestamp=`date +"%y-%m-%d"`
day_of_month=`date +%d`
uname="<db_user>"
err_exit()
{
echo -e 1>&2
exit 1
}

# for ((i=1; i<6; i++; '<alt_server>'))
# ^ Use this line instead of line 20 in the event that one MySQL server in the cluster 
#   has a different MySQL root user password than the others

for ((i=1; i<6; i++))
do

# if [ "${i}"=="<alt_server>" ];
#  then
#        pw="<password>"
#  else
#        pw="<alt_password>"
# fi
#
# ^ In the event that one MySQL server in the cluster has a different MySQL root user password than the others,
#   this password exception clause notifies the backup script to adjust the root password accordingly.



DBS="$(mysql --socket=/var/lib/mysql/${i}/${i}-mysql.sock --user=$uname --password=$pw $myopts 'show databases' | egrep -v 'performance_schema|information_schema|mysql|test')"
if [ $day_of_month -ne '01' ]; then
  echo "Beginning backup: `date`"
  mkdir ${export_dir}/${timestamp}
  # Flush logs and stop slave
  mysql --socket=/var/lib/mysql/${i}/${i}-mysql.sock --user=$uname --password=$pw -e 'flush logs; stop slave;'
  # Dump schema
  mysqldump --socket=/var/lib/mysql/${i}/${i}-mysql.sock --user=$uname --password=$pw --all-databases --no-data > ${export_dir}/${timestamp}/${i}.schema_dump.sql
  # Dump slave and master status
  mysql --socket=/var/lib/mysql/${i}/${i}-mysql.sock --user=$uname --password=$pw -e 'show slave status \G' > $export_dir/$timestamp/${i}.slave_status
  mysql --socket=/var/lib/mysql/${i}/${i}-mysql.sock --user=$uname --password=$pw -e 'show master status \G' > $export_dir/$timestamp/${i}.master_status
  for db in ${DBS}
  do
    echo "Backup of ${db} beginning"
    mysql_data_dir=$(mysql --socket=/var/lib/mysql/${i}/${i}-mysql.sock --user=$uname --password=$pw $myopts "show variables like 'datadir'" | awk '{sub(/\/$/,"");print$NF}')
    if ! (mysqlshow --socket=/var/lib/mysql/${i}/${i}-mysql.sock --user=$uname --password=$pw $db 1>/dev/null); then
        echo ERROR: unable to access database
        exit 1
    fi
    if ! [ -w $export_dir ]; then
        echo ERROR: export dir is not writable
        exit 1
    fi
    if ! (touch $mysql_data_dir/$db/test 2>/dev/null); then
        echo ERROR: this script will need sudo access to
        echo move exported files out of mysql data dir.
        echo Come back when you get sudo, son.
        exit 1
    else
         rm $mysql_data_dir/$db/test
    fi
# loop through the DB list and create table level backup
    index=0
    table_types=($(mysql --socket=/var/lib/mysql/${i}/${i}-mysql.sock --user=$uname --password=$pw -e "show table status from $db" | \
            awk '{ if ($2 == "MyISAM" || $2 == "InnoDB") print $1,$2}'))
    table_type_count=${#table_types[@]}
    while [ "$index" -lt "$table_type_count" ]; do
        START=$(date +%s)
        TYPE=${table_types[$index + 1]}
        table=${table_types[$index]}
        echo -en "$(date) : backup $DB : $table : $TYPE "
        if [ "$TYPE" = "MyISAM" ]; then
            DUMP_OPT="--socket=/var/lib/mysql/${i}/${i}-mysql.sock --user=$uname --password=$pw $db --no-create-info --tables "
        else
            DUMP_OPT="--socket=/var/lib/mysql/${i}/${i}-mysql.sock --user=$uname --password=$pw $db --no-create-info --single-transaction --tables"
        fi
        mysqldump $DUMP_OPT $table |gzip -c > ${export_dir}/${timestamp}/${i}.${db}.$table.sql.gz
        index=$(($index + 2))
        echo -e " - Total time : $(($(date +%s) - $START))\n"
    done
    echo "Backup of ${db} complete"
  done
  # Start slave
  mysql --socket=/var/lib/mysql/${i}/${i}-mysql.sock --user=$uname --password=$pw -e 'start slave'
  # Remove temporary files and daily backups older than 28 days
  find ${export_dir} -type f -mtime +29 -exec rm {} \;
  echo "Completed backup: `date`"
else
  echo "Today's the first of the month - no weekly backup!"
fi
done