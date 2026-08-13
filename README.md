# CNI ARP Spoofing Test

Demonstrates an ARP spoofing man-in-the-middle attack on a Kubernetes cluster using the bridge CNI plugin.

## Prerequisites

- [kind](https://kind.sigs.k8s.io/)
- [Docker](https://www.docker.com/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Quick Start

```bash
make deploy                # Create kind cluster with bridge CNI
make build-arp-poison      # Build the arp-poison image (used by client and arp-poison pods)
make deploy-client-server  # Deploy server and client pods
make deploy-arp-poison     # Deploy the ARP poisoning pod
```

Watch the client:

```bash
make client-logs
```

Watch the captured traffic:

```bash
make arp-poison-logs
```

## Architecture

A single-node kind cluster with the default CNI disabled, replaced by the [bridge CNI plugin](https://www.cni.dev/plugins/current/main/bridge/) configured with `isDefaultGateway: true`. All pods share the `10.10.0.0/16` subnet on a Linux bridge (`mynet0`).

- **server** — `agnhost netexec --http-port=8080`, exposed via ClusterIP Service `server-svc`
- **client** — discovers the server pod IP via `kubectl`, then curls `http://<server-pod-ip>:8080/clientip` every second
- **arp-poison** — privileged pod that runs bidirectional ARP spoofing (`arpspoof -r`) between the client and server pods, then captures traffic with tcpdump

The client curls the server's pod IP directly (bypassing kube-proxy/iptables DNAT) so that traffic stays on the L2 bridge, making it interceptable via ARP spoofing.

## How It Works

The bridge CNI plugin connects all pods to a shared Linux bridge (`mynet0`). Pods communicate over this bridge at L2, resolving each other's MAC addresses via ARP. The bridge does not validate ARP replies, which makes it vulnerable to ARP spoofing.

The attack works as follows:

1. The **arp-poison** pod discovers the client and server pod IPs via `kubectl`.
2. It enables IP forwarding (`net.ipv4.ip_forward=1`) so it can relay traffic between the two.
3. It runs `arpspoof -r -t <client-ip> <server-ip>`, which sends forged ARP replies to both pods:
   - Tells the **client** that the server's IP is at the attacker's MAC address.
   - Tells the **server** that the client's IP is at the attacker's MAC address.
4. Both pods update their ARP tables and start sending traffic to the attacker's MAC instead of each other's.
5. The attacker forwards the traffic transparently (due to IP forwarding), so the connection stays alive.
6. `tcpdump -l -nne -A` captures and prints all intercepted packets, including plaintext HTTP request and response bodies.

This demonstrates why a flat L2 network without ARP spoofing protection (e.g., the bridge CNI's `macspoofchk` option or network policies) is vulnerable to MITM attacks from any pod on the same bridge.

## Example Output

`make arp-poison-logs` shows the MITM pod intercepting HTTP traffic between the client and server. The captured packets include the full HTTP response with the client's IP:

```
12:57:01.742973 ae:f1:96:b8:46:b5 > 22:c2:c4:04:8e:15, ethertype IPv4 (0x0800), length 199: 10.10.0.27.8080 > 10.10.0.28.52598: Flags [P.], seq 1:134, ack 88, win 509, options [nop,nop,TS val 1202796902 ecr 1928340263], length 133: HTTP: HTTP/1.1 200 OK
E...U.@.?...

..

.....vC.`S...|...........
G.9fr.#'HTTP/1.1 200 OK
Date: Thu, 13 Aug 2026 12:57:01 GMT
Content-Length: 16
Content-Type: text/plain; charset=utf-8

10.10.0.28:52598
```

The HTTP response body (`10.10.0.28:52598`) is the client's pod IP and source port as seen by the server — visible in plaintext to the MITM attacker.

## Cleanup

Full cleanup (delete cluster and remove Docker image):

```bash
make clean
```

## Make Targets

```
make help
```

## Note

This prototype was nearly entirely written with AI (Claude Code).
