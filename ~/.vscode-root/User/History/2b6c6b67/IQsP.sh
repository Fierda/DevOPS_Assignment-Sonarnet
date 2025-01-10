#!/bin/bash

# Load environment variables
if [ -f .env ]; then
    source .env
else
    DB_USER=${DB_USER:-popo}
    DB_PASSWORD=${DB_PASSWORD:-baba4678}
fi

# Create required networks
docker network create sonarnet || true

# Create volumes for data persistence
docker volume create sonar_data
docker volume create sonar_extensions
docker volume create sonar_logs
docker volume create postgres_data

# Download sonar-golang plugin
echo "Downloading sonar-golang plugin..."
mkdir -p plugins
curl -sSL -o plugins/sonar-go-plugin.jar \
    https://github.com/SonarSource/sonar-go/releases/download/x.y.z/sonar-go-plugin-x.y.z.jar

# Deploy PostgreSQL primary
echo "Starting PostgreSQL..."
docker run -d --name postgres-primary \
    --network sonarnet \
    --restart unless-stopped \
    -e POSTGRES_USER="${DB_USER}" \
    -e POSTGRES_PASSWORD="${DB_PASSWORD}" \
    -e POSTGRES_DB=sonar \
    -v postgres_data:/var/lib/postgresql/data \
    postgres:13

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
sleep 10

# Deploy PostgreSQL replica
echo "Starting PostgreSQL replica..."
docker run -d --name postgres-replica \
    --network sonarnet \
    --restart unless-stopped \
    -e POSTGRES_USER="${DB_USER}" \
    -e POSTGRES_PASSWORD="${DB_PASSWORD}" \
    -e POSTGRES_DB=sonar \
    postgres:13

# Deploy pgAdmin
echo "Starting pgAdmin..."
docker run -d --name pgadmin \
    --network sonarnet \
    --restart unless-stopped \
    -p 4100:80 \
    -e PGADMIN_DEFAULT_EMAIL=admin@admin.com \
    -e PGADMIN_DEFAULT_PASSWORD=admin \
    dpage/pgadmin4:latest

# Deploy first SonarQube instance
echo "Starting SonarQube instance 1..."
docker run -d --name sonarqube1 \
    --network sonarnet \
    --restart unless-stopped \
    -p 9000:9000 \
    -e SONAR_JDBC_USERNAME="${DB_USER}" \
    -e SONAR_JDBC_PASSWORD="${DB_PASSWORD}" \
    -e SONAR_JDBC_URL="jdbc:postgresql://postgres-primary:5432/sonar" \
    -v sonar_data:/opt/sonarqube/data \
    -v sonar_extensions:/opt/sonarqube/extensions \
    -v sonar_logs:/opt/sonarqube/logs \
    -v $(pwd)/plugins:/opt/sonarqube/extensions/plugins \
    sonarqube:latest

# Deploy second SonarQube instance (on different port)
echo "Starting SonarQube instance 2..."
docker run -d --name sonarqube2 \
    --network sonarnet \
    --restart unless-stopped \
    -p 9001:9000 \
    -e SONAR_JDBC_USERNAME="${DB_USER}" \
    -e SONAR_JDBC_PASSWORD="${DB_PASSWORD}" \
    -e SONAR_JDBC_URL="jdbc:postgresql://postgres-primary:5432/sonar" \
    -v sonar_data:/opt/sonarqube/data \
    -v sonar_extensions:/opt/sonarqube/extensions \
    -v sonar_logs:/opt/sonarqube/logs \
    -v $(pwd)/plugins:/opt/sonarqube/extensions/plugins \
    sonarqube:latest

# Add nginx load balancer
echo "Setting up Nginx load balancer..."
cat << EOF > nginx.conf
events {
    worker_connections 1024;
}

http {
    upstream sonarqube {
        server sonarqube1:9000;
        server sonarqube2:9001;
    }

    server {
        listen 80;
        
        location / {
            proxy_pass http://sonarqube;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }
}
EOF

docker run -d --name nginx \
    --network sonarnet \
    --restart unless-stopped \
    -p 4080:80 \
    -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro \
    nginx:latest

echo "Deployment completed!"
echo "SonarQube will be available at:"
echo "  - http://localhost:9000 (Instance 1)"
echo "  - http://localhost:9001 (Instance 2)"
echo ""
echo "Please wait a few minutes for SonarQube to initialize completely."