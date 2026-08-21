{%- set db = salt['pillar.get']('slurm:db') %}
{%- set password = salt['pillar.get']('secrets:slurmdbd_db_password') %}

mariadb-packages:
  pkg.installed:
    - pkgs:
      - mariadb-server
      - mariadb-client

mariadb-service:
  service.running:
    - name: mariadb
    - enable: True
    - require:
      - pkg: mariadb-packages

# The accounting store is provisioned with the mysql client rather than Salt's
# mysql_* states. Those states only load if a MySQL driver is importable from
# Salt's bundled interpreter, and the state compiler resolves them before any
# state could install one - so a first highstate on a fresh minion would fail with
# "State 'mysql_database.present' was not found".
#
# Every statement below is written to converge rather than assert, so applying the
# file repeatedly is safe. Both files are root-only, and the password is never
# passed on a command line where it would land in process listings or Salt's logs.
slurm-acct-sql:
  file.managed:
    - name: /root/slurm-acct.sql
    - user: root
    - group: root
    - mode: '0600'
    - contents: |
        CREATE DATABASE IF NOT EXISTS `{{ db.name }}`;
        CREATE USER IF NOT EXISTS '{{ db.user }}'@'{{ db.host }}' IDENTIFIED BY '{{ password }}';
        ALTER USER '{{ db.user }}'@'{{ db.host }}' IDENTIFIED BY '{{ password }}';
        GRANT ALL PRIVILEGES ON `{{ db.name }}`.* TO '{{ db.user }}'@'{{ db.host }}';
        FLUSH PRIVILEGES;
    - require:
      - pkg: mariadb-packages

# Used only by the guard below, to ask the database whether the account already
# works instead of inferring it.
slurm-acct-client-cnf:
  file.managed:
    - name: /root/slurm-acct-client.cnf
    - user: root
    - group: root
    - mode: '0600'
    - contents: |
        [client]
        user={{ db.user }}
        password={{ password }}
        host={{ db.host }}
    - require:
      - pkg: mariadb-packages

# The guard is a real login as the Slurm account against its own database, so this
# runs on the first highstate, again if the password or grants ever drift, and not
# at all once they are correct.
slurm-acct-provision:
  cmd.run:
    - name: mysql < /root/slurm-acct.sql
    - unless: mysql --defaults-extra-file=/root/slurm-acct-client.cnf -e 'SELECT 1' {{ db.name }}
    - require:
      - service: mariadb-service
      - file: slurm-acct-sql
      - file: slurm-acct-client-cnf
