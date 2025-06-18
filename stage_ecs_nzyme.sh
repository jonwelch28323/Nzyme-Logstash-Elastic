#!/bin/bash

# Check for required dependencies
for dep in jq docker; do
  command -v $dep >/dev/null 2>&1 || { echo >&2 "$dep is required but not installed. Aborting."; exit 1; }
done

if ! command -v docker compose >/dev/null 2>&1; then
  echo "docker compose is required (v2+). Aborting."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not running or not accessible. Aborting."
  exit 1
fi

if [ ! -f .env ]; then
  echo ".env file not found in the current directory. Aborting."
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  PSQL_AVAILABLE=0
else
  PSQL_AVAILABLE=1
fi

# Convert .env to Unix line endings if needed
if file .env | grep -q CRLF; then
  echo "Converting .env to Unix (LF) line endings..."
  sed -i 's/\r$//' .env
fi

# Source environment variables from .env file
set -a  # automatically export all variables
source .env
set +a  # turn off automatic export

ES_URL="https://${ELASTIC_HOST}:${ELASTIC_PORT}"
ES_USER="${ELASTIC_USER}"
ES_PASS="${ELASTIC_PASSWORD}"
ES_CURL_OPTS="-k" # Ignore certificate errors

print_container_env() {
  if docker ps | grep -q logstash01; then
    echo "Environment variables inside logstash01 container:"
    docker exec -it logstash01 env | grep -E 'DATABASE|ELASTIC'
  else
    echo "Logstash container is not running."
  fi
}

manage_container() {
  case "$1" in
    stage)
      echo "Staging (pulling and creating) Logstash container, but not starting it..."
      docker compose create logstash01
      ;;
    start)
      if docker ps | grep -q logstash01; then
        echo "Logstash container is already running."
      else
        echo "Starting Logstash container..."
        docker compose --env-file .env up -d logstash01
        sleep 3
        print_container_env
      fi
      ;;
    stop)
      echo "Stopping Logstash container..."
      docker compose stop logstash01
      ;;
    restart)
      echo "Restarting Logstash container..."
      docker compose restart logstash01
      sleep 3
      print_container_env
      ;;
    delete)
      echo "Deleting Logstash container..."
      docker compose down
      ;;
    status)
      echo "Logstash container status:"
      docker compose ps logstash01
      ;;
    envtest)
      print_container_env
      ;;
    *)
      echo "Unknown container command: $1"
      ;;
  esac
}

delete_nzyme_data() {
  echo "WARNING: This will delete all nzyme data streams and their data from Elasticsearch!"
  read -p "Are you sure you want to proceed? (yes/no): " confirm
  if [[ "$confirm" =~ ^[Yy][Ee][Ss]$ || "$confirm" =~ ^[Yy]$ ]]; then
    declare -A SOURCES=(
      [wifi]="wifi"
      [bluetooth]="bluetooth"
      [alerts]="alerts"
      [uavs]="uavs"
      [disconnection_activity]="disconnections"
    )
    for source in "${!SOURCES[@]}"; do
      index_name="nzyme-$source"
      echo "Deleting data stream: $index_name"
      curl $ES_CURL_OPTS -u "$ES_USER:$ES_PASS" -s -X DELETE "$ES_URL/_data_stream/$index_name"
    done
    echo "Deleting all nzyme indices (if any remain)..."
    indices=$(curl $ES_CURL_OPTS -u "$ES_USER:$ES_PASS" -s "$ES_URL/_cat/indices/nzyme-*?h=index" | grep '^nzyme-' || true)
    for idx in $indices; do
      echo "Deleting index: $idx"
      curl $ES_CURL_OPTS -u "$ES_USER:$ES_PASS" -s -X DELETE "$ES_URL/$idx"
    done
    echo "All nzyme data streams and indices deleted."
  else
    echo "Delete operation cancelled."
  fi
}

