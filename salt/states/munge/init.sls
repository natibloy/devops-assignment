# Munge authenticates every Slurm RPC, so slurmctld on the controller and slurmd
# on the compute node must hold byte-identical keys. Both get theirs from the same
# pillar value, which is what keeps them synchronized.

munge-package:
  pkg.installed:
    - name: munge

# The key is 1024 random bytes; the pillar carries it base64-encoded because a
# pillar cannot hold raw binary. It is staged here and decoded below rather than
# passed on a command line, which would leak it into process listings and logs.
munge-key-encoded:
  file.managed:
    - name: /etc/munge/munge.key.b64
    - contents_pillar: secrets:munge_key_b64
    - contents_newline: False
    - user: root
    - group: root
    - mode: '0400'
    - require:
      - pkg: munge-package

# The `unless` compares the installed key against the desired one, so this decodes
# on the first run, again if the pillar changes, and never otherwise.
munge-key:
  cmd.run:
    - name: |
        base64 -d /etc/munge/munge.key.b64 > /etc/munge/munge.key
        chown munge:munge /etc/munge/munge.key
        chmod 0400 /etc/munge/munge.key
    - unless: base64 -d /etc/munge/munge.key.b64 | cmp -s - /etc/munge/munge.key
    - require:
      - file: munge-key-encoded

munge-service:
  service.running:
    - name: munge
    - enable: True
    - watch:
      - cmd: munge-key
