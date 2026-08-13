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

## Teardown

```bash
make undeploy  # Delete the entire kind cluster
```

## Make Targets

```
make help
```

## Note

This prototype was nearly entirely written with AI (Claude Code).
