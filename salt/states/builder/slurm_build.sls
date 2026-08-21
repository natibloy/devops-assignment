{%- import 'artifacts.jinja' as artifacts with context %}
{%- set slurm = salt['pillar.get']('slurm') %}
{%- set version = slurm.version %}
{%- set src = slurm.build_dir ~ '/slurm-' ~ version %}
{%- set tarball = src ~ '.tar.bz2' %}
{%- set debs = artifacts.debs %}
{%- set sentinel = artifacts.build_sentinel(version) %}

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
#
# Only five of Slurm's seventeen binary packages are ever installed, so the build
# options drop the work whose output nothing here consumes: noautodbgsym skips the
# debug packages (over half the bytes copied to the share), nodoc the manuals,
# nocheck the test suite, and --no-lintian the packaging audit of all seventeen.
# dpkg-buildpackage rather than debuild: debuild's only additions here are package
# signing, which -uc -us disables anyway, and a lintian run whose output nothing
# reads. It also sanitises the environment, which is a trap for the build options
# below - dpkg-buildpackage reads them straight from it.
slurm-debuild:
  cmd.run:
    - name: dpkg-buildpackage -b -uc -us
    - cwd: {{ src }}
    - env:
      - DEB_BUILD_OPTIONS: parallel={{ grains['num_cpus'] }} noautodbgsym nodoc nocheck
      - DEBIAN_FRONTEND: noninteractive
    - timeout: 3600
    - unless: test -f {{ sentinel }}
    - require:
      - cmd: slurm-build-deps

# dpkg-buildpackage drops its output in the parent of the source tree, so the glob
# is pinned to this version: a previous build of a different version leaves its own
# debs there, and copying those too would publish two versions in the repository.
slurm-export-debs:
  cmd.run:
    - name: cp {{ slurm.build_dir }}/*_{{ version }}-*.deb {{ debs }}/
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

# Written last, so its presence means "the repository is complete and indexed" to
# every consumer, not merely "a build happened".
slurm-build-sentinel:
  file.managed:
    - name: {{ sentinel }}
    - contents: |
        slurm {{ version }} built from source on {{ grains['id'] }}
    - require:
      - cmd: slurm-apt-index
