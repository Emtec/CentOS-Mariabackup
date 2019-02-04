#!/bin/bash

export LC_ALL=C

shopt -s nullglob
incremental_dirs=( ./incremental-*/ )
full_dirs=( ./full-*/ )
shopt -u nullglob

#backup_owner="backup"
log_file="prepare-progress.log"
full_backup_dir="${full_dirs[0]}"

# Use this to echo to standard error
error() {
    printf "%s: %s\n" "$(basename "${BASH_SOURCE}")" "${1}" >&2
    exit 1
}

trap 'error "An unexpected error occurred.  Try checking the \"${log_file}\" file for more information."' ERR

sanity_check () {
    # Check user running the script
    if [[ -n "${backup_owner}" && "${USER}" != "${backup_owner}" ]]; then
        error "Script can only be run as the \"${backup_owner}\" user."
    fi

    # Check whether a single full backup directory are available
    if (( ${#full_dirs[@]} != 1 )); then
        error "Exactly one full backup directory is required."
    fi
}

do_prepare () {
    # Apply the logs to each of the backups
    printf "Initial prep of full backup %s\n" "${full_backup_dir}"
    mariabackup --prepare --apply-log-only --target-dir="${full_backup_dir}"
    
    for increment in "${incremental_dirs[@]}"; do
        printf "Applying incremental backup %s to %s\n" "${increment}" "${full_backup_dir}"
        mariabackup --prepare --apply-log-only --incremental-dir="${increment}" --target-dir="${full_backup_dir}"
    done
    
    # (Optional) Create .cfg/.exp for InnoDB file-per-table tablespace
    printf "Prepare final backup with --export option (>= MariaDB 10.2.9) %s\n" "${full_backup_dir}"
    mariabackup --prepare --export --target-dir="${full_backup_dir}"
}

sanity_check && do_prepare > "${log_file}" 2>&1

# Check the number of reported completions.  Each time a backup is processed,
# an informational "completed OK" and a real version is printed.  At the end of
# the process, a final full apply is performed, generating another 2 messages.
ok_count="$(grep -c 'completed OK' "${log_file}")"

if (( ${ok_count} == ${#full_dirs[@]} + ${#incremental_dirs[@]} )); then
    cat << EOF
Backup looks to be fully prepared.  Please check the "prepare-progress.log" file
to verify before continuing.

If everything looks correct, you can apply the restored files.

##############################################################################
# FULL RESTORE
##############################################################################
First, stop MySQL and move or remove the contents of the MySQL data directory:
    
        $ sudo systemctl stop mysql
        $ sudo mv /var/lib/mysql/ /tmp/
    
Then, recreate the data directory and  copy the backup files:
    
        $ sudo mkdir /var/lib/mysql
        $ sudo mariabackup --copy-back ${PWD}/$(basename "${full_backup_dir}")
    
Afterward the files are copied, adjust the permissions and restart the service:
    
        $ sudo chown -R mysql:mysql /var/lib/mysql
        $ sudo find /var/lib/mysql -type d -exec chmod 750 {} \\;
        $ sudo systemctl start mysql
        
##############################################################################
# PARTIAL RESTORE
##############################################################################        
Create a temporary database for importing partial tables:

        CREATE DATABASE temporarydb;

Create an empty table based on the schema of the source and discard it's tablespace:
        
        CREATE TABLE table_name (
            column1 datatype,
            column2 datatype,
            column3 datatype,
            ....
        );
        
        ALTER TABLE table_name DISCARD TABLESPACE;
        
Stop MySQL and copy .ibd/.cfg/.exp files from the restore directory to the temporarydb folder (/var/lib/mysql/temporarydb) and assign the correct permissions and ownership.

        $ sudo systemctl stop mysql

        $ sudo cp table_name.idb /var/lib/mysql/temporarydb/
        $ sudo cp table_name.cfg /var/lib/mysql/temporarydb/
        $ sudo cp table_name.exp /var/lib/mysql/temporarydb/
        
        $ sudo chown mysql:mysql /var/lib/mysql/temporarydb/*
        
Start MySQL and import tablespace for restored table(s)

        $ sudo systemctl start mysql
        
        USE temporarydb;
        ALTER TABLE table_name IMPORT TABLESPACE;               

EOF
else
    error "It looks like something went wrong.  Check the \"${log_file}\" file for more information."
fi
