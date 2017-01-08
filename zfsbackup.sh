#!/bin/bash -e
# zfsbackup - Jonathan Chan <jonmchan@gmail.com>
#
# ZFSBackup is a remote backup management utility that utilizes the power of
# zfs send/receive along with other utils to provide a complete remote backup
# solution. 
#
# Feature List:
#   * Simple intuitive interface - zfsbackup backup, zfsbackup restore rpool; done.
#   * Supports backup retention expiration dates - automatically delete snapshots
#     and set full backups to be run after a certain interval
#   * GPG Encryption of all remote data, allowing backups to be stored anywhere,
#     even on insecure internet locations.
#   * Account for transport errors and provide for some means of repairing
#     the remote backup system (Partial support - I am sure I will find more errors when in use)
#   * Monitoring and validation of backup sets (utilizing md5). Works quickly and efficiently
#     without transferring any data on the network utilizing the remote computer to check
#     checksum!
#   * Email status reports (still need to make this more robust and clear).
#
# Requirements:
# This script was built on a solaris system, but any system with the following
# software should work:
#
# * ZFS File System with the standard zfs utility
# * GNU coreutils - cat, tee, md5sum, etc.
# * gnupg 1.x branch - on solaris, you can get this from the CSW repository
# * sqlite3
# * sendmail - make sure it works
#
# You will also need a remote system that supports ssh remote commands (cat and md5sum) and that 
# has plenty of space. Minimally, you must have n+1 * Size of File System where n is the number 
# of full backups you want to keep. The reason this is true is that the system creates a new full
# backup first and makes sure that works before it deletes the old full backup. 
#
# Wishlist:
#   * CODE CLEANUP! It is very messy after several late night code sprints.
#   * Check if executables exist for all programs used and check if remote directory exists and 
#     make it if it doesn't
#   * Allow pre and post scripts to be run
#   * Compression of remote data with gzip 
#   * External conf file with multiple conf file support
#   * Account for manual edits from the zfs commandline
#   * Change md5sum tmpfile to pipes or something more intelligent
#
# ChangeLog:
# Sat, 28 Aug 2010 23:22:51 -0400
# * First public release
# * Added a help
# * Added cronjob (same as backup, but emails all output and adds status report)
# * Finished repair code
#
# Thu, 26 Aug 2010 13:32:40 -0400
# * Changed system db layout to key -> value
# * Fixed db layout
# * Added different list views
# * Implemented incremental backup
# * Implemented some of the repair code and error/incomplete checking
# * Implemented retention expiration dates
#
# Wed, 25 Aug 2010 19:19:37 -0400 
# * Initial development.
# * skeletoning system
# * Implemented full backup, and restore - still need to create incremental backup


## Config Section - Edit ME! ##

# Filename prefix for all backup files.
ZFSPREFIX=backup

# Volume to run the backup on 
#  ZFSVOLUME=rpool/storage

# Email address of administrator
ZFSADMIN=youremail@yourhost.com

# ssh login for remote server (either hostname or username@hostname)
SSHLOGIN=remoteuser@remostbackup
USESFTP=true

# Local path to folder to keep config files (You must create this directory)
CONFDIR=/home/user/zfsbackup

# Remote Server Path for Backup (You must also create this directory)
REMOTEPATH=/home/jonathan/test

## Retention Policy ##
# number of full backups kept on remote location
ZFSREMOTEFULL=1

# how often should we make a full backup?
ZFSFULLEXPIRATION="365 days"

# how long should snapshots be kept on the local server?
ZFSSNAPSHOTEXPIRATION="30 days"

# how often should we check if the files on the remote server is not corrupt?
# Comment this out to disable automated remote verify
# (you can still run this command with zfsbackup verify)
ZFSVERIFYREMOTE="7 days"

# if you're not on solaris or if you're using sudo or su, change this.
ZFSBIN="pfexec zfs" 
GPGBIN="gpg"
SSHBIN="ssh"

