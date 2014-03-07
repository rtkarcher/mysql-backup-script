#!/bin/bash
 
export_dir="/opt/backup/weekly" 
myopts=" -Bse" # add username/password if not using ~/.my.cnf
#DBS="$(mysql --socket=/opt/mysql-sock/cluster${i}.sock $myopts 'show databases' | egrep -v 'performance_schema | information_schema | mysql | test')"
timestamp=`date +"%y-%m-%d"`
day_of_month=`date +%d`
uname="root"
pword="xxxxxx"
 
err_exit()
{
 echo -e 1>&2
 exit 1
}
 
for ((i=1; i<6; i++))
do
 
DBS="$(mysql --socket=/opt/mysql-sock/cluster${i}.sock $myopts 'show databases' | egrep -v 'performance_schema | information_schema | mysql|test')"
 
if [ $day_of_month -ne '01' ]; then
 
  echo "Beginning backup: `date`"
  mkdir ${export_dir}/${timestamp}
  # flush logs and stop slave
  mysql --socket=/opt/mysql-sock/cluster${i}.sock -e 'flush logs;stop slave'
  # dump schema
 
  mysqldump --socket=/opt/mysql-sock/cluster${i}.sock --all-databases --no-data > ${export_dir}/${timestamp}/cluster${i}.schema_dump.sql
 
  # dump slave and master status
 
  mysql --socket=/opt/mysql-sock/cluster${i}.sock -e 'show slave status\G' > $export_dir/$timestamp/cluster${i}.slave_status
  mysql --socket=/opt/mysql-sock/cluster${i}.sock -e 'show master status\G' > $export_dir/$timestamp/cluster${i}.master_status
 
 
  for db in ${DBS}
  do
 
    echo "Backup of ${db} beginning"
    mysql_data_dir=$(mysql --socket=/opt/mysql-sock/cluster${i}.sock $myopts "show variables like 'datadir'" | awk '{sub(/\/$/,"");print$NF}')
 
    if ! (mysqlshow --socket=/opt/mysql-sock/cluster${i}.sock $db 1>/dev/null); then
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
    table_types=($(mysql --socket=/opt/mysql-sock/cluster${i}.sock -e "show table status from $db" | \
            awk '{ if ($2 == "MyISAM" || $2 == "InnoDB") print $1,$2}'))
    table_type_count=${#table_types[@]}
 
    while [ "$index" -lt "$table_type_count" ]; do
        START=$(date +%s)
        TYPE=${table_types[$index + 1]}
        table=${table_types[$index]}
        echo -en "$(date) : backup $DB : $table : $TYPE "
        if [ "$TYPE" = "MyISAM" ]; then
            DUMP_OPT="--socket=/opt/mysql-sock/cluster${i}.sock $db --no-create-info --tables "
        else
            DUMP_OPT="--socket=/opt/mysql-sock/cluster${i}.sock $db --no-create-info --single-transaction --tables"
        fi
        mysqldump  $DUMP_OPT $table |gzip -c > ${export_dir}/${timestamp}/cluster${i}.${db}.$table.sql.gz
        index=$(($index + 2))
        echo -e " - Total time : $(($(date +%s) - $START))\n"
    done
 
    echo "Backup of ${db} complete"
  done
 
  # start slave
  mysql --socket=/opt/mysql-sock/cluster${i}.sock -e 'start slave' 
 
 
 
  # remove temporary files and daily backups older than twenty-eight days
 
  find ${export_dir} -type f -mtime +29 -exec rm {} \;
 
  echo "Completed backup: `date`"
else
  echo "Today is the 1st of the month. No weekly backup."
fi
 
done
