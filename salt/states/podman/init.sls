# Applied unchanged to both the builder (to build the gateway image) and the
# controller (to run node_exporter). This single state is why neither node needs
# its own copy of the container-engine setup.

podman-packages:
  pkg.installed:
    - pkgs:
      - podman
      - buildah
      - uidmap
      - slirp4netns

# Debian's podman ships no default registry search list, so unqualified image
# names fail to resolve without this.
podman-registries:
  file.managed:
    - name: /etc/containers/registries.conf.d/10-lab.conf
    - makedirs: True
    - mode: '0644'
    - contents: |
        unqualified-search-registries = ["docker.io", "quay.io"]
    - require:
      - pkg: podman-packages
