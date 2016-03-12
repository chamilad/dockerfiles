#!/bin/bash
# ------------------------------------------------------------------------
#
# Copyright 2005-2015 WSO2, Inc. (http://wso2.com)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License

# ------------------------------------------------------------------------
set -e

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source "${DIR}/base.sh"

# Show usage and exit
function showUsageAndExit() {
    echoError "Insufficient or invalid options provided!"
    echoBold "Usage: ./build.sh -v [product-version] -i [docker-image-version] [OPTIONAL] -l [product-profile-list] [OPTIONAL] -e [product-env] [OPTIONAL] -h [Puppet HTTP Server address ip:port]"
    echo "Ex: ./build.sh -v 1.9.1 -i 1.0.0 -l 'default|worker|manager'"
    echo "Ex: ./build.sh -v 1.9.1 -i 1.0.0 -h '172.17.0.1:8000'"
    exit 1
}

function cleanup() {
    echoBold "Cleaning..."
    if [ ! -z $httpserver_pid ]; then
        kill -9 $httpserver_pid > /dev/null 2>&1
    fi
    # rm -rf "$dockerfile_path/scripts"
    # rm -rf "$dockerfile_path/puppet"
}

function listFiles () {
    find "${1}" -maxdepth 1 -mindepth 1 -printf "%f\n"
    echo
    # for n in "${1}"; do echo "${n%%.*}"; done
    # for n in "${1}"; do echo "${n}"; done
}

# $1 product name = esb
# $2 product version = 4.9.0
function validateProductVersion() {
    ver_dir="${PUPPET_HOME}/hieradata/dev/wso2/wso2${1}/${2}"
    if [ ! -d "$ver_dir" ]; then
        echoError "Provided product version wso2${1}:${2} doesn't exist in PUPPET_HOME: ${PUPPET_HOME}. Available versions are,"
        listFiles "${PUPPET_HOME}/hieradata/dev/wso2/wso2${1}/"
        showUsageAndExit
    fi
}

# $1 product name = esb
# $2 product version = 4.9.0
# $3 product profile list = 'default|worker|manager'
function validateProfile() {
    invalidFound=false
    IFS='|' read -r -a array <<< "${3}"
    for profile in "${array[@]}"
    do
        profile_yaml="${PUPPET_HOME}/hieradata/dev/wso2/wso2${1}/${2}/${profile}.yaml"
        if [ ! -e "${profile_yaml}" ] || [ ! -s "${profile_yaml}" ]
        then
            invalidFound=true
        fi
    done

    if [ "${invalidFound}" == true ]
    then
        echoError "One or more provided product profiles wso2${1}:${2}-[${3}] do not exist in PUPPET_HOME: ${PUPPET_HOME}. Available profiles are,"
        listFiles "${PUPPET_HOME}/hieradata/dev/wso2/wso2${1}/${2}/"
        showUsageAndExit
    fi
}

verbose=false

while getopts :n:v:i:e:l:d:h:x FLAG; do
    case $FLAG in
        n)
            product_name=$OPTARG
            ;;
        v)
            product_version=$OPTARG
            ;;
        i)
            image_version=$OPTARG
            ;;
        l)
            product_profiles=$OPTARG
            ;;
        e)
            product_env=$OPTARG
            ;;
        d)
            dockerfile_path=$OPTARG
            ;;
        x)
            verbose=true
            ;;
        h)
            httpserver_address=$OPTARG
            ;;
        \?)
            showUsageAndExit
            ;;
    esac
done

prgdir2=$(dirname "$0")
self_path=$(cd "$prgdir2"; pwd)

# Validate mandatory args
if [ -z "$product_version" ]
  then
    showUsageAndExit
fi

if [ -z "$image_version" ]
  then
    showUsageAndExit
fi

if [ -z "$product_profiles" ]
  then
    product_profiles="default"
fi

if [ -z "$product_env" ]; then
    product_env="dev"
fi

# Check if a Puppet folder is set
if [ -z "$PUPPET_HOME" ]; then
   echoError "Puppet home folder could not be found! Set PUPPET_HOME environment variable pointing to local puppet folder."
   exit 1
