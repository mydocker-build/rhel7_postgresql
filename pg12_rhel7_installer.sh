#!/bin/bash
# Settins here
PG_ADMPWD=P@ssw0rd#1
PG_DATA=/srv/pgdata
PG_PORT=5342
PG_NETALLOW=192.168.43.0/24

echo "Install PostgreSQL yum repository (latest version)..............."
yum -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm

echo "Install the PostgreSQL client/server packages...................."
yum -y install postgresql12 postgresql12-server pgaudit14_12 policycoreutils-python

echo "Set PGDATA with specific path from variable......................"
cat > /etc/profile.d/pgenv.sh <<EOF
# PostgreSQL Data Path
export PGDATA=$PG_DATA
export PGPORT=$PG_PORT
EOF
chown root:root /etc/profile.d/pgenv.sh
chmod +x /etc/profile.d/pgenv.sh
source ~/.bashrc
sed -i "s@^Environment=PGDATA=.*@Environment=PGDATA=$PGDATA@" /usr/lib/systemd/system/postgresql*.service
sed -i "s@^PGDATA=.*@PGDATA=$PGDATA@" /var/lib/pgsql/.bash_profile
systemctl daemon-reload

echo "Create PGDATA directory.........................................."
mkdir -p $PGDATA
chown -R postgres:postgres $PGDATA
chmod o-rwx $PGDATA
semanage fcontext -a -t postgresql_db_t "$PGDATA(/.*)?"
restorecon -Rv $PGDATA

echo "First initialize the PostgreSQL database server after install....."
PGSETUP_INITDB_OPTIONS="-k" /usr/pgsql-12/bin/postgresql-12-setup initdb

echo "Enable auto startup and start PostgreSQL service................."
systemctl enable postgresql-12 && systemctl start postgresql-12

echo "Start configuration............................................."
echo "Directory and File Permissions.................................."
echo "umask 077" >> /var/lib/pgsql/.bash_profile
groupadd pg_wheel && gpasswd -a postgres pg_wheel

echo "Logging Monitoring And Auditing................................."
mkdir -p /var/log/postgres && \
chown postgres:postgres /var/log/postgres && \
chmod 750 /var/log/postgres
sudo -u postgres psql <<'EOF'
-- Ensure the log destinations are set correctly --
alter system set log_destination = 'csvlog';
-- Ensure the logging collector is enabled --
alter system set logging_collector = 'on';
-- Ensure the log file destination directory is set correctly --
alter system set log_directory='/var/log/postgres';
-- Ensure the filename pattern for log files is set correctly --
alter system set log_filename='postgresql-%d%m%Y.log';
-- Ensure the log file permissions are set correctly --
alter system set log_file_mode = '0600';
-- Ensure 'log_truncate_on_rotation' is enabled --
alter system set log_truncate_on_rotation = 'on';
-- Ensure the maximum log file lifetime is set correctly --
alter system set log_rotation_age='1d';
-- Ensure the maximum log file size is set correctly --
alter system set log_rotation_size = '0';
-- Ensure the correct syslog facility is selected --
alter system set syslog_facility = 'LOCAL1';
-- Ensure the program name for PostgreSQL syslog messages is correct --
alter system set syslog_ident = 'postgres';
-- Ensure the correct messages are written to the server log --
alter system set log_min_messages = 'warning';
-- Ensure the correct SQL statements generating errors are recorded --
alter system set log_min_error_statement = 'error';
-- Ensure 'debug_print_parse' is disabled --
alter system set debug_print_parse='off';
-- Ensure 'debug_print_rewritten' is disabled --
alter system set debug_print_rewritten = 'off';
-- Ensure 'debug_print_plan' is disabled --
alter system set debug_print_plan = 'off';
-- Ensure 'debug_pretty_print' is enabled --
alter system set debug_pretty_print = 'on';
-- Ensure 'log_connections' is enabled --
alter system set log_connections = 'on';
-- Ensure 'log_disconnections' is enabled --
alter system set log_disconnections = 'on';
-- Ensure 'log_error_verbosity' is set correctly --
alter system set log_error_verbosity = 'verbose';
-- Ensure 'log_hostname' is set correctly --
alter system set log_hostname='off';
-- Ensure 'log_line_prefix' is set correctly --
alter system set log_line_prefix = '%t [%p]: [%l-1] db=%d,user=%u,app=%a,client=%h ';
-- Ensure 'log_statement' is set correctly --
alter system set log_statement='ddl';
-- Ensure 'log_timezone' is set correctly --
alter system set log_timezone = 'UTC';
-- Ensure the PostgreSQL Audit Extension (pgAudit) is enabled --
alter system set shared_preload_libraries = 'pgaudit';
EOF
echo "pgaudit.log='ddl,write'" >> $PGDATA/postgresql.auto.conf

echo "User Access and Authorization.............................."
echo '%pg_wheel ALL= /bin/su - postgres' > /etc/sudoers.d/postgres
chmod 600 /etc/sudoers.d/postgres

echo "Connection and Login......................................."
sudo -u postgres psql <<'EOF'
-- Set listen address to any address --
alter system set listen_addresses = '*';
-- Set password encryption with scram-sha-256 --
alter system set password_encryption = 'scram-sha-256';
EOF
echo "Set listen custom PG port.................................."
sudo -u postgres psql -c "alter system set port = '$PGPORT';"

echo "If you use new port, please make sure to allow it from SELinux..."
semanage port -a -t postgresql_port_t -p tcp $PGPORT

cp $PGDATA/pg_hba.conf $PGDATA/pg_hba.conf_`date +"%d%m%Y"`
cat > $PGDATA/pg_hba.conf <<'EOF'
# TYPE         DATABASE        USER        ADDRESS         METHOD
# Only local be able to access Postgres with "peer"
local          all             all                         peer
EOF
systemctl restart postgresql-12
sudo -u postgres psql -p $PGPORT -p $PGPORT -c "alter role postgres with password '$PG_ADMPWD';"

echo "Local Firewall Settings..................................."
firewall-cmd --permanent --new-ipset=NET_PGUSER --type=hash:net
firewall-cmd --permanent --ipset=NET_PGUSER --add-entry=$PG_NETALLOW
firewall-cmd --permanent --service=postgresql --remove-port=5432/tcp
firewall-cmd --permanent --service=postgresql --add-port=$PG_PORT/tcp
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source ipset="NET_PGUSER" service name="postgresql" accept'
firewall-cmd --reload

echo "...End of Config!..................................Thanks!"
