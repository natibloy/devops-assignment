#!py
"""Lab secrets - generated on first use, never committed.

The munge key and the slurmdbd database password are values no human needs to
read: nothing outside this cluster consumes them, and no operator ever types
them. So instead of shipping them in git, they are generated the first time the
pillar is rendered and cached on the machine that rendered it.

That machine is the Salt master, and the master renders pillar data on behalf of
every minion - which is exactly what the munge key needs, since slurmctld on the
controller and slurmd on the compute node must hold byte-identical keys. Both
receive the same generated value from the same cache.

Consequences worth knowing:

  * Nothing secret is in the repository, so cloning it grants no access.
  * `vagrant destroy` discards the cache, so a rebuilt cluster gets fresh
    credentials. Rotation is `rm -rf /etc/salt/lab-secrets` plus a highstate.
  * The builder renders this masterless and caches its own unused copy. Harmless:
    its states need neither value.

In a real deployment this file would be replaced by Salt's GPG renderer, or an
ext_pillar backed by Vault or another secret store. The pillar *keys* it returns
would be identical, so no state or template would change - which is the point of
reading every credential through the pillar in the first place.
"""

import base64
import os

# Root-only, and outside both the state tree and the synced folder, so a
# generated value can never be written back into the repository.
CACHE_DIR = "/etc/salt/lab-secrets"


def _read(path):
    try:
        with open(path) as handle:
            return handle.read().strip() or None
    except OSError:
        return None


def _generated(name, factory):
    """Return the cached value for `name`, generating and storing it if absent.

    Creation is atomic (O_EXCL). The master renders pillar for each minion
    independently and may do so concurrently, so a plain write-if-missing would
    let two renders each generate a value with the last write winning - and a
    minion that received the losing value would cache it and go on using a key
    the other node does not share. Whichever render creates the file wins, and
    every other render re-reads it, so all of them return the same value.
    """
    path = os.path.join(CACHE_DIR, name)
    cached = _read(path)
    if cached:
        return cached

    os.makedirs(CACHE_DIR, mode=0o700, exist_ok=True)
    try:
        handle = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        # Another render created it first; its value is authoritative.
        return _read(path)
    with os.fdopen(handle, "w") as fh:
        fh.write(factory())
    return _read(path)


def run():
    return {
        "secrets": {
            # 1024 random bytes, base64-encoded because a pillar cannot carry raw
            # binary. The munge state decodes it back to bytes on both nodes.
            "munge_key_b64": _generated(
                "munge_key_b64",
                lambda: base64.b64encode(os.urandom(1024)).decode(),
            ),
            "slurmdbd_db_password": _generated(
                "slurmdbd_db_password",
                lambda: os.urandom(16).hex(),
            ),
            # The assignment asks for Grafana's default credentials, so these are
            # deliberately not secret and stay literal.
            "grafana_admin_user": "admin",
            "grafana_admin_password": "admin",
        }
    }
