# CentOS 7.x MariaDB 10.x backup using Mariabackup

This repository contains a few scripts for automating backups with mariabackup (a fork of Percona Xtrabackup) by MariaDB.

These instructions adapted for CentOS 7.x & MariaDB 10.x were mostly taken from <a href="https://github.com/nullart">nullart</a>'s <a href="https://github.com/nullart/debian-ubuntu-mariadb-backup">debian-ubuntu-mariadb-backup</a> repository which referenced <a href="https://www.digitalocean.com/community/users/jellingwood">Justin Ellingwood</a>'s original article <a href="https://www.digitalocean.com/community/tutorials/how-to-configure-mysql-backups-with-percona-xtrabackup-on-ubuntu-16-04">here</a>.

## Requirements
You will require the **qpress** utility from Percona to perform decompression and extraction. Mariabackup recommends using third-party compression tools, however from testing, it seems the native Xtrabackup --compress option still produces the fastest result (requires further testing).

Check the latest instructions from Percona website for installing **qpress** using the official Percona repository.

```
$ yum install https://repo.percona.com/yum/percona-release-latest.noarch.rpm
$ yum install qpress
```

## Create a MySQL User with Appropriate Privileges

The first thing we need to do is create a new MySQL user configured to handle backup tasks. We will only give this user the privileges it needs to copy the data safely while the system is running.

To be explicit about the account's purpose, we will call the new user backup. We will be placing the user's credentials in a secure file, so feel free to choose a complex password:

```
mysql> CREATE USER 'backup'@'localhost' IDENTIFIED BY 'password';
```

Next we need to grant the new **backup** user the permissions it needs to perform all backup actions on the database system. Grant the required privileges and apply them to the current session by typing:

```
mysql> GRANT RELOAD, LOCK TABLES, REPLICATION CLIENT, CREATE TABLESPACE, PROCESS, SUPER, CREATE, INSERT, SELECT ON *.* TO 'backup'@'localhost';
mysql> FLUSH PRIVILEGES;
```

Our MySQL backup user is configured and has the access it requires.

## Display the value of the datadir variable 

```
mysql> SELECT @@datadir;

+-----------------+
| @@datadir       |
+-----------------+
| /var/lib/mysql/ |
+-----------------+
1 row in set (0.01 sec)
```

Take a note of the location you find.

## Creating the Backup Assets

Now that MySQL and system backup users are available, we can begin to set up the configuration files, encryption keys (currently disabled), and other assets that we need to successfully create and secure our backups.

### Create a MySQL Configuration File with the Backup Parameters

Begin by creating a minimal MySQL configuration file that the backup script will use. This will contain the MySQL credentials for the MySQL user.

Open a file at **/etc/my.cnf.d/mariabackup.cnf** in your text editor:

```
$ nano /etc/my.cnf.d/mariabackup.cnf
```

Inside, start a ```[mariabackup]``` section and set the MySQL backup user and password user you defined within MySQL:

```
[mariabackup]
user = backup
password = password
databases = database_name # (Optional) Limit backup of specific databases only
```

Save and close the file when you are finished.

## Downloading the Backup and Restore Scripts

Clone this repo to a local folder.

Be sure to inspect the scripts after downloading to make sure they were retrieved successfully and that you approve of the actions they will perform. If you are satisfied, mark the scripts as executable and then move them into the /usr/local/bin directory by typing:

```
$ chmod +x {backup,extract,prepare}-mysql.sh
$ mv /tmp/{backup,extract,prepare}-mysql.sh /usr/local/bin
```

## Using the Backup and Restore Scripts

In order to make our backup and restore steps repeatable, we will script the entire process. We will use the following scripts:

* **backup-mysql.sh**: This script backs up the MySQL databases, encrypting and compressing the files in the process. It creates full and incremental backups and automatically organizes content by day. By default, the script maintains 3 days worth of backups.
* **extract-mysql.sh**: This script decompresses and decrypts the backup files to create directories with the backed up content.
* **prepare-mysql.sh**: This script "prepares" the back up directories by processing the files and applying logs. Any incremental backups are applied to the full backup. Once the prepare script finishes, the files are ready to be moved back to the data directory.

Be sure to inspect the scripts after downloading to make sure they were retrieved successfully and that you approve of the actions they will perform. If you are satisfied, mark the scripts as executable and then move them into the ```/usr/local/bin``` directory by typing:

```
$ chmod +x /tmp/{backup,extract,prepare}-mysql.sh
$ mv /tmp/{backup,extract,prepare}-mysql.sh /usr/local/bin
```

### The backup-mysql.sh Script

The script has the following functionality:

