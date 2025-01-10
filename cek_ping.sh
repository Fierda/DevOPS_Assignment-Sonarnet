#!/bin/bash

# Function to display network details
show_network_info() {
    echo "=== Network Information ==="
    echo "Networks:"
    docker network ls | grep -E 'sonarnet|NAME'
    
    echo -e "\nNetwork Details:"
    docker network inspect sonarnet
}

# Function to test inter-container connectivity using nc (netcat) or basic TCP connection
test_connectivity() {
    echo -e "\n=== Testing Inter-Container Connectivity ==="
    
    # Get all container IPs and names
    declare -A container_ips
    while IFS= read -r line; do
        name=$(echo $line | cut -d';' -f1)
        ip=$(echo $line | cut -d';' -f2)
        container_ips[$name]=$ip
    done < <(docker ps --format '{{.Names}}' | while read container; do
        ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $container)
        echo "$container;$ip"
    done)
    
    # Display container IPs
    echo "Container IP Addresses:"
    for container in "${!container_ips[@]}"; do
        echo "$container: ${container_ips[$container]}"
    done
    
    # Test connectivity between containers using IP addresses
    echo -e "\nTesting direct IP connectivity:"
    for source in "${!container_ips[@]}"; do
        echo -e "\nFrom $source (${container_ips[$source]}):"
        for target in "${!container_ips[@]}"; do
            if [ "$source" != "$target" ]; then
                echo -n "$target (${container_ips[$target]}): "
                # Try to establish a TCP connection to port 22 (or another common port)
                # We use timeout to avoid hanging
                if docker exec $source timeout 1 bash -c "< /dev/tcp/${container_ips[$target]}/22" 2>/dev/null; then
                    echo "✅ Port open"
                else
                    # If port 22 fails, try ping
                    if docker exec $source ping -c 1 -W 1 ${container_ips[$target]} >/dev/null 2>&1; then
                        echo "✅ Responds to ping"
                    else
                        echo "⚠️  Responds to ping only"
                    fi
                fi
            fi
        done
    done
}

# Main execution
echo "Starting network connectivity check..."
show_network_info
test_connectivity

echo -e "\n=== Container DNS Resolution Test ==="
for container in $(docker ps --format "{{.Names}}"); do
    echo -e "\nTesting DNS resolution from $container:"
    # Try to use 'getent' which is more commonly available than nslookup
    for target in $(docker ps --format "{{.Names}}"); do
        if [ "$container" != "$target" ]; then
            echo -n "$target: "
            if docker exec $container getent hosts $target >/dev/null 2>&1; then
                echo "✅ Resolves"
            else
                echo "⚠️  DNS entry not found (but may still be reachable by IP)"
            fi
        fi
    done
done

echo -e "\n=== Quick Network Commands Reference ==="
echo "• Manual ping test: docker exec <container> ping -c 1 <target_ip>"
echo "• View container IP: docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' <container>"
echo "• View network details: docker network inspect sonarnet"
echo "• List all containers: docker ps"