LOCALMD5="md5 -q"
REMOTEMD5="md5sum -b"

# If you would like to customize the email sent to you, you can add other
# commands here such as `date` or `zpool status` or anything else pertinent
function status-email {
cat << EOF|sendmail $ZFSADMIN
Subject: zfsbackup $ZFSVOLUME report
==========================
`date -R`
==========================
$1

==========================
Current Backups:
==========================
`zfs-list`

==========================
ZFS Pool Status:
==========================
`zpool status`
EOF

}

## Config Section End - No more edits! ##


SSHKEY="$CONFDIR/${ZFSPREFIX}_id_rsa"

# TODO add ZFSVOLUME
REMOTEFILENAME='$REMOTEPATH/$SNAPSHOTNAME.zfs.gpg'

## commands - DO NOT EDIT UNLESS YOU KNOW WHAT YOU'RE DOING! ## 
# Commands to pipe from/to - Change this to add compression or different
# encryption algorithms, but verify it works or else all your backups will
# be destroyed! You definitely cannot change this once you started making
# backups; the schemes will be different.
# Do not touch this unless you really know what you're doing!
function ZFSSENDFULLCMD {
$ZFSBIN send -R ${ZFSVOLUME}@${SNAPSHOTNAME}|$GPGCMD --encrypt -r $GPGEMAIL | tee >($LOCALMD5 > md5sum.tmp) |
if [ "X$USESFTP" == "X" ]; then
	$SSHBIN -i $SSHKEY $SSHLOGIN bash -c "cat > '`eval echo $REMOTEFILENAME|sed 's/://g'`'"
else
	curl --key $SSHKEY --pubkey $SSHKEY.pub -T - "sftp://$SSHLOGIN/`eval echo $REMOTEFILENAME|sed 's/://g'`"
fi
}
function ZFSSENDINCREMENTALCMD {
$ZFSBIN send -RI ${ZFSVOLUME}@${LASTSNAPSHOTDATE} ${ZFSVOLUME}@${SNAPSHOTNAME} |$GPGCMD --encrypt -r $GPGEMAIL | tee >($LOCALMD5 > md5sum.tmp) | 
if [ "X$USESFTP" == "X" ]; then
	$SSHBIN -i $SSHKEY $SSHLOGIN bash -c "cat > '`eval echo $REMOTEFILENAME|sed 's/://g'`'"
else
	curl --key $SSHKEY --pubkey $SSHKEY.pub -T - "sftp://$SSHLOGIN/`eval echo $REMOTEFILENAME|sed 's/://g'`"  
fi
}
function ZFSRECEIVECMD {
if [ "X$USESFTP" == "X" ]; then
	$SSHBIN -i $SSHKEY $SSHLOGIN "cat `eval echo $REMOTEFILENAME|sed 's/://g'`" 
else
	curl --key $SSHKEY --pubkey $SSHKEY.pub "sftp://$SSHLOGIN/`eval echo $REMOTEFILENAME|sed 's/://g'`" 
fi |
$GPGCMD --passphrase-file <(eval echo $GPGPASSWORD) --decrypt --secret-keyring $GPGSECKEY  | $ZFSBIN receive -F -d $1
}
function ZFSRMCMD {
if [ "X$USESFTP" == "X" ]; then
	$SSHBIN -i $SSHKEY $SSHLOGIN "rm `eval echo $REMOTEFILENAME|sed 's/://g'`"
else
	echo "rm `eval echo $REMOTEFILENAME|sed 's/://g'`" | sftp -i $SSHKEY $SSHLOGIN
fi
}
function ZFSMD5CMD {
if [ "X$USESFTP" == "X" ]; then
	$SSHBIN -i $SSHKEY $SSHLOGIN "$REMOTEMD5 `eval echo $REMOTEFILENAME|sed 's/://g'`" |awk '// { print $1 }'
else
	curl --key $SSHKEY --pubkey $SSHKEY.pub "sftp://$SSHLOGIN/`eval echo $REMOTEFILENAME|sed 's/://g'`" | $LOCALMD5
fi 
}

