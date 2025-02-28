#!/usr/bin/env bash
EB_ENV=$(./01_get_eb_envs.sh | fzf)
echo "EB env: ${EB_ENV}"
EB_INSTANCE=$(./02_get_instances.sh ${EB_ENV} | fzf)
echo "EB instance: ${EB_INSTANCE}"
./03_connect_to_instance.sh ${EB_INSTANCE}