* Creates a compressed full backup the first time it is run each day.
* Generates compressed incremental backups based on the daily full backup when called again on the same day.
* Maintains backups organized by day. By default, three days of backups are kept. This can be changed by adjusting the days_of_backups parameter within the script.

When the script is run, a daily directory is created where timestamped files representing individual backups will be written. The first timestamped file will be a full backup, prefixed by full-. Subsequent backups for the day will be incremental backups, indicated by an incremental- prefix, representing the changes since the last full or incremental backup.

Backups will generate a file called backup-progress.log in the daily directory with the output from the most recent backup operation. A file called xtrabackup_checkpoints containing the most recent backup metadata will be created there as well. This file is needed to produce future incremental backups, so it is important not to remove it. A file called xtrabackup_info, which contains additional metadata, is also produced but the script does not reference this file.

### The extract-mysql.sh Script

Unlike the backup-mysql.sh script, which is designed to be automated, this script is designed to be used intentionally when you plan to restore from a backup. Because of this, the script expects you to pass in the .xbstream files that you wish to extract.

The script creates a restore directory within the current directory and then creates individual directories within for each of the backups passed in as arguments. It will process the provided .xbstream files by extracting directory structure from the archive, decrypting the individual files within, and then decompressing the decrypted files.

After this process has completed, the restore directory should contain directories for each of the provided backups. This allows you to inspect the directories, examine the contents of the backups, and decide which backups you wish to prepare and restore.

### The prepare-mysql.sh Script

This script will apply the logs to each backup to create a consistent database snapshot. It will apply any incremental backups to the full backup to incorporate the later changes.

The script looks in the current directory for directories beginning with full- or incremental-. It uses the MySQL logs to apply the committed transactions to the full backup. Afterwards, it applies any incremental backups to the full backup to update the data with the more recent information, again applying the committed transactions.

Once all of the backups have been combined, the uncommitted transactions are rolled back. At this point, the full- backup will represent a consistent set of data that can be moved into MySQL's data directory.

In order to minimize chance of data loss, the script stops short of copying the files into the data directory. This way, the user can manually verify the backup contents and the log file created during this process, and decide what to do with the current contents of the MySQL data directory. The commands needed to restore the files completely are displayed when the command exits.

## Testing the MySQL Backup and Restore Scripts

### Perform a Full Backup

```
$ backup-mysql.sh

Backup successful!
Backup created at /backups/mysql/Thu/full-2017-04-20_14-55-17.xbstream

```

If everything went as planned, the script will execute correctly, indicate success, and output the location of the new backup file. As the above output indicates, a daily directory ("Thu" in this case) has been created to house the day's backups. The backup file itself begins with full- to express that this is a full backup.

Let's move into the daily backup directory and view the contents:

```
$ cd /backups/mysql/"$(date +%a)"
$ ls

backup-progress.log  full-2017-04-20_14-55-17.xbstream  xtrabackup_checkpoints  xtrabackup_info

```

Here, we see the actual backup file (full-2017-04-20_14-55-17.xbstream in this case), the log of the backup event (backup-progress.log), the xtrabackup_checkpoints file, which includes metadata about the backed up content, and the xtrabackup_info file, which contains additional metadata.

If we tail the backup-progress.log, we can confirm that the backup completed successfully.

```
$ tail backup-progress.log

170420 14:55:19 All tables unlocked
170420 14:55:19 [00] Compressing, encrypting and streaming ib_buffer_pool to <STDOUT>
170420 14:55:19 [00]        ...done
170420 14:55:19 Backup created in directory '/backups/mysql/Thusday/'
170420 14:55:19 [00] Compressing, encrypting and streaming backup-my.cnf
170420 14:55:19 [00]        ...done
170420 14:55:19 [00] Compressing, encrypting and streaming xtrabackup_info
170420 14:55:19 [00]        ...done
xtrabackup: Transaction log of lsn (2549956) to (2549965) was copied.
170420 14:55:19 completed OK!
```

If we look at the xtrabackup_checkpoints file, we can view information about the backup. While this file provides some information that is useful for administrators, it's mainly used by subsequent backup jobs so that they know what data has already been processed.

This is a copy of a file that's included in each archive. Even though this copy is overwritten with each backup to represent the latest information, each original will still be available inside the backup archive.

```
$ cat xtrabackup_checkpoints

backup_type = full-backuped
from_lsn = 0
to_lsn = 2549956
last_lsn = 2549965
compact = 0
recover_binlog_info = 0
```

The example above tells us that a full backup was taken and that the backup covers log sequence number (LSN) 0 to log sequence number 2549956. The last_lsn number indicates that some operations occurred during the backup process.

### Perform an Incremental Backup

Now that we have a full backup, we can take additional incremental backups. Incremental backups record the changes that have been made since the last backup was performed. The first incremental backup is based on a full backup and subsequent incremental backups are based on the previous incremental backup.

