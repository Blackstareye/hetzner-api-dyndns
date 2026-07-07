#!/usr/bin/env bash
# DynDNS Script for Hetzner DNS API by FarrowStrange; Updateded and Extended by Blackeye/ Blackstareye
# v1.4

# get OS environment variables
auth_api_token=${HETZNER_AUTH_API_TOKEN:-''}

zone_name=${HETZNER_ZONE_NAME:-''}
zone_id=${HETZNER_ZONE_ID:-''}

record_name=${HETZNER_RECORD_NAME:-''}
record_ttl=${HETZNER_RECORD_TTL:-'60'}
record_type=${HETZNER_RECORD_TYPE:-'A'}


localserver=${LOCALSERVERFILE:-'server.json'}
ext_ip_resolver_type=${HETZNER_EXT_IP_RESOLVER_TYPE:-'hetzner'}
ext_ip_resolver=${HETZNER_EXT_IP_RESOLVER:-'https://ip.hetzner.com'}

record_set=""

debug() {
  echo "$1"
}


display_help() {
  cat <<EOF

exec: ./dyndns.sh [ -z <Zone ID> | -Z <Zone Name> ] [-m <hetzner|fritzbox|server>] -r <Record ID> -n <Record Name>

parameters:
  -z  - Zone ID
  -Z  - Zone name
  -r  - Record ID
  -n  - Record name

optional parameters:
  -t  - TTL (Default: 60)
  -T  - Record type (Default: A)
  -m  - Method for Extracting IP(Default:hetzner)

help:
  -h  - Show Help 

requirements:
  curl
  jq

example:
  .exec: ./dyndns.sh -z 98jFjsd8dh1GHasdf7a8hJG7 -r AHD82h347fGAF1 -n dyn
  .exec: ./dyndns.sh -Z example.com -n dyn -T AAAA

EOF
  exit 1
}

logger() {
  echo ${1}: Record_Name: ${record_name} : ${2}
}
while getopts ":z:Z:m:r:n:t:T:h" opt; do
  case "$opt" in
    z  ) zone_id="${OPTARG}";;
    Z  ) zone_name="${OPTARG}";;
    m  ) ext_ip_resolver_type="${OPTARG}";;
    r  ) record_id="${OPTARG}";;
    n  ) record_name="${OPTARG}";;
    t  ) record_ttl="${OPTARG}";;
    T  ) record_type="${OPTARG}";;
    h  ) display_help;;
    \? ) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    :  ) echo "Missing option argument for -$OPTARG" >&2; exit 1;;
    *  ) echo "Unimplemented option: -$OPTARG" >&2; exit 1;;
  esac
done

# Check if tools are installed
for cmd in curl jq; do
  if ! command -v "${cmd}" &> /dev/null; then
    logger Error "To run the script '${cmd}' is needed, but it seems not to be installed."
    logger Error "Please check 'https://github.com/Blackstareye/hetzner-api-dyndns#install-tools' for more informations and try again."
    exit 1
  fi
done

# Check if api token is set 
if [[ "${auth_api_token}" = "" ]]; then
  logger Error "No Auth API Token specified."
  exit 1
fi

# get all zones
zone_info=$(curl "https://api.hetzner.cloud/v1/zones?name=&mode=primary&label_selector=&sort=id&page=1&per_page=25" --header "Authorization: Bearer ${auth_api_token}")


# check if either zone_id or zone_name is correct
if [[ "$(echo ${zone_info} | jq --raw-output '.zones[] | select(.name=="'${zone_name}'") | .id')" = "" && "$(echo ${zone_info} | jq --raw-output '.zones[] | select(.id=="'${zone_id}'") | .name')" = "" ]]; then
  logger Error "Something went wrong. Could not find Zone ID."
  logger Error "Check your inputs of either -z <Zone ID> or -Z <Zone Name>."
  logger Error "Use -h to display help."
  exit 1
fi

# get zone_id if zone_name is given and in zones
if [[ "${zone_id}" = "" ]]; then
  zone_id=$(echo ${zone_info} | jq --raw-output '.zones[] | select(.name=="'${zone_name}'") | .id')
fi

# get zone_name if zone_id is given and in zones
if [[ "${zone_name}" = "" ]]; then
  zone_name=$(echo ${zone_info} | jq --raw-output '.zones[] | select(.id=="'${zone_id}'") | .name')
fi

logger Info "Zone_ID: ${zone_id}"
logger Info "Zone_Name: ${zone_name}"

if [[ "${record_name}" = "" ]]; then
  logger Error "Mission option for record name: -n <Record Name>"
  logger Error "Use -h to display help."
  exit 1
fi


get_ext_ip() {
  # get external ip using either 
  # 1) ip.hetzner.com
  # 2) own server backend using "ping.php"
  # 3) fritzbox backend call
  local response=""
  local at_part
  if [[ "$1" = 'hetzner' ]]; then
    if [[ "$2" == '-6' ]]; then 
      # ipv6
      response=$(curl -s6  ${ext_ip_resolver} | grep -E '^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$')
    else
      # ipv4
      response=$(curl -s4  ${ext_ip_resolver} | grep -E '^([0-9]+(\.|$)){4}')
    fi

  elif [[ "$1" = 'server' ]]; then
    # if you have a json backend on a private server, you can use that
    # jq
    local credentials
    local credential_curl
    local url
    # get credentials from json file if there are any
    credentials=$(jq -r .credentials "${localserver}")
    credential_curl=""
    # get server url from json
    url=$(jq -r .server_url "${localserver}")
    if [[ "$credentials" != "" ]]; then
        credential_curl="-u ${credentials}"
    fi

    if [[ "$url" != "" ]]; then
      response=$(curl ${credential_curl} "${url}" | jq -r '.REMOTE_ADDR')
    else
      logger Error "Missing server_url in ${localserver}"
    fi
  elif [[ "$1" = 'fritzbox' ]]; then
    # use a bash file based on https://wiki.ubuntuusers.de/FritzBox/Skripte/
    response=$(bash localservice.sh)
  fi
  echo "$response"
}