GPGCMD="$GPGBIN --no-default-keyring --keyring $CONFDIR/$ZFSPREFIX.pub"

## Code Section ##
ZFSDB=$CONFDIR/${ZFSPREFIX}.db
ZFSPID=$CONFDIR/${ZFSPREFIX}.pid
export GNUPGHOME=$CONFDIR
GPGPUBKEY=$CONFDIR/$ZFSPREFIX.pub
GPGSECKEY=$CONFDIR/$ZFSPREFIX.sec
DB="sqlite3 $ZFSDB"

# init - sqlite and gpg
function zfs-init {
  if [ -e "$ZFSDB" ] || [ -e "$GPGPUBKEY" ]; then
    echo "ZFS Backup has already been initialized. If you want to start over again, please delete"
    echo "$ZFSDB and $GPGPUBKEY, but note that your backups will not be able to be restored"
    echo "after you do this."
    exit
  fi
  echo "Initializing zfsbackup..."
  echo "Generating GPG Keys..."
  echo "Note: Make sure you specify your key to never expire!"
  ($GPGCMD --secret-keyring $GPGSECKEY --gen-key)||true
  echo "Keys created!"
  echo "Creating Status DB..."
  $DB "CREATE TABLE system (Key TEXT, Value TEXT);"
  $DB "INSERT INTO system VALUES ('Version', '2');"
  $DB "INSERT INTO system VALUES ('lastverify',null)"
  $DB "CREATE TABLE status (Date TIMESTAMP, Status TEXT, LocalSnapshot INTEGER, Type TEXT, Hash BLOB, ErrorDesc TEXT, SnapshotName TEXT, Volume Text );"
  echo "Done!"
  echo
  echo "IMPORTANT NOTICE:"
  echo "Please backup $GPGSECKEY - if this file is lost, you will have NO way"
  echo "of restoring your backups. If you are extremely paranoid, remove $GPGSECKEY"
  echo "and store in a secure location. If security is not too much of an issue for"
  echo "you, you may store the file on the remote storage along with your backup files"
  echo "granted that you have a good password (you have a good password right?)."
  echo
  echo "Again, let me repeat. PLEASE KEEP $GPGSECKEY IN A SAFE LOCATION."
  echo
  echo "Creating ssh-key"
  ssh-keygen -f $SSHKEY -C "zfsbackup ssh key"
  echo "Add this to your authorized_keys on the server"
  if [ "X$USESFTP" == "X" ]; then
	ssh-keygen -f $SSHKEY -y 
  else
	ssh-keygen -f $SSHKEY -y -e | grep -v ^Comment:
  fi
}

function zfs-resume {
  check-if-running
  echo $$ > $ZFSPID
  VOLSNAP=`$DB "SELECT Volume || '@' || SnapshotName FROM status WHERE Status='Incomplete' LIMIT 1"`
  if [ "$VOLSNAP" == '' ]; then
    echo "There are no incomplete backups to resume."
  else
    TYPE=`$DB "SELECT Type FROM status WHERE Status='Incomplete' AND Volume || '@' || SnapshotName ='$VOLSNAP'"`
    echo "$VOLSNAP was interrupted, resuming $TYPE backup..."
    zfs-send-backup $VOLSNAP
    echo "$VOLSNAP backup successfully completed."
  fi
  rm $ZFSPID
}

