#!/usr/bin/env bash
EB_ENV=$(./get_eb_envs.sh | fzf)
echo "EB env: ${EB_ENV}"
EB_INSTANCE=$(./get_instances.sh ${EB_ENV} | fzf)
echo "EB instance: ${EB_INSTANCE}"
./connect_to_instance.sh ${EB_INSTANCE}