test_connections() {
  # Color codes for better visibility
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m' # No Color

  echo ""
  echo -e "${BOLD}================================================================${NC}"
  echo -e "${BOLD}                    CONNECTION TEST RESULTS                     ${NC}"
  echo -e "${BOLD}================================================================${NC}"
  echo ""

  echo -e "${BLUE}Testing connection to Elasticsearch at $ES_URL ...${NC}"
  elastic_output=$(curl $ES_CURL_OPTS -u "$ES_USER:$ES_PASS" -s -w "\n%{http_code}" "$ES_URL")
  elastic_body=$(echo "$elastic_output" | head -n -1)
  elastic_code=$(echo "$elastic_output" | tail -n1)
  if [ "$elastic_code" = "200" ]; then
    echo -e "${GREEN}✓ Elasticsearch connection: SUCCESS${NC}"
  else
    echo -e "${RED}✗ Elasticsearch connection: FAILED (HTTP $elastic_code)${NC}"
    echo -e "${YELLOW}---- Elasticsearch Response ----${NC}"
    echo "$elastic_body"
    echo -e "${YELLOW}---- End Response ----${NC}"
    echo -e "${YELLOW}Check:${NC}"
    echo "- ELASTIC_HOST: $ELASTIC_HOST"
    echo "- ELASTIC_PORT: $ELASTIC_PORT"
    echo "- ELASTIC_USER: $ES_USER"
    echo "- Network connectivity and firewall"
    echo "- SSL certificate (if using self-signed, ensure -k is set or CA is trusted)"
  fi

  echo ""
  echo -e "${BLUE}Testing connection to PostgreSQL database at ${DATABASE_HOST:-localhost}:${DATABASE_PORT:-5432} ...${NC}"
  if [ "$PSQL_AVAILABLE" -eq 1 ]; then
    export PGPASSWORD="${DATABASE_PASSWORD}"
    psql_output=$(psql -h "${DATABASE_HOST:-localhost}" -p "${DATABASE_PORT:-5432}" -U "${DATABASE_USER:-postgres}" -d "${DATABASE_NAME:-postgres}" -c '\q' 2>&1)
    psql_exit_code=$?
    unset PGPASSWORD
    if [ $psql_exit_code -eq 0 ]; then
      echo -e "${GREEN}✓ PostgreSQL connection: SUCCESS${NC}"
    else
      echo -e "${RED}✗ PostgreSQL connection: FAILED${NC}"
      echo -e "${YELLOW}---- psql Output ----${NC}"
      echo "$psql_output"
      echo -e "${YELLOW}---- End Output ----${NC}"
      echo -e "${YELLOW}Check:${NC}"
      echo "- DATABASE_HOST: ${DATABASE_HOST:-localhost}"
      echo "- DATABASE_PORT: ${DATABASE_PORT:-5432}"
      echo "- DATABASE_USER: ${DATABASE_USER:-postgres}"
      echo "- DATABASE_NAME: ${DATABASE_NAME:-postgres}"
      echo "- DATABASE_PASSWORD: (set in .env)"
      echo "- PostgreSQL server is running and accessible"
      echo "- pg_hba.conf and postgresql.conf allow connections"
      echo "- Network connectivity and firewall"
    fi
  else
    echo -e "${YELLOW}⚠ psql command not found. Cannot test PostgreSQL connection.${NC}"
  fi
  
  echo ""
  echo -e "${BOLD}================================================================${NC}"
  echo -e "${BOLD}Connection testing complete. Please review the results above.${NC}"
  echo -e "${BOLD}================================================================${NC}"
  read -p "Press Enter to continue..."
}