# get current public ip address
if [[ "${record_type}" = "AAAA" ]]; then
  logger Info "Using IPv6, because AAAA was set as record type."
  cur_pub_addr=$(get_ext_ip "$ext_ip_resolver_type" '-6')
  
  if [[ "${cur_pub_addr}" = "" ]]; then
    logger Error "It seems you don't have a IPv6 public address."
    exit 1
  else
    logger Info "Current public IP address: ${cur_pub_addr}"
  fi
elif [[ "${record_type}" = "A" ]]; then
  logger Info "Using IPv4, because A was set as record type."
  cur_pub_addr=$(get_ext_ip "$ext_ip_resolver_type" '-4')
  
  if [[ "${cur_pub_addr}" = "" ]]; then
    logger Error "Apparently there is a problem in determining the public ip address."
    exit 1
  else
    logger Info "Current public IP address: ${cur_pub_addr}"
  fi
else 
  logger Error "Only record type \"A\" or \"AAAA\" are support for DynDNS."
  exit 1
fi

# get record id if not given as parameter
if [[ "${record_id}" = "" ]]; then
    record_zone=$(curl -s -w "\n%{http_code}" --location --request GET "https://api.hetzner.cloud/v1/zones/${zone_id}/rrsets?name=&type=${record_type}&label_selector=&sort=id&page=1&per_page=25" \
  --header "Authorization: Bearer ${auth_api_token}")

  http_code=$(echo "${record_zone}" | tail -n 1 )
  if [[ "${http_code}" != "200" ]]; then
    logger Error "HTTP Response ${http_code} - Aborting run to prevent multipe records."
    exit 1
  else 
    record_set=$(echo ${record_zone} | jq | sed '$d' | jq --raw-output '.rrsets [] | select(.type == "'${record_type}'") | select(.name == "'${record_name}'")')
    record_id=$(echo $record_set | jq -r '.id')
  fi
fi 

logger Info "Record_ID: ${record_id}"

if [[ "${record_id}" = "" ]]; then
  echo "DNS record \"${record_name}\" does not exists"
  # create hetzner record
  curl -s -o /dev/null -w "%{http_code}\n" "https://api.hetzner.cloud/v1/zones/${zone_id}/rrsets/www/${record_type}/actions/add_records" \
  --request POST \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer ${auth_api_token}" \
 --data '{
    "ttl": '"${record_ttl}"',
    "records": [
      {
        "value": "'"${cur_pub_addr}"'",
        "comment": "Dyn DNS POST"
      }
    ]
  }'

  #  debug

  #     cmd=$(cat <<EOF
  #       curl -s -o /dev/null -w "%{http_code}\n" "https://api.hetzner.cloud/v1/zones/${zone_id}/rrsets/${record_id}/actions/set_records" \
  #         --request POST \
  #         --header 'Content-Type: application/json' \
  #         --header "Authorization: Bearer ${auth_api_token}" \
  #         --data '{
  #           "records": [
  #             {
  #               "value": "'"${cur_pub_addr}"'",
  #               "comment": "UPDATE IP: Dyn DNS POST"
  #             }
  #           ]
  #         }'
  # EOF
  # )

  # debug "$cmd"

      # curl -s -X "POST" "https://dns.hetzner.com/api/v1/records" \
      #  -H 'Content-Type: application/json' \
      #  -H 'Auth-API-Token: '${auth_api_token} \
      #  -d $'{
      #     "value": "'${cur_pub_addr}'",
      #     "ttl": '${record_ttl}',
      #     "type": "'${record_type}'",
      #     "name": "'${record_name}'",
      #     "zone_id": "'${zone_id}'"
      #   }'
else
# check if update is needed
  # cur_dyn_addr=`curl -s "https://dns.hetzner.com/api/v1/records/${record_id}" -H 'Auth-API-Token: '${auth_api_token} | jq --raw-output '.record.value'`
  cur_dyn_addr=$(echo $record_set | jq -r '.records[0]|.value')
  logger Info "Currently set IP address: ${cur_dyn_addr}"
# update existing record
  if [[ $cur_pub_addr == $cur_dyn_addr ]]; then
    logger Info "DNS record \"${record_name}\" is up to date - nothing to to."
    exit 0
  else
    logger Info "DNS record \"${record_name}\" is no longer valid - updating record"
    
    curl --fail-with-body \
    -X POST \
    -H "Authorization: Bearer ${auth_api_token}" \
    -H "Content-Type: application/json" \
    --data '{
      "records":[
      {
          "value":"'"${cur_pub_addr}"'",
          "comment":"UPDATE IP: Dyn DNS POST"
      }
    ]
    }' \
    "https://api.hetzner.cloud/v1/zones/${zone_id}/rrsets/${record_id}/actions/set_records"
    # curl -s -X "PUT" "https://dns.hetzner.com/api/v1/records/${record_id}" \
    #      -H 'Content-Type: application/json' \
    #      -H 'Auth-API-Token: '${auth_api_token} \
    #      -d $'{
    #        "value": "'${cur_pub_addr}'",
    #        "ttl": '${record_ttl}',
    #        "type": "'${record_type}'",
    #         "name": "'${record_name}'",
    #        "zone_id": "'${zone_id}'"
    #      }'

    if [[ $? != 0 ]]; then
      logger Error "Unable to update record: \"${record_name}\""
    else
      logger Info "DNS record \"${record_name}\" updated successfully"
    fi
  fi
fi
