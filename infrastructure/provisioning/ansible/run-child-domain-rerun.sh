#!/usr/bin/env bash
set -euo pipefail

cd /ansible

rm -f child_domain-rerun.log child_domain-rerun.pid child_domain-rerun.exit

nohup bash -c '
  cd /ansible
  ANSIBLE_CONFIG=/ansible/ansible.cfg ansible-playbook \
    -i inventory.yml \
    site.yml \
    --tags child \
    --limit winterfell \
    -e vault_lab_password=Password123!
  echo "$?" > child_domain-rerun.exit
' > child_domain-rerun.log 2>&1 < /dev/null &

echo "$!" > child_domain-rerun.pid
cat child_domain-rerun.pid