# calls ZFSSEND* commands and handles the backup after the snapshot was created
# Create the snapshot and place update the db then pass the $DATE to $1
function zfs-send-backup {
  gpg-setemail
  TYPE=`$DB "SELECT Type FROM status WHERE Volume || '@' || SnapshotName = '$1'"`
  DATE=`$DB "SELECT Date FROM status WHERE Volume || '@' || SnapshotName = '$1'"`
  VOLSNAP=$1
  if [ "$TYPE" == 'Full' ]; then
    ZFSSENDFULLCMD
  elif [ "$TYPE" == 'Incremental' ]; then
    LASTSNAPSHOTDATE=`$DB "SELECT date FROM status WHERE datetime(date) < datetime('$DATE') AND Status='Complete' AND LocalSnapshot=1 AND Volume='$ZFSVOLUME' ORDER BY Date DESC LIMIT 1;"`
    if [ "$LASTSNAPSHOTDATE" == '' ]; then
      echo "Reference local snapshot does not exist anymore to be able to make incremental backup."
      echo "Falling back to full backup."
      ZFSSENDFULLCMD
    else
      ZFSSENDINCREMENTALCMD
    fi
  else
    echo "ERROR: $DATE does not exist or the DB is corrupt/missing Type field."
    exit 1
  fi
  $DB "UPDATE status SET Status='Complete',Hash='`awk '// { print $1 }' md5sum.tmp`',ErrorDesc=null WHERE Volume || '@' || SnapshotName = '$VOLSNAP'"
  rm md5sum.tmp
}

function zfs-remove-backup {
  DATE=$1
  EXISTS=`$DB "SELECT COUNT(*) FROM status WHERE Date='$1'"`
  if [ $EXISTS -eq 0 ]; then
    echo "ERROR: $DATE does not exist or the DB is corrupt/missing Type field."
    exit 1
  fi
  ZFSRMCMD
  $DB "UPDATE status Set Status='Removed' WHERE Date='$1' AND Volume='$ZFSVOLUME'"
}

# main backup code
function zfs-backup {
  check-installed
  check-if-running
  if check-for-errors; then
    echo "One or more backup sets have failed checksum test and have been marked as "
    echo "corrupted. Please look into the issue ASAP. Backups will NOT run until"
    echo " this has been resolved. ($0 verify / $0 repair)"
    exit
  fi
  if check-for-incomplete; then
    zfs-resume
    echo "Resuming current backup job."
  fi
  echo "Starting backup..."
  echo $$ > $ZFSPID
  $DB "INSERT INTO status VALUES (strftime('%Y-%m-%dT%H:%M:%S',current_timestamp),'Phantom',0,null,null,'Died before snapshot made...', '$ZFSPREFIX-' || strftime('%Y-%m-%dT%H:%M:%S',current_timestamp), '$ZFSVOLUME');"
  DATE=`$DB "SELECT date FROM status ORDER BY date DESC LIMIT 1"`
  echo "Creating new snapshot..."
  $ZFSBIN snapshot -r ${ZFSVOLUME}@${DATE}
  if [ "$1" == 'force-full' ] || check-backup-type; then
    BACKUPTYPE=Full
    $DB "UPDATE status SET Status='Incomplete',LocalSnapshot=1,Type='Full',ErrorDesc='Sending snapshot...' WHERE date='$DATE' AND Volume='$ZFSVOLUME'"
    zfs-send-backup $DATE
    echo "Full Backup Complete."
  else
    BACKUPTYPE=Incremental
    $DB "UPDATE status SET Status='Incomplete',LocalSnapshot=1,Type='Incremental',ErrorDesc='Sending snapshot...' WHERE date='$DATE' AND Volume='$ZFSVOLUME'"
    zfs-send-backup $DATE
    echo "Incremental Backup Complete."
  fi
  rm $ZFSPID
  if [ "$ZFSVERIFYREMOTE" != '' ]; then
    LASTVERIFY=`$DB "SELECT value FROM system WHERE key='lastverify' AND datetime(value)>datetime(current_timestamp,'-$ZFSVERIFYREMOTE');"`
    if [ "$LASTVERIFY" == '' ]; then
      echo "Verification of remote files has never been run or it has been more "
      echo "than $ZFSVERIFYREMOTE since last verification run, verifying now." 
      zfs-verify
      $DB "UPDATE system SET value=current_timestamp WHERE key='lastverify';"
    else
      echo "Skipping remote data verification because the last verification ($LASTVERIFY)"
      echo "is not more than $ZFSVERIFYREMOTE old."
    fi 
  fi
  expire-local-snapshots
  echo "Job complete."
}

