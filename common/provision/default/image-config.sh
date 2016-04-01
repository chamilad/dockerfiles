#!/bin/sh
# ------------------------------------------------------------------------
#
# Copyright 2016 WSO2, Inc. (http://wso2.com)
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

mkdir -p /mnt > /dev/null
cd /mnt > /dev/null
addgroup wso2
adduser -S -s /bin/sh -g 'WSO2User' -G wso2 wso2user
wget ${HTTP_PACK_SERVER}/${WSO2_SERVER}-${WSO2_SERVER_VERSION}.zip
echo "Unpacking ${WSO2_SERVER}-${WSO2_SERVER_VERSION}.zip to /mnt"
unzip -q /mnt/${WSO2_SERVER}-${WSO2_SERVER_VERSION}.zip -d /mnt
rm -rf /mnt/${WSO2_SERVER}-${WSO2_SERVER_VERSION}.zip
chown wso2user:wso2 /usr/local/bin/*
chown -R wso2user:wso2 /mnt
