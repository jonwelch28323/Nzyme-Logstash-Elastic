# Nzyme Logstash to Elastic

This project provides a Dockerized Logstash pipeline for ingesting data from a PostgreSQL database (such as nzyme) and forwarding it to an Elasticsearch cluster. It is designed for easy deployment and configuration using Docker Compose and environment variables.

---

## ⚠️ Security Warning

**This configuration is intended for lab, demo, or internal use only.**
- Environment variables (including passwords) are stored in plaintext in `.env`.
- The default PostgreSQL and Elasticsearch configurations may allow remote access.
- No authentication or network restrictions are enforced by default.
- Do not expose this setup to the public internet or use in production without additional security hardening.

---

## Features

- **Logstash** container with JDBC input for PostgreSQL
- Secure connection to Elasticsearch (supports SSL)
- Environment-based configuration for easy deployment
- Automatic download of the PostgreSQL JDBC driver
- Example pipeline configuration included
- **Interactive management script** for setup, container lifecycle, connection testing, and environment variable inspection

---

## Prerequisites

- [Docker](https://www.docker.com/products/docker-desktop)
- [Docker Compose](https://docs.docker.com/compose/)
- Access to a running PostgreSQL database (e.g., nzyme)
- Access to an Elasticsearch cluster

---

## Getting Started

### 1. Clone the Repository

```sh
git clone https://github.com/yourusername/nzyme_logstash.git
cd nzyme_logstash
```

### 2. Configure Environment Variables

Edit the `.env` file and set the following variables:

```ini
DOCKER_NETWORK=nzyme
LOGSTASH_VERSION=9.0.0

ELASTIC_HOST=your.elasticsearch.host
ELASTIC_PORT=9200
ELASTIC_USER=elastic
ELASTIC_PASSWORD=your_elastic_password

DATABASE_NAME=nzyme
DATABASE_USER=nzyme
DATABASE_PASSWORD=your_db_password
DATABASE_HOST=your.db.host
DATABASE_PORT=5432
```

> **Note:**  
> If your password contains a `$`, use `$$` in the `.env` file (e.g., `pa$$word` for `pa$word`).  
> Do **not** quote or escape passwords in any other way.

---

### 3. (Optional) Configure Logstash Pipeline

Edit `configs/logstash.conf` to customize the pipeline as needed.  
By default, it pulls data from PostgreSQL and outputs to Elasticsearch.

---

### 4. (Optional) Add SSL Certificates

If your Elasticsearch uses a self-signed certificate, place your CA certificate in `certs/ca/ca.crt` and update the pipeline config accordingly.

---

### 5. Use the Management Script

This project includes an enhanced interactive management script:  
**`stage_ecs_nzyme.sh`**

#### Make the script executable (Linux/macOS):

```sh
chmod +x stage_ecs_nzyme.sh
```

#### Run the script:

```sh
./stage_ecs_nzyme.sh
```

> **Recommended Workflow:**  
> 1. First run option 1 to test your connections to both Elasticsearch and PostgreSQL
> 2. If connections are successful, run option 2 to set up the Elasticsearch infrastructure
> 3. Use options 3-4 to stage and start your Logstash container
> 4. Monitor with option 7 for container status

#### Script Capabilities:

The interactive management script provides a user-friendly menu organized into logical sections:

**Setup & Configuration:**
- **Test connection to Elasticsearch and PostgreSQL** with enhanced visual feedback
  - Color-coded results (green ✓ for success, red ✗ for failure)
  - Automatic pause to review results before continuing
  - Uses credentials from `.env` file automatically (no manual password entry)
- Setup/Update ILM, templates, and datastreams in Elasticsearch

**Container Management:**
- Stage Logstash container (pull/create but do not start)
- Start Logstash container
- Stop Logstash container  
- Restart Logstash container
- Show container status
- Show environment variables inside Logstash container
- Delete Logstash container

**Data Management:**
- Delete all nzyme data streams and data from Elasticsearch

> **Connection Testing Features:**  
> The script now provides enhanced connection testing with color-coded output, clear visual separators, and automatic pausing so you can review the results. It automatically uses the database password from your `.env` file without prompting for manual entry.

> **After starting the Logstash container, the script will automatically display the environment variables inside the container so you can verify that all credentials are passed correctly.**

---

### 6. Allowing External Connections to nzyme's PostgreSQL Database

To allow Logstash (or any external service) to connect to the nzyme PostgreSQL database, you must configure PostgreSQL to accept external connections.

#### a. Edit `postgresql.conf`

Find and edit the `postgresql.conf` file (commonly located in `/etc/postgresql/<version>/main/` or `/var/lib/pgsql/data/`):

```
listen_addresses = '*'
```

This allows PostgreSQL to listen on all network interfaces.  
You can also specify a particular IP address if you prefer.

#### b. Edit `pg_hba.conf`

Find and edit the `pg_hba.conf` file (in the same directory as `postgresql.conf`).  
Add a line like this to allow password authentication from your network (replace `192.168.1.0/24` with your network or use `0.0.0.0/0` for all, but this is less secure):

```
host    nzyme    nzyme    192.168.1.0/24    md5
```

- The columns are: `host`, `database`, `user`, `address`, `authentication method`.
- For maximum compatibility, you can use:
  ```
  host    all    all    0.0.0.0/0    md5
  ```
  (Not recommended for production without firewalling.)

#### c. Restart PostgreSQL

After making these changes, restart the PostgreSQL service:

**On Ubuntu/Debian:**
```sh
sudo systemctl restart postgresql
```

**On CentOS/RHEL:**
```sh
sudo systemctl restart postgresql
```

**Or using Docker:**
```sh
docker restart <postgres_container_name>
```

#### d. Verify Connectivity

From the Logstash container or host, test the connection:

```sh
psql -h <nzyme_db_host> -U nzyme -d nzyme
```

---

## File Structure

```
nzyme_logstash/
├── configs/
│   ├── logstash.conf
│   └── postgresql-42.7.6.jar (optional, auto-downloaded if missing)
├── certs/
│   └── ca/ca.crt (optional, for SSL)
├── .env
├── docker-compose.yml
├── stage_ecs_nzyme.sh
└── logstash-entrypoint.sh
```

---

## Troubleshooting

- **Environment Variable Errors:**  
  Ensure all required variables are set in `.env` and referenced in `docker-compose.yml`. The script automatically loads environment variables from the `.env` file.

- **Connection Testing:**  
  Use option 1 in the management script to test both Elasticsearch and PostgreSQL connections. The script will display color-coded results and pause for you to review them. Green checkmarks (✓) indicate success, red X marks (✗) indicate failures.

- **Password Not Passed Correctly:**  
  If your password contains `$`, use `$$` in `.env`.  
  Do **not** source `.env` in your shell before running the script. The script handles environment variable loading automatically.

- **SSL Certificate Errors:**  
  Make sure the CA certificate is mounted and the path matches in your Logstash config.

- **JDBC Driver Issues:**  
  The entrypoint script will attempt to download the driver if missing. Ensure the container has internet access.

- **Elasticsearch Connection Issues:**  
  Check network connectivity and credentials using the connection test feature in the management script.

---

## Customization

- **Change the SQL Query:**  
  Edit the `statement` in `logstash.conf` to pull the data you need.

- **Add More Pipelines:**  
  Add more `.conf` files to the `pipeline` directory and update the Docker Compose volumes if needed.

---

## Connection String Explanation

The JDBC connection string used in this project is:

```
jdbc:postgresql://${DATABASE_HOST}:${DATABASE_PORT}/${DATABASE_NAME}
```

- **jdbc:**  
  Specifies the use of the JDBC protocol.

- **postgresql:**  
  The JDBC driver subprotocol for PostgreSQL databases.

- **${DATABASE_HOST}:**  
  The hostname or IP address of your PostgreSQL server, set via environment variable.

- **${DATABASE_PORT}:**  
  The port number for your PostgreSQL server, set via environment variable.

- **${DATABASE_NAME}:**  
  The name of the database to connect to, set via environment variable.

Example with values substituted:
```
jdbc:postgresql://172.16.68.22:5432/nzyme
```

---

## License

MIT License

---

## Credits

- [Elastic Logstash](https://www.elastic.co/logstash/)
- [nzyme](https://www.nzyme.org/)
- [PostgreSQL JDBC Driver](https://jdbc.postgresql.org/)

---

**Questions or issues?**  
Open an issue or visit [Elastic Discuss](https://discuss.elastic.co/c/logstash)
