#!/usr/bin/env bash
# E7: encryption proof - tcpdump capture of HTTP vs HTTPS, analysed with
# tshark, showing readable payload vs encrypted payload.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p evidence/raw
OUT="evidence/raw/E7_$(date +%Y%m%dT%H%M%S).txt"
raw_header "E7" > "$OUT"

echo "--- capturing HTTP traffic ---" >> "$OUT"
multipass exec web -- sudo bash -c "rm -f /tmp/http.pcap; nohup tcpdump -i any -w /tmp/http.pcap port 80 > /tmp/tcpdump_http.log 2>&1 & echo \$! > /tmp/tcpdump_http.pid"
sleep 1
multipass exec attacker -- bash -c "curl -s -X POST -H 'Content-Type: application/json' -d '{\"name\":\"E7\",\"email\":\"e7@example.com\",\"message\":\"plaintext capture test\"}' http://${WEB_IP}/api/contact" >> "$OUT" 2>&1
sleep 1
multipass exec web -- bash -c "kill \$(cat /tmp/tcpdump_http.pid) 2>/dev/null; sleep 1"

echo "--- capturing HTTPS traffic ---" >> "$OUT"
multipass exec web -- sudo bash -c "rm -f /tmp/https.pcap; nohup tcpdump -i any -w /tmp/https.pcap port 443 > /tmp/tcpdump_https.log 2>&1 & echo \$! > /tmp/tcpdump_https.pid"
sleep 1
multipass exec attacker -- bash -c "curl -sk -X POST -H 'Content-Type: application/json' -d '{\"name\":\"E7\",\"email\":\"e7@example.com\",\"message\":\"encrypted capture test\"}' https://${WEB_IP}/api/contact" >> "$OUT" 2>&1
sleep 1
multipass exec web -- bash -c "kill \$(cat /tmp/tcpdump_https.pid) 2>/dev/null; sleep 1"

multipass transfer web:/tmp/http.pcap evidence/raw/http.pcap
multipass transfer web:/tmp/https.pcap evidence/raw/https.pcap

echo "--- tshark: HTTP request URI + visible payload ---" >> "$OUT"
tshark -r evidence/raw/http.pcap -Y http -T fields -e http.request.uri -e http.file_data >> "$OUT" 2>&1 || true

echo "--- tshark: HTTPS is opaque application data (no http dissection possible) ---" >> "$OUT"
tshark -r evidence/raw/https.pcap -Y tls -T fields -e tls.record.content_type >> "$OUT" 2>&1 || true

echo "E7 raw output: $OUT (pcaps saved to evidence/raw/http.pcap, https.pcap, gitignored)"