# main restore code - the volume must exist to restore to, restore does not create the volume.
# add this to the readme, but something like tank/restore has to exist before using restore
# do a zfs create tank/restore or a ./zfsbackup restore tank
function zfs-restore {
  if check-for-errors; then
    echo "There are errors within the remote backup set that must be resolved. You may not"
    echo "restore any backups until these issues are resolved ($0 repair)."
    exit
  fi
  if [ -r  "$GPGPUBKEY" ] && [ -r "$GPGSECKEY" ] ; then
    NOTHING=TODO
    # replace this with a valid ! if statement
  else
    echo "ERROR: Could not access the GPG key files. Please make sure that $GPGPUBKEY"
    echo "and $GPGSECKEY are available and readable."
    exit
  fi
  if ! [ "$1" ]; then
    zfs-help
    exit
  fi
  if ! [ "$2" ]; then
    DATE=`$DB "SELECT date FROM status WHERE Status='Complete' ORDER BY date DESC LIMIT 1"`
  else
    DATE=$2
  fi
  fetch-backup-set $DATE
  if [ "$BACKUPSET" == '' ]; then
    echo "There are no backups to restore or there are no backups matching the date you passed!"
    exit
  fi
  echo "We will be restoring the following backup sets:"
  for i in $BACKUPSET; do VAR+="'$i',"; done
  sqlite3 --header --column $ZFSDB "SELECT Date, Status,LocalSnapshot,Type,ErrorDesc as 'Error Description' FROM status WHERE Date IN (${VAR%?}) AND Status='Complete' ORDER BY Date ASC;"
  echo "Is this ok? [Y|n] "
  read ANSWER
  if [ "${ANSWER:0:1}" == 'n' ]; then
    echo "You selected no, ok. bye bye."
    exit
  fi
  echo "Please enter your GPG key passphrase (If you have an empty password, just press enter): "
  stty -echo
  read GPGPASSWORD
  stty echo
  for DATE in $BACKUPSET; do
    echo "Restoring $DATE snapshot..."
    ZFSRECEIVECMD $1
  done
  echo "Done restoring $ZFSPREFIX backup sets to $1."

}

function zfs-list {
  check-installed
case "$1" in
all) WHERE="" ;;
errors) WHERE="WHERE Status = 'Incomplete' OR Status = 'Error'";;
history) WHERE="WHERE Status = 'Complete' OR Status = 'Removed'";;
valid) WHERE="WHERE Status = 'Complete'";;
*) WHERE="WHERE Status != 'Removed'";;
esac
  sqlite3 --header --column $ZFSDB "SELECT Date, Status,LocalSnapshot,Type,ErrorDesc as 'Error Description' FROM status $WHERE"
  exit
}

function zfs-help {
cat << EOF  
Usage: $0 command [option]

Commands:

backup            Creates a zfs snapshot and sends it to a remote location
cronjob           Same as backup, but suppressed output and emails you a report
list              Displays information on backups
  [all|errors|history|valid] 
init              Initializes zfsbackup system, setting up the gpg keys and db
repair            Fixes corrupt backups by restoring from local snapshot
  [destructive]   Fixes corrupt backups by deleting corrupt files
  [phantom]       Deletes phantom (invalid with no snapshot) backup records
  [hardreset]     (TESTING FUNCTION) Delete all snapshots and backups
                  remotely and locally
  [hardresetdb]   (TESTING FUNCTION) Resets database (without cleaning 
                  snapshots or backups)
restore           Restores backup to FILESYSTEM from DATE or latest backup set
  FILESYSTEM [DATE]
resume            Resumes a failed or interrupted backup
test-email        Sends a test email to make sure sendmail works
verify            Verify integrity of remote backup files

EOF
check-installed
}


