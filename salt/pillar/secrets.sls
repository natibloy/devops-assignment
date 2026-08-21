# Sensitive values consumed by the munge, mariadb and monitoring states.
#
# These are committed in plaintext because this is a self-contained lab that must
# come up from a single `vagrant up` with no external key material. In a real
# deployment this file would be encrypted (GPG renderer) or sourced from an SDB
# backend such as Vault, with only the pillar *references* in git.
secrets:
  # 1024 random bytes, base64-encoded on a single line (folded YAML scalars would
  # inject whitespace and corrupt the decoded key). Decoded by the munge state and
  # written identically to the controller and compute nodes so they trust each other.
  munge_key_b64: 'REDACTED-ROTATED-CREDENTIAL'
  slurmdbd_db_password: REDACTED-ROTATED-CREDENTIAL
  grafana_admin_user: admin
  grafana_admin_password: REDACTED-ROTATED-CREDENTIAL
