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

# Salt's mysql_* states need a MySQL driver inside Salt's own bundled Python, not
# the system one, so it is installed with salt-pip.
mariadb-python-driver:
  cmd.run:
    - name: salt-pip install PyMySQL
    - unless: salt-pip list 2>/dev/null | grep -qi '^PyMySQL'
    - require:
      - pkg: mariadb-packages

# slurmdbd's accounting store. Root connects over the local socket via unix_socket
# auth, so no root password is needed or stored.
slurm-acct-database:
  mysql_database.present:
    - name: {{ db.name }}
    - connection_default_file: /dev/null
    - connection_unix_socket: /run/mysqld/mysqld.sock
    - connection_user: root
    - require:
      - service: mariadb-service
      - cmd: mariadb-python-driver

slurm-acct-user:
  mysql_user.present:
    - name: {{ db.user }}
    - host: {{ db.host }}
    - password: '{{ password }}'
    - connection_default_file: /dev/null
    - connection_unix_socket: /run/mysqld/mysqld.sock
    - connection_user: root
    - require:
      - mysql_database: slurm-acct-database

slurm-acct-grants:
  mysql_grants.present:
    - grant: all privileges
    - database: {{ db.name }}.*
    - user: {{ db.user }}
    - host: {{ db.host }}
    - connection_default_file: /dev/null
    - connection_unix_socket: /run/mysqld/mysqld.sock
    - connection_user: root
    - require:
      - mysql_user: slurm-acct-user
