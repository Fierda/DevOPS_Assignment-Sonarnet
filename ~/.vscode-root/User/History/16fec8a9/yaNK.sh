#!/bin/bash

# Function to check if Docker Swarm is initialized
check_swarm_status() {
    if ! docker info | grep -q "Swarm: active"; then
        echo "Docker Swarm is not initialized. Initializing..."
        docker swarm init
    fi
}

# Function to display network details
show_network_info() {
    echo "=== Network Information ==="
    echo "Networks:"
    docker network ls | grep -E 'sonarnet|NAME'
    
    echo -e "\nNetwork Details:"
    docker network inspect sonarnet
    
    echo -e "\n=== Container Connectivity ==="
    echo "Services and their networks:"
    docker service ls --format "table {{.Name}}\t{{.Ports}}"
    
    echo -e "\nContainer Network Details:"
    for container in $(docker ps --format "{{.Names}}"); do
        echo -e "\nContainer: $container"
        docker inspect -f '{{range .NetworkSettings.Networks}}{{printf "IP: %s\nNetwork: %s\n" .IPAddress .NetworkID}}{{end}}' "$container"
    done
}

# Function to test inter-container connectivity using Docker's DNS
test_connectivity() {
    echo -e "\n=== Testing Inter-Container Connectivity ==="
    
    # Get all container names
    containers=($(docker ps --format "{{.Names}}"))
    
    # Test connectivity between all containers
    for source in "${containers[@]}"; do
        echo -e "\nTesting connectivity from $source:"
        for target in "${containers[@]}"; do
            if [ "$source" != "$target" ]; then
                echo -n "$target: "
                # Using nslookup to test DNS resolution and connectivity
                docker exec "$source" nslookup "$target" >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    echo "✅ Connected"
                else
                    echo "❌ Failed"
                fi
            fi
        done
    done
}

# Function to show service logs
show_service_logs() {
    echo -e "\n=== Service Logs Summary ==="
    services=$(docker service ls --format "{{.Name}}")
    
    for service in $services; do
        echo -e "\nLogs for service: $service"
        docker service logs --tail 10 "$service" 2>&1 | head -n 5
    done
}

# Main execution
echo "Starting network connectivity check..."
check_swarm_status
show_network_info
test_connectivity
show_service_logs

echo -e "\n=== Quick Network Commands Reference ==="
echo "• View network details: docker network inspect sonarnet"
echo "• List all services: docker service ls"
echo "• View service tasks: docker service ps <service-name>"
echo "• View service logs: docker service logs <service-name>"