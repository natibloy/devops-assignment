{%- set slurm = salt['pillar.get']('slurm') %}
{%- set version = slurm.version %}
{%- set src = slurm.build_dir ~ '/slurm-' ~ version %}
{%- set tarball = slurm.build_dir ~ '/slurm-' ~ version ~ '.tar.bz2' %}
{%- set debs = '/srv/artifacts/debs' %}
{%- set sentinel = debs ~ '/.built-' ~ version %}

# Slurm ships its own debian/ packaging, which produces the separated
# slurm-smd-* packages (client, slurmctld, slurmd, slurmdbd, ...) rather than one
# monolithic deb. mk-build-deps reads that packaging's own Build-Depends so the
# dependency list never has to be restated here.
slurm-build-tooling:
  pkg.installed:
    - pkgs:
      - build-essential
      - fakeroot
      - devscripts
      - equivs
      - dpkg-dev
      - bzip2

{{ slurm.build_dir }}:
  file.directory:
    - makedirs: True

{{ debs }}:
  file.directory:
    - makedirs: True

# Everything below is skipped once the sentinel exists, so re-running the
# highstate on a surviving builder does not rebuild Slurm.
slurm-download:
  cmd.run:
    - name: curl -fL --retry 3 -o {{ tarball }} {{ slurm.source_url }}/slurm-{{ version }}.tar.bz2
    - creates: {{ tarball }}
    - unless: test -f {{ sentinel }}
    - require:
      - file: {{ slurm.build_dir }}

slurm-extract:
  cmd.run:
    - name: tar -xaf {{ tarball }}
    - cwd: {{ slurm.build_dir }}
    - creates: {{ src }}/debian/control
    - unless: test -f {{ sentinel }}
    - require:
      - cmd: slurm-download

slurm-build-deps:
  cmd.run:
    - name: >-
        mk-build-deps -i -r
        -t 'apt-get -y --no-install-recommends -o Debug::pkgProblemResolver=yes'
        debian/control
    - cwd: {{ src }}
    - unless: test -f {{ sentinel }}
    - require:
      - pkg: slurm-build-tooling
      - cmd: slurm-extract

# debuild is deliberately run on the guest filesystem: the VirtualBox shared
# folder cannot represent the symlinks and hardlinks dpkg-buildpackage creates.
slurm-debuild:
  cmd.run:
    - name: debuild -b -uc -us
    - cwd: {{ src }}
    - env:
      - DEB_BUILD_OPTIONS: parallel={{ grains['num_cpus'] }}
      - DEBIAN_FRONTEND: noninteractive
    - timeout: 3600
    - unless: test -f {{ sentinel }}
    - require:
      - cmd: slurm-build-deps

slurm-export-debs:
  cmd.run:
    - name: cp {{ slurm.build_dir }}/*.deb {{ debs }}/
    - unless: test -f {{ sentinel }}
    - require:
      - cmd: slurm-debuild
      - file: {{ debs }}

# Publishing the debs as a real apt repository lets the controller and compute
# nodes use pkg.installed and have apt resolve inter-package dependencies,
# instead of fighting dpkg -i ordering.
slurm-apt-index:
  cmd.run:
    - name: dpkg-scanpackages --multiversion . > Packages && gzip -9cf Packages > Packages.gz
    - cwd: {{ debs }}
    - unless: test -f {{ sentinel }}
    - require:
      - cmd: slurm-export-debs

slurm-build-sentinel:
  file.managed:
    - name: {{ sentinel }}
    - contents: |
        slurm {{ version }} built from source on {{ grains['id'] }}
    - require:
      - cmd: slurm-apt-index