function zfs-verify {
  echo "Verifying all remote backups..."
  VERIFYSET=`$DB "SELECT Date FROM status WHERE status ='Complete' OR status ='Error'"`
  for DATE in $VERIFYSET; do
    echo -n "Verifying $DATE..."
    MD5SUM=`ZFSMD5CMD`
    VERIFIED=`$DB "SELECT COUNT(*) FROM status WHERE Date='$DATE' AND Hash='$MD5SUM'"`
    if [ $VERIFIED -eq 1 ]; then
      echo " VERIFIED - MD5 Checksum Passed!"
      $DB "UPDATE status SET Status='Complete',ErrorDesc=null WHERE Date='$DATE' AND Volume='$ZFSVOLUME'"
    else
      $DB "UPDATE status SET Status='Error',ErrorDesc='MD5 Checksum Failed!' WHERE Date='$DATE' AND Volume='$ZFSVOLUME'"
      echo " FAILED - MD5 Checksum Failed!"
    fi
  done
}

# note, before running this, if all your backup sets have been set into an error state, try to run a verify first.
function zfs-repair {
  case "$1" in
  phantom)
    echo "Cleaning up phantom record(s) from DB."
    $DB "DELETE FROM Status WHERE Status='Phantom';"
  ;;
  hardresetdb)
    echo "ARE YOU SURE YOU WANT TO DO THIS? YOUR BACKUPS WILL BE MADE "
    echo "INACCESSIBLE. (this is function was written primarily for testing)"
    echo "[y|n] (default n)"
    read ANSWER
    if [ "${ANSWER:0:1}" == 'y' ]; then
      $DB "DELETE FROM Status;"
      echo "Database reset - Neither local snapshots were deleted or remote files."
      echo "You have to clean this up yourself."
    fi
  ;;
  hardreset)
    echo "This will delete ALL your backups and reset the status DB. This action is undoable"
    echo "and ALL your backups and snapshots (both locally and remotely) will be DELETED."
    echo
    echo "Are you sure you want to do this? [y|N]"
    read ANSWER
    if [ "${ANSWER:0:1}" == 'y' ]; then
      EXPIREDSNAPSHOTS=`$DB "SELECT Date FROM status WHERE LocalSnapshot=1"`
      for i in $EXPIREDSNAPSHOTS; do
        echo "Removing local snapshot: $i"
        $ZFSBIN destroy $ZFSVOLUME@$i
        echo "Removing remote backup: $i"
        zfs-remove-backup $i
      done
      echo "Resetting database..."
      $DB "DELETE FROM Status;"
      $DB "UPDATE System SET Value=null WHERE Key='lastverify';"
      echo "ZFSBackup System Reset!"
    fi
  ;;
  destructive)
    echo "This command will delete corrupted backup files and whatever incremental snapshots they have"
    echo "affected. Only use this command if you do not have any other options."
    echo 
    echo -n "Are you sure you want to continue? [y|N]"
    read ANSWER
    if [ "${ANSWER:0:1}" != 'y' ]; then
      exit
    fi
    echo "Alright, removing corrupt files..."
    while check-for-errors; do
      ERRORDATE=`$DB "SELECT Date FROM status WHERE status='Error' LIMIT 1"`
      fetch-newestbackup-set $ERRORDATE
      for i in $BACKUPSET; do
        echo "Removing $i backup..."
        zfs-remove-backup $i
      done
    done
    echo "Backup datasets scrubbed, $0 should be fully operational now."
  ;;
  *)
    if ! check-for-errors; then
      echo "There are no errors to repair."
      exit
    fi
    echo "Found errors and attempting to repair them by restoring from local snapshot..."
    REPAIRSET=`$DB "SELECT DATE FROM status WHERE status='Error' AND LocalSnapshot=1"`
    for i in $REPAIRSET; do
      echo "Repairing $i..."
      zfs-send-backup $i
      echo "Remote backup snapshot repaired!"
    done
    if check-for-errors; then
      zfs-list errors
      echo "The above backup sets were not able to be restored because no local snapshots available to restore"
      echo "them from. Either fix them manually or run '$0 repair destructive' to delete the corrupt backupset."
    else
      echo "All errors repaired! Backups may be resumed!"
    fi
  ;;
