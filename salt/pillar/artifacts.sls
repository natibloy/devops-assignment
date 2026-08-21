# The shared folder the builder writes and the other two nodes read - the one
# cross-node contract in this repo. Only the root lives here; every path beneath
# it is derived by salt/states/artifacts.jinja so the producer and the consumers
# cannot drift apart. The Vagrantfile reads this value too, for the mount point.
artifacts:
  root: /srv/artifacts
