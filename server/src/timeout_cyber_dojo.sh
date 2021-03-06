#!/usr/bin/env sh
# Note: Alpine images may not have bash

readonly IMAGE_NAME=$1
readonly KATA_ID=$2
readonly AVATAR_NAME=$3
readonly MAX_SECONDS=$4

export CYBER_DOJO_IMAGE_NAME=${IMAGE_NAME}
export CYBER_DOJO_KATA_ID=${KATA_ID}
export CYBER_DOJO_AVATAR_NAME=${AVATAR_NAME}
export CYBER_DOJO_RUNNER=processful
export CYBER_DOJO_SANDBOX=/sandboxes/${AVATAR_NAME}

cd ${CYBER_DOJO_SANDBOX}

grep -q -c Alpine /etc/issue >/dev/null 2>&1
if [ $? -eq 0 ]; then
  # On Alpine's ps, the avatar-user's name is truncated to 8 chars
  readonly PS_AVATAR=`echo ${AVATAR_NAME} | cut -c -8`
fi

grep -q -c Ubuntu /etc/issue >/dev/null 2>&1
if [ $? -eq 0 ]; then
  readonly PS_AVATAR=${AVATAR_NAME}
fi

grep -q -c Debian /etc/issue >/dev/null 2>&1
if [ $? -eq 0 ]; then
  readonly PS_AVATAR=${AVATAR_NAME}
fi

/dev/init -s -g -- su ${AVATAR_NAME} -c "timeout -s KILL ${MAX_SECONDS}s sh ./cyber-dojo.sh"
status=$?
ps -o user,pid | grep "^${PS_AVATAR}\s" | awk '{print $2}' | xargs -r kill -9 >/dev/null 2>&1
exit ${status}