We should add some data to our database before taking another backup so that we can tell which backups have been applied.

Insert another record into the equipment table of our playground database representing 10 yellow swings. You will be prompted for the MySQL administrative password during this process.

Now that there is more current data than our most recent backup, we can take an incremental backup to capture the changes. The backup-mysql.sh script will take an incremental backup if a full backup for the same day exists:

```
$ backup-mysql.sh

Backup successful!
Backup created at /backups/mysql/Thu/incremental-2017-04-20_17-15-03.xbstream
```

Check the daily backup directory again to find the incremental backup archive:

```
$ cd /backups/mysql/"$(date +%a)"
$ ls

backup-progress.log                incremental-2017-04-20_17-15-03.xbstream  xtrabackup_info
full-2017-04-20_14-55-17.xbstream  xtrabackup_checkpoints
```

The contents of the xtrabackup_checkpoints file now refer to the most recent incremental backup:

```
$ cat xtrabackup_checkpoints

backup_type = incremental
from_lsn = 2549956
to_lsn = 2550159
last_lsn = 2550168
compact = 0
recover_binlog_info = 0
```

The backup type is listed as "incremental" and instead of starting from LSN 0 like our full backup, it starts at the LSN where our last backup ended.

### Extract the Backups

Next, let's extract the backup files to create backup directories. Due to space and security considerations, this should normally only be done when you are ready to restore the data.

We can extract the backups by passing the .xbstream backup files to the extract-mysql.sh script. Again, this must be run by the backup user:

```
$ extract-mysql.sh *.xbstream

Extraction complete! Backup directories have been extracted to the "restore" directory.

```

The above output indicates that the process was completed successfully. If we check the contents of the daily backup directory again, an extract-progress.log file and a restore directory have been created.

If we tail the extraction log, we can confirm that the latest backup was extracted successfully. The other backup success messages are displayed earlier in the file.



```
$ tail extract-progress.log

170420 17:23:32 [01] decrypting and decompressing ./performance_schema/socket_instances.frm.qp.xbcrypt
170420 17:23:32 [01] decrypting and decompressing ./performance_schema/events_waits_summary_by_user_by_event_name.frm.qp.xbcrypt
170420 17:23:32 [01] decrypting and decompressing ./performance_schema/status_by_user.frm.qp.xbcrypt
170420 17:23:32 [01] decrypting and decompressing ./performance_schema/replication_group_members.frm.qp.xbcrypt
170420 17:23:32 [01] decrypting and decompressing ./xtrabackup_logfile.qp.xbcrypt
170420 17:23:33 completed OK!


Finished work on incremental-2017-04-20_17-15-03.xbstream
```

If we move into the restore directory, directories corresponding with the backup files we extracted are now available:

```
$ cd restore
$ ls -F

full-2017-04-20_14-55-17/  incremental-2017-04-20_17-15-03/
```

The backup directories contains the raw backup files, but they are not yet in a state that MySQL can use though. To fix that, we need to prepare the files.

### Prepare the Final Backup

Next, we will prepare the backup files. To do so, you must be in the restore directory that contains the full- and any incremental- backups. The script will apply the changes from any incremental- directories onto the full- backup directory. Afterwards, it will apply the logs to create a consistent dataset that MySQL can use.

If for any reason you don't want to restore some of the changes, now is your last chance to remove those incremental backup directories from the restore directory (the incremental backup files will still be available in the parent directory). Any remaining incremental- directories within the current directory will be applied to the full- backup directory.

When you are ready, call the prepare-mysql.sh script. Again, make sure you are in the restore directory where your individual backup directories are located:

```
$ prepare-mysql.sh

Backup looks to be fully prepared.  Please check the "prepare-progress.log" file
to verify before continuing.

If everything looks correct, you can apply the restored files.

First, stop MySQL and move or remove the contents of the MySQL data directory:

        systemctl stop mysql
        mv /var/lib/mysql/ /tmp/

Then, recreate the data directory and  copy the backup files:

        mkdir /var/lib/mysql
        mariabackup --copy-back --target-dir=/backups/mysql/Thu/restore/full-2017-04-20_14-55-17

Afterward the files are copied, adjust the permissions and restart the service:

        chown -R mysql:mysql /var/lib/mysql
        find /var/lib/mysql -type d -exec chmod 750 {} \;
        systemctl start mysql
```

The output above indicates that the script thinks that the backup is fully prepared and that the full- backup now represents a fully consistent dataset. As the output states, you should check the prepare-progress.log file to confirm that no errors were reported during the process.

The script stops short of actually copying the files into MySQL's data directory so that you can verify that everything looks correct.

## Choose Full Restore / Partial Restore