setup_ilm_templates_datastreams() {
  echo "Testing connection to Elasticsearch at $ES_URL ..."
  test_response=$(curl $ES_CURL_OPTS -u "$ES_USER:$ES_PASS" -s -o /dev/null -w "%{http_code}" "$ES_URL")
  if [ "$test_response" != "200" ]; then
    echo "ERROR: Unable to connect to Elasticsearch at $ES_URL (HTTP $test_response)."
    echo "Check your .env settings, network connectivity, and credentials."
    return
  fi
  echo "Connection to Elasticsearch successful."

  ilm_response=$(curl $ES_CURL_OPTS -u "$ES_USER:$ES_PASS" -s -w "\n%{http_code}" -X PUT "$ES_URL/_ilm/policy/nzyme-default-ilm" -H 'Content-Type: application/json' -d '{
    "policy": {
      "phases": {
        "hot": {
          "actions": {
            "rollover": {
              "max_size": "5gb",
              "max_age": "30d"
            }
          }
        },
        "delete": {
          "min_age": "90d",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }')
  ilm_body=$(echo "$ilm_response" | head -n -1)
  ilm_code=$(echo "$ilm_response" | tail -n1)
  echo "ILM policy response: $ilm_body (HTTP $ilm_code)"

  declare -A SOURCES=(
    [wifi]="wifi"
    [bluetooth]="bluetooth"
    [alerts]="alerts"
    [uavs]="uavs"
    [disconnection_activity]="disconnections"
  )

  for source in "${!SOURCES[@]}"; do
    mapping_file="ECS_Field_Mappings/${SOURCES[$source]}.json"
    index_name="nzyme-$source"
    template_name="nzyme-${source}-template"

    if [ ! -f "$mapping_file" ]; then
      echo "Mapping file not found: $mapping_file. Skipping $index_name."
      continue
    fi
    mappings=$(jq '.mappings' "$mapping_file")

    template_response=$(curl $ES_CURL_OPTS -u "$ES_USER:$ES_PASS" -s -w "\n%{http_code}" -X PUT "$ES_URL/_index_template/$template_name" -H 'Content-Type: application/json' -d @- <<EOF
{
  "index_patterns": ["$index_name*"],
  "data_stream": {},
  "template": {
    "settings": {
      "index.lifecycle.name": "nzyme-default-ilm"
    },
    "mappings": $mappings
  },
  "priority": 500
}
EOF
)
    template_body=$(echo "$template_response" | head -n -1)
    template_code=$(echo "$template_response" | tail -n1)
    echo "Index template response for $template_name: $template_body (HTTP $template_code)"

    exists=$(curl $ES_CURL_OPTS -u "$ES_USER:$ES_PASS" -s -o /dev/null -w "%{http_code}" "$ES_URL/_data_stream/$index_name")
    if [ "$exists" = "404" ]; then
      ds_response=$(curl $ES_CURL_OPTS -u "$ES_USER:$ES_PASS" -s -w "\n%{http_code}" -X PUT "$ES_URL/_data_stream/$index_name")
      ds_body=$(echo "$ds_response" | head -n -1)
      ds_code=$(echo "$ds_response" | tail -n1)
      echo "Created data stream: $index_name - $ds_body (HTTP $ds_code)"
    else
      rollover_response=$(curl $ES_CURL_OPTS -u "$ES_USER:$ES_PASS" -s -w "\n%{http_code}" -X POST "$ES_URL/$index_name/_rollover" \
        -H 'Content-Type: application/json' \
        -d '{"conditions":{}}')
      rollover_body=$(echo "$rollover_response" | head -n -1)
      rollover_code=$(echo "$rollover_response" | tail -n1)
      echo "Data stream already exists: $index_name (forced rollover to apply new template and ILM if needed) - $rollover_body (HTTP $rollover_code)"
    fi
  done

  echo "Done. ILM policy, index templates, and data streams created or updated successfully."
}

show_help() {
  echo "Nzyme Logstash Management Script"
  echo "--------------------------------"
  echo "Setup & Configuration:"
  echo "1) Test connection to Elasticsearch and PostgreSQL"
  echo "2) Setup/Update ILM, templates, and datastreams"
  echo ""
  echo "Container Management:"
  echo "3) Stage Logstash container (pull/create but do not start)"
  echo "4) Start Logstash container"
  echo "5) Stop Logstash container"
  echo "6) Restart Logstash container"
  echo "7) Show Logstash container status"
  echo "8) Show environment variables inside Logstash container"
  echo "9) Delete Logstash container"
  echo ""
  echo "Data Management:"
  echo "10) Delete ALL nzyme data streams and data from Elasticsearch"
  echo ""
  echo "h) Help"
  echo "0) Exit"
}

while true; do
  echo ""
  show_help
  read -p "Enter your choice: " choice

  case "$choice" in
    1) test_connections ;;
    2) setup_ilm_templates_datastreams ;;
    3) manage_container stage ;;
    4) manage_container start ;;
    5) manage_container stop ;;
    6) manage_container restart ;;
    7) manage_container status ;;
    8) manage_container envtest ;;
    9) manage_container delete ;;
    10) delete_nzyme_data ;;
    h|help) show_help ;;
    0) echo "Exiting."; exit 0 ;;
    *) echo "Invalid option." ;;
  esac
done