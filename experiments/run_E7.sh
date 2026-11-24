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

# Port 80 normally 301-redirects everything to HTTPS (Phase 3 hardening),
# so a plain POST to it gets no payload at all to capture - not "plaintext
# payload" but "no payload, redirected". Swap in a temporary config that
# serves /api/ directly on port 80 for this one capture, then swap the
# real hardened config straight back. See docs/decisions.md.
echo "--- temporarily serving /api/ over plain HTTP for the capture ---" >> "$OUT"
mp_retry multipass transfer lab/configs/nginx/meridian-e7-plaintext.conf.template web:/tmp/meridian-e7-plaintext.conf
mp_retry multipass exec web -- sudo bash -c 'cp /etc/nginx/sites-available/meridian.conf /tmp/meridian.conf.e7-backup && mv /tmp/meridian-e7-plaintext.conf /etc/nginx/sites-available/meridian.conf && nginx -t && systemctl reload nginx'

echo "--- capturing HTTP traffic ---" >> "$OUT"
mp_retry multipass exec web -- sudo bash -c "rm -f /tmp/http.pcap; nohup tcpdump -i any -w /tmp/http.pcap port 80 > /tmp/tcpdump_http.log 2>&1 & echo \$! > /tmp/tcpdump_http.pid"
sleep 3
# Each curl is sent 3 times with a 1s gap, not once: the first capture
# attempt only ever showed TLS record types 22 (Handshake) and 20
# (ChangeCipherSpec), never 23 (Application Data) - the actual POST/
# response exchange was being missed by the capture window even though
# curl itself returned successfully, almost certainly a timing race on
# this VM under load, not a config issue (confirmed: the HTTP side's
# plaintext payload captures fine). Sending several requests widens the
# window without having to guess the exact right sleep duration. See
# docs/decisions.md.
for i in 1 2 3; do
  mp_retry multipass exec attacker -- bash -c "curl -s -X POST -H 'Content-Type: application/json' -d '{\"name\":\"E7\",\"email\":\"e7@example.com\",\"message\":\"plaintext capture test\"}' http://${WEB_IP}/api/contact" >> "$OUT" 2>&1
  sleep 1
done
sleep 3
mp_retry multipass exec web -- bash -c "sudo kill \$(cat /tmp/tcpdump_http.pid) 2>/dev/null; for i in 1 2 3 4 5; do kill -0 \$(cat /tmp/tcpdump_http.pid) 2>/dev/null || break; sleep 1; done; sync"

echo "--- restoring the real hardened config (301 redirect) ---" >> "$OUT"
mp_retry multipass exec web -- sudo bash -c 'mv /tmp/meridian.conf.e7-backup /etc/nginx/sites-available/meridian.conf && nginx -t && systemctl reload nginx'

echo "--- capturing HTTPS traffic ---" >> "$OUT"
mp_retry multipass exec web -- sudo bash -c "rm -f /tmp/https.pcap; nohup tcpdump -i any -w /tmp/https.pcap port 443 > /tmp/tcpdump_https.log 2>&1 & echo \$! > /tmp/tcpdump_https.pid"
sleep 3
for i in 1 2 3; do
  mp_retry multipass exec attacker -- bash -c "curl -sk -X POST -H 'Content-Type: application/json' -d '{\"name\":\"E7\",\"email\":\"e7@example.com\",\"message\":\"encrypted capture test\"}' https://${WEB_IP}/api/contact" >> "$OUT" 2>&1
  sleep 1
done
sleep 3
mp_retry multipass exec web -- bash -c "sudo kill \$(cat /tmp/tcpdump_https.pid) 2>/dev/null; for i in 1 2 3 4 5; do kill -0 \$(cat /tmp/tcpdump_https.pid) 2>/dev/null || break; sleep 1; done; sync"

mp_retry multipass transfer web:/tmp/http.pcap evidence/raw/http.pcap
mp_retry multipass transfer web:/tmp/https.pcap evidence/raw/https.pcap

echo "--- tshark: HTTP request URI + visible payload ---" >> "$OUT"
tshark -r evidence/raw/http.pcap -Y http -T fields -e http.request.uri -e http.file_data >> "$OUT" 2>&1 || true

# `-T fields -e tls.record.content_type` was tried first and only ever
# showed types 22/20 (Handshake/ChangeCipherSpec), never 23 (Application
# Data) - looked like the real exchange was being missed by the capture.
# It wasn't: `tshark -r https.pcap -Y "frame.number==N"` on the very
# frames the field extraction skipped shows them labelled directly as
# "TLSv1.3 ... Application Data" (sometimes several per frame) - Wireshark's
# TLS 1.3 dissector doesn't always populate the raw per-record
# `tls.record.content_type` field when the outer type is already implied
# by the fully-encrypted post-handshake stream. Wireshark's own default
# packet summary, which this uses instead, is not subject to that gap.
echo "--- tshark: HTTPS is opaque application data (no http dissection possible) ---" >> "$OUT"
tshark -r evidence/raw/https.pcap >> "$OUT" 2>&1 || true

echo "E7 raw output: $OUT (pcaps saved to evidence/raw/http.pcap, https.pcap, gitignored)"
