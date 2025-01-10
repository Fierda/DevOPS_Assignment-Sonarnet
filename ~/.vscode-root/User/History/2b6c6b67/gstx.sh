#!/bin/bash

# Load environment variables
if [ -f .env ]; then
    source .env
else
    DB_USER=${DB_USER:-popo}
    DB_PASSWORD=${DB_PASSWORD:-baba4678}
fi

# Create required networks
docker network create sonarnet

# Create volumes for data persistence
docker volume create sonar_data
docker volume create sonar_extensions
docker volume create sonar_logs
docker volume create postgres_data

# Deploy PostgreSQL with replication (Primary)
docker run -d --name postgres-primary \
    --network sonarnet \
    -e POSTGRES_USER="${DB_USER}" \
    -e POSTGRES_PASSWORD="${DB_PASSWORD}" \
    -e POSTGRES_DB=sonar \
    -v postgres_data:/var/lib/postgresql/data \
    -e POSTGRES_REPLICATION_MODE=master \
    -e POSTGRES_REPLICATION_USER=repl_user \
    -e POSTGRES_REPLICATION_PASSWORD=repl_password \
    postgres:13

# Deploy PostgreSQL replica
docker run -d --name postgres-replica \
    --network sonarnet \
    -e POSTGRES_USER="${DB_USER}" \
    -e POSTGRES_PASSWORD="${DB_PASSWORD}" \
    -e POSTGRES_DB=sonar \
    -e POSTGRES_REPLICATION_MODE=slave \
    -e POSTGRES_REPLICATION_USER=repl_user \
    -e POSTGRES_REPLICATION_PASSWORD=repl_password \
    -e POSTGRES_MASTER_HOST=postgres-primary \
    postgres:13

# Deploy SonarQube with redundancy using Docker Swarm
docker swarm init

# Create Docker config for sonar.properties
cat << EOF > sonar.properties
sonar.jdbc.username=${DB_USER}
sonar.jdbc.password=${DB_PASSWORD}
sonar.jdbc.url=jdbc:postgresql://postgres-primary:5432/sonar
sonar.search.javaAdditionalOpts=-Dbootstrap.system_call_filter=false
EOF

docker config create sonar_properties sonar.properties

# Deploy SonarQube stack
docker stack deploy -c - sonarqube << EOF
version: '3.8'
services:
  sonarqube:
    image: sonarqube:latest
    ports:
      - "9000:9000"
    networks:
      - sonarnet
    environment:
      - SONAR_JDBC_USERNAME=${DB_USER}
      - SONAR_JDBC_PASSWORD=${DB_PASSWORD}
      - SONAR_JDBC_URL=jdbc:postgresql://postgres-primary:5432/sonar
    volumes:
      - sonar_data:/opt/sonarqube/data
      - sonar_extensions:/opt/sonarqube/extensions
      - sonar_logs:/opt/sonarqube/logs
    configs:
      - source: sonar_properties
        target: /opt/sonarqube/conf/sonar.properties
    deploy:
      replicas: 2
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
        max_attempts: 3
        window: 120s

networks:
  sonarnet:
    external: true
EOF

# Wait for SonarQube to be ready
echo "Waiting for SonarQube to start..."
sleep 30