### (Option 1) Full Restore - Restore the Backup Data to the MySQL Data Directory

If you are satisfied that everything is in order after reviewing the logs, you can follow the instructions outlined in the prepare-mysql.sh output.

First, stop the running MySQL process:

```
$ systemctl stop mysql
```

Since the backup data may conflict with the current contents of the MySQL data directory, we should remove or move the /var/lib/mysql directory. If you have space on your filesystem, the best option is to move the current contents to the /tmp directory or elsewhere in case something goes wrong:

```
$ mv /var/lib/mysql/ /tmp
```

Recreate an empty /var/lib/mysql directory. We will need to fix permissions in a moment, so we do not need to worry about that yet:

```
$ mkdir /var/lib/mysql
```

Now, we can copy the full backup to the MySQL data directory using the xtrabackup utility. Substitute the path to your prepared full backup in the command below:

```
mariabackup --copy-back --target-dir=/backups/mysql/Thu/restore/full-2017-04-20_14-55-17
```

A running log of the files being copied will display throughout the process. Once the files are in place, we need to fix the ownership and permissions again so that the MySQL user and group own and can access the restored structure:

```
$ chown -R mysql:mysql /var/lib/mysql
$ find /var/lib/mysql -type d -exec chmod 750 {} \;
``` 

Our restored files are now in the MySQL data directory.

Start up MySQL again to complete the process:

```
$ systemctl start mysql
```

After restoring your data, it is important to go back and delete the restore directory. Future incremental backups cannot be applied to the full backup once it has been prepared, so we should remove it. Furthermore, the backup directories should not be left unencrypted on disk for security reasons:

```
$ cd ~
$ rm -rf /backups/mysql/"$(date +%a)"/restore
```

The next time we need a clean copies of the backup directories, we can extract them again from the backup files.


### (Option 2) Partial Restore - Partially restore table(s) from prepared backup

- For partial restore, it is preferable to use the mariabackup "--export" option to generate .cfg/.exp files containing tablespace info. - This is currently performed automatically with the prepare-mysql.sh script.
- For more information about partial restoration, take a look at the <a href="https://mariadb.com/kb/en/library/partial-backup-and-restore-with-mariabackup/">Mariabackup documentation</a>.

Create a temporary database for importing partial tables:

```
mysql> CREATE DATABASE temporarydb;
```

Create an empty table based on the schema of the source and discard it's tablespace:
   
```   
mysql> CREATE TABLE table_name (
            column1 datatype,
            column2 datatype,
            column3 datatype,
            ....
        );

mysql> ALTER TABLE table_name DISCARD TABLESPACE;
```   

Stop MySQL and copy .ibd/.cfg/.exp files from the restore directory to the temporarydb folder (/var/lib/mysql/temporarydb) and assign the correct file permissions and ownership.

```
$ systemctl stop mysql
$ cp table_name.{ibd,cfg,exp} /var/lib/mysql/temporarydb/
$ chown mysql:mysql /var/lib/mysql/temporarydb/*
```

Start MySQL and import tablespace for restored table(s)

```
$ systemctl start mysql
```

```
mysql> USE temporarydb;
mysql> ALTER TABLE table_name IMPORT TABLESPACE;     
```
This will take some time depending on the size of your data. Once completed, verify that your data is restored and use the data necessitated.

## Creating a Cron Job to Run Backups Hourly

Now that we've verified that the backup and restore process are working smoothly, we should set up a cron job to automatically take regular backups.

We will create a small script within the /etc/cron.hourly directory to automatically run our backup script and log the results. The cron process will automatically run this every hour:

```
$ nano /etc/cron.hourly/backup-mysql
```

Inside, we will call the backup script with the systemd-cat utility so that the output will be available in the journal. We'll mark them with a backup-mysql identifier so we can easily filter the logs:

```
#!/bin/bash
systemd-cat --identifier=backup-mysql /usr/local/bin/backup-mysql.sh
```

Save and close the file when you are finished. Make the script executable by typing:

```
$ chmod +x /etc/cron.hourly/backup-mysql
```

The backup script will now run hourly. The script itself will take care of cleaning up backups older than three days ago.

We can test the cron script by running it manually:

```
/etc/cron.hourly/backup-mysql
```

After it completes, check the journal for the log messages by typing:

```
$ journalctl -t backup-mysql

-- Logs begin at Wed 2017-04-19 18:59:23 UTC, end at Thu 2017-04-20 18:54:49 UTC. --
Apr 20 18:35:07 myserver backup-mysql[2302]: Backup successful!
Apr 20 18:35:07 myserver backup-mysql[2302]: Backup created at /backups/mysql/Thu/incremental-2017-04-20_18-35-05.xbstream
```

Check back in a few hours to make sure that additional backups are being taken.