esac
}
 
# fetches a backup set from the first full backup to the current state. Returns to $BACKUPSET
function fetch-backup-set {
  LASTFULL=`$DB "SELECT Date FROM status WHERE datetime(replace(date,'$ZFSPREFIX-','')) <= DATETIME(replace('$1','$ZFSPREFIX-','')) AND Type ='Full' ORDER BY Date DESC LIMIT 1;"`
  BACKUPSET=`$DB "SELECT Date FROM status WHERE datetime(replace(date,'$ZFSPREFIX-','')) BETWEEN DATETIME(replace('$LASTFULL','$ZFSPREFIX-','')) AND DATETIME(replace('$1','$ZFSPREFIX-','')) AND status='Complete';"`
}

# fetches the full backup set that this backup is in. Returns to $BACKUPSET
function fetch-fullbackup-set {
  LASTFULL=`$DB "SELECT Date FROM status WHERE datetime(replace(date,'$ZFSPREFIX-','')) <= DATETIME(replace('$1','$Z    FSPREFIX-','')) AND Type ='Full' ORDER BY Date DESC LIMIT 1;"`
  NEXTFULL=`$DB "SELECT Date FROM status WHERE datetime(replace(date,'$ZFSPREFIX-','')) > DATETIME(replace('$LASTFULL','$ZFSPREFIX-','')) AND Type='Full' ORDER BY Date ASC LIMIT 1;"`
  if [ "$NEXTFULL" == '' ]; then
    BACKUPSET=`$DB "SELECT Date FROM status WHERE datetime(replace(date,'$ZFSPREFIX-','')) >= DATETIME(replace('$LASTFULL','$ZFSPREFIX-',''));"`
  else    
    BACKUPSET=`$DB "SELECT Date FROM status WHERE datetime(replace(date,'$ZFSPREFIX-','')) >= DATETIME(replace('$LASTFULL','$ZFSPREFIX-','')) AND datetime(replace(date,'$ZFSPREFIX-','')) < DATETIME(replace('$NEXTFULL','$ZFSPREFIX-',''));"`
  fi
}

# fetches the current and future backup set that this backup is in. Returns to $BACKUPSET
function fetch-newestbackup-set {
  LASTFULL=`$DB "SELECT Date FROM status WHERE datetime(replace(date,'$ZFSPREFIX-','')) <= DATETIME(replace('$1','$ZFSPREFIX-','')) AND Type ='Full' ORDER BY Date DESC LIMIT 1;"`
  NEXTFULL=`$DB "SELECT Date FROM status WHERE datetime(replace(date,'$ZFSPREFIX-','')) > DATETIME(replace('$LASTFULL','$ZFSPREFIX-','')) AND Type='Full' ORDER BY Date ASC LIMIT 1;"`
  if [ "$NEXTFULL" == '' ]; then
    BACKUPSET=`$DB "SELECT Date FROM status WHERE datetime(replace(date,'$ZFSPREFIX-','')) >= DATETIME(replace('$1','$ZFSPREFIX-',''));"`
  else   
    BACKUPSET=`$DB "SELECT Date FROM status WHERE datetime(replace(date,'$ZFSPREFIX-','')) >= DATETIME('$1') AND DATETIME(Date) < DATETIME(replace('$NEXTFULL','$ZFSPREFIX-',''));"`
  fi
}

