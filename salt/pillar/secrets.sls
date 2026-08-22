# Sensitive values for the Slurm cluster, consumed by the munge, mariadb and
# monitoring states. The assignment asks for Salt Pillars to hold the Munge key and
# the database password, and this is that pillar.
#
# Every value here is a throwaway lab credential. They authorize nothing outside
# these three disposable VMs on a private host-only network, and they are identical
# for anyone who clones the repository - which is the point: `vagrant up` has to work
# from a fresh clone with no external key material to fetch.
#
# What a real deployment would do instead: keep these same pillar keys, but fill them
# from Salt's GPG renderer, or an ext_pillar backed by Vault, AWS Secrets Manager or
# similar. No state and no template would change, because none of them contain a
# credential - they all read these keys by name. That indirection is the reason the
# storage backend is a swappable detail.
secrets:
  # 1024 bytes, base64-encoded on a single line, because a pillar cannot carry raw
  # binary and a folded YAML scalar would inject whitespace and corrupt the decode.
  # The decoded content spells out what it is: munge accepts any 32-1024 byte key,
  # and for a key that is public in git anyway, entropy buys nothing over honesty.
  munge_key_b64: 'TEFCLU9OTFktTVVOR0UtS0VZLU5PVC1BLVJFQUwtU0VDUkVULUxBQi1PTkxZLU1VTkdFLUtFWS1OT1QtQS1SRUFMLVNFQ1JFVC1MQUItT05MWS1NVU5HRS1LRVktTk9ULUEtUkVBTC1TRUNSRVQtTEFCLU9OTFktTVVOR0UtS0VZLU5PVC1BLVJFQUwtU0VDUkVULUxBQi1PTkxZLU1VTkdFLUtFWS1OT1QtQS1SRUFMLVNFQ1JFVC1MQUItT05MWS1NVU5HRS1LRVktTk9ULUEtUkVBTC1TRUNSRVQtTEFCLU9OTFktTVVOR0UtS0VZLU5PVC1BLVJFQUwtU0VDUkVULUxBQi1PTkxZLU1VTkdFLUtFWS1OT1QtQS1SRUFMLVNFQ1JFVC1MQUItT05MWS1NVU5HRS1LRVktTk9ULUEtUkVBTC1TRUNSRVQtTEFCLU9OTFktTVVOR0UtS0VZLU5PVC1BLVJFQUwtU0VDUkVULUxBQi1PTkxZLU1VTkdFLUtFWS1OT1QtQS1SRUFMLVNFQ1JFVC1MQUItT05MWS1NVU5HRS1LRVktTk9ULUEtUkVBTC1TRUNSRVQtTEFCLU9OTFktTVVOR0UtS0VZLU5PVC1BLVJFQUwtU0VDUkVULUxBQi1PTkxZLU1VTkdFLUtFWS1OT1QtQS1SRUFMLVNFQ1JFVC1MQUItT05MWS1NVU5HRS1LRVktTk9ULUEtUkVBTC1TRUNSRVQtTEFCLU9OTFktTVVOR0UtS0VZLU5PVC1BLVJFQUwtU0VDUkVULUxBQi1PTkxZLU1VTkdFLUtFWS1OT1QtQS1SRUFMLVNFQ1JFVC1MQUItT05MWS1NVU5HRS1LRVktTk9ULUEtUkVBTC1TRUNSRVQtTEFCLU9OTFktTVVOR0UtS0VZLU5PVC1BLVJFQUwtU0VDUkVULUxBQi1PTkxZLU1VTkdFLUtFWS1OT1QtQS1SRUFMLVNFQ1JFVC1MQUItT05MWS1NVU5HRS1LRVktTk9ULUEtUkVBTC1TRUNSRVQtTEFCLU9OTFktTVVOR0UtS0VZLU5PVC1BLVJFQUwtU0VDUkVULUxBQi1PTkxZLU1VTkdFLUtFWS1OT1QtQS1SRUFMLVNFQ1JFVC1MQUItT05MWS1NVU5HRS1LRVktTk9ULUEtUkVBTC1TRUNSRVQtTEFCLU9OTFktTVVOR0UtS0VZLU5PVC1BLVJFQUwtU0VDUkVULUxBQi1PTkxZLU1VTkdFLUtFWS1OT1QtQS1SRUFMLVNFQ1JFVC1MQUItT05MWS1NVU5HRS1LRVktTk9ULUEtUkVBTC1TRUNSRVQtTEFCLU9OTFktTVVOR0UtS0VZLU5PVC1BLQ=='

  slurmdbd_db_password: lab-only-slurmdbd-password

  # Grafana's default credentials, as the assignment specifies.
  grafana_admin_user: admin
  grafana_admin_password: admin
