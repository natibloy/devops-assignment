{%- import 'artifacts.jinja' as artifacts with context %}
{%- set slurm = salt['pillar.get']('slurm') %}
{%- set debs = artifacts.debs %}
{#- Probed to decide whether apt can already see the local repository. Taken from
    the packages both roles install, since this state applies to both. -#}
{%- set probe = slurm.packages.common[0] %}

# The builder published its output as a flat apt repository. Pointing apt at it
# lets the Slurm packages be installed with pkg.installed, with apt resolving the
# dependencies between them and against Debian's own archive.
#
# The repository is written as a plain file rather than with pkgrepo.managed:
# pkgrepo needs python-apt importable from Salt's bundled interpreter, which the
# onedir packages do not provide on Debian.
slurm-artifacts-present:
  file.exists:
    - name: {{ artifacts.build_sentinel(slurm.version) }}

slurm-local-repo:
  file.managed:
    - name: /etc/apt/sources.list.d/slurm-local.list
    - mode: '0644'
    - contents: |
        # Local repository of the DEBs built by the builder node.
        deb [trusted=yes] file:{{ debs }} ./
    - require:
      - file: slurm-artifacts-present

# Refreshes when the Slurm packages are not yet visible to apt, which covers both
# the first run and a stale cache, and is a no-op once they are.
slurm-local-repo-refresh:
  cmd.run:
    - name: apt-get update
    - unless: "apt-cache policy {{ probe }} | grep -qE 'Candidate: [0-9]'"
    - require:
      - file: slurm-local-repo