# check if there is any error backup sessions
function check-for-errors {
  ERRORS=`$DB "SELECT COUNT(*) FROM status WHERE Status='Error'"`
  if [ $ERRORS -gt 0 ]; then
    return 0
  else
    return 1 
  fi 
}

function check-for-incomplete {
  ERRORS=`$DB "SELECT COUNT(*) FROM status WHERE Status='Incomplete'"`
  if [ $ERRORS -gt 0 ]; then
    return 0
  else
    return 1
  fi 
}


function check-if-running {
  if [ "$ICHECKEDALREADY" == 1 ]; then
    return
  else 
    ICHECKEDALREADY=1
  fi
  if [ -e $ZFSPID ]; then
    pid=`cat $ZFSPID`
    if kill -0 $pid > /dev/null 2>&1; then
      echo "Another instance of $0 is running, quitting."
      echo "DEV NOTE: Add email here to let admin know the frequency of backups is perhaps too frequent."
      exit
    else 
      echo "Stale lockfile, uh oh... looks like $0 did not shutdown cleanly?"
    fi
  fi
}

# check if a full backup or incremental backup is due (0 - full, 1 - incremental)
function check-backup-type {
OUTPUT=`$DB "SELECT Date FROM status WHERE status='Complete' AND Type = 'Full' and datetime(replace(date,'$ZFSPREFIX-','')) > datetime(current_timestamp, '-$ZFSFULLEXPIRATION') ORDER BY Date DESC LIMIT 1"`
if [ "$OUTPUT" ]; then
  echo "Our last full backup was $OUTPUT - running incremental backup."
  return 1 
else
  echo "We have never had a backup or our last backup was over $ZFSFULLEXPIRATION - running full backup."
  return 0 
fi
}

function expire-local-snapshots {
EXPIREDSNAPSHOTS=`$DB "SELECT Date FROM status WHERE datetime(replace(date,'$ZFSPREFIX-','')) < datetime(current_timestamp, '-$ZFSSNAPSHOTEXPIRATION') AND LocalSnapshot=1"`
for i in $EXPIREDSNAPSHOTS; do
  echo "$i has passed the $ZFSSNAPSHOTEXPIRATION retention period for local snapshots, removing local snapshot."
  $ZFSBIN destroy $ZFSVOLUME@$i
  $DB "UPDATE Status SET LocalSnapshot=0 WHERE Date='$i' AND Volume='$ZFSVOLUME'"
done
}

function gpg-setemail {
   if ! [ -r "$GPGPUBKEY" ] ; then
     echo "ERROR: The GPG public key '$GPGPUBKEY' is missing. Cannot run."
     exit
   fi
   GPGEMAIL=`$GPGCMD --list-keys|grep -o "<.*>"|sed 's/[<>]//g'`
}

# check if zfsbackup is installed
function check-installed {
  if [ -r "$ZFSDB" ] ; then 
    ver=`$DB "SELECT Value FROM system WHERE Key='Version'" 2> /dev/null||echo -1`
  else 
    ver=-1
  fi
  if [ "$ver" -lt 1 ]; then 
    echo
    echo "Notice:"
    echo "ZFSBackup is not configured yet. ZFSBackup must be configured in order to run."
    echo "Please check the source and edit the configuration variables first, then run"
    echo "$0 init." 
    echo
    exit
  fi
}

case "$1" in
init) zfs-init ;;
backup) zfs-backup $2 $3 $4;;
cronjob) status-email "`zfs-backup $2 $3 $4`";;
test-email) status-email "This is a test email to see if $0 can send email.";;
resume) zfs-resume;;
restore) zfs-restore $2 $3 $4;;
list) zfs-list $2;;
verify) zfs-verify ;; 
repair) zfs-repair $2 $3 $4 ;;
*) zfs-help ;;
esac