else
   echoBold "PUPPET_HOME is set to ${PUPPET_HOME}."
fi

# check if provided product version exists in PUPPET_HOME
validateProductVersion "${product_name}" "${product_version}"

# check if provided profile exists in PUPPET_HOME
validateProfile "${product_name}" "${product_version}" "${product_profiles}"

docker_version=$(docker version --format '{{.Server.Version}}')
echoBold "Docker version should be equal to or later than 1.9.0 to build WSO2 Docker images. Found ${docker_version}"
echo

if [ -z "$httpserver_address" ]; then
    # starting http Server
    echoBold "A server address is not specified (-h)."
    echoBold "Starting HTTP Server at ${PUPPET_HOME}..."

    # check if port 8000 is already in use
    port_uses=$(lsof -i:8000 | wc -l)
    if [ $port_uses -gt 1 ]; then
        echoError "Port 8000 seems to be already in use. Exiting..."
        exit 1
    fi

    # start the server in background
    pushd ${PUPPET_HOME}
    python -m SimpleHTTPServer 8000 & > /dev/null 2>&1
    httpserver_pid=$!
    popd

    # get docker bridge ip
    httpserver_address=$(ifconfig docker | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
    httpserver_address="${httpserver_address// /}"
    if [[ $docker_bridge_ip == *"error"* ]]; then
        echoError "Couldn't find Docker bridge IP. Exiting..."
        cleanup
        exit 1
    fi

    httpserver_address="${httpserver_address}:8000"
fi

# check if http server is accessible
# echo "HTTP: Ser: ${httpserver_address}"
# curl_response=$(curl -s -o /dev/null -w "%{http_code}" http://${httpserver_address})
# if [[ $curl_response != "200" ]]; then
#     echoError "Cannot reach the specified HTTP Server: ${httpserver_address}. Exiting..."
#     cleanup
#     exit 1
# fi

# Build image for each profile provided
echoBold "Starting Docker builds..."
IFS='|' read -r -a profiles_array <<< "${product_profiles}"
for profile in "${profiles_array[@]}"
do
    # set image name according to the profile list
    if [[ "${profile}" = "default" ]]; then
        image_id="wso2/${product_name}-${product_version}:${image_version}"
    else
        image_id="wso2/${product_name}-${profile}-${product_version}:${image_version}"
    fi

    image_exists=$(docker images $image_id | wc -l)
    if [ ${image_exists} == "2" ]; then
        askBold "Docker image \"${image_id}\" already exists? Overwrite? (y/n): "
        read -r overwrite_v
    fi

    if [ "${image_exists}" == "1" ] || [ "$overwrite_v" == "y" ]; then

        # if there is a custom init.sh script supplied specific for the profile of this product, pack
        # it to ${dockerfile_path}/scripts/
        # product_init_script_name="wso2${product_name}-${profile}-init.sh"
        # if [[ -f "${dockerfile_path}/scripts/${product_init_script_name}" ]]; then
        #     pushd "${dockerfile_path}" > /dev/null
        #     cp "${product_init_script_name}" scripts/
        #     popd > /dev/null
        # fi

        echoBold "Building docker image ${image_id}..."

        {
            ! docker build --no-cache=true \
            --build-arg WSO2_SERVER="wso2${product_name}" \
            --build-arg WSO2_SERVER_VERSION="${product_version}" \
            --build-arg WSO2_SERVER_PROFILE="${profile}" \
            --build-arg WSO2_ENVIRONMENT="${product_env}" \
            --build-arg HTTP_PUPPET_SERVER="${httpserver_address}" \
            -t "${image_id}" "${dockerfile_path}" | grep -i error && echo "Docker image ${image_id} created."

        } || {
            echoError "ERROR: Docker image ${image_id} creation failed"
            cleanup
            exit 1
        }
    else
        echoBold "Not overwriting \"${image_id}\"..."
    fi
done

cleanup
echoSuccess "Build process completed"
