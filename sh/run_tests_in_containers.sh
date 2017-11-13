#!/bin/bash

readonly ROOT_DIR="$( cd "$( dirname "${0}" )" && cd .. && pwd )"
readonly MY_NAME="${ROOT_DIR##*/}"

readonly SERVER_CID=`docker ps --all --quiet --filter "name=${MY_NAME}_server"`
readonly CLIENT_CID=`docker ps --all --quiet --filter "name=${MY_NAME}_client"`

run_server_tests()
{
  docker exec ${SERVER_CID} sh -c "cd test && ./run.sh ${*}"
  server_status=$?
  rm -rf ${ROOT_DIR}/server/coverage/
  docker cp ${SERVER_CID}:${CYBER_DOJO_COVERAGE_ROOT}/. ${ROOT_DIR}/server/coverage/
  echo "Coverage report copied to ${ROOT_DIR}/server/coverage"
  cat ${ROOT_DIR}/server/coverage/done.txt
}

run_client_tests()
{
  docker exec ${CLIENT_CID} sh -c "cd test && ./run.sh ${*}"
  client_status=$?
  rm -rf ${ROOT_DIR}/client/coverage
  docker cp ${CLIENT_CID}:${CYBER_DOJO_COVERAGE_ROOT}/. ${ROOT_DIR}/client/coverage/
  echo "Coverage report copied to ${ROOT_DIR}/client/coverage"
  cat ${ROOT_DIR}/client/coverage/done.txt
}

# - - - - - - - - - - - - - - - - - - - - - - - - - -

server_status=0
client_status=0
. ${ROOT_DIR}/.env
run_server_tests ${*}
run_client_tests ${*}

if [[ ( ${server_status} == 0 && ${client_status} == 0 ) ]];  then
  echo "------------------------------------------------------"
  echo "All passed"
  ${ROOT_DIR}/sh/docker_containers_down.sh
  exit 0
else
  echo
  echo "server: cid = ${server_cid}, status = ${server_status}"
  echo "client: cid = ${client_cid}, status = ${client_status}"
  echo
  exit 1
fi
