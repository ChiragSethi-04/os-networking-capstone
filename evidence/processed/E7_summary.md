# E7 encryption proof

Source: `E7_20261124T040151.txt`

- HTTP payload readable in capture: YES
- HTTPS capture contains real encrypted application data (not just handshake): YES (42 frame(s) labelled Application Data)
- HTTPS payload opaque (no plaintext contact-form data visible): YES

## HTTP plaintext payload, decoded from tshark's hex field output
```
{"name":"E7","email":"e7@example.com","message":"plaintext capture test"}
{"name":"E7","email":"e7@example.com","message":"plaintext capture test"}
{"name":"E7","email":"e7@example.com","message":"plaintext capture test"}
```

## HTTP (tshark http.file_data, raw fields output)
```
+ visible payload ---
/api/contact	7b226e616d65223a224537222c22656d61696c223a226537406578616d706c652e636f6d222c226d657373616765223a22706c61696e7465787420636170747572652074657374227d
/api/contact	7b22737461747573223a227265636569766564227d0a
/api/contact	7b226e616d65223a224537222c22656d61696c223a226537406578616d706c652e636f6d222c226d657373616765223a22706c61696e7465787420636170747572652074657374227d
/api/contact	7b22737461747573223a227265636569766564227d0a
/api/contact	7b226e616d65223a224537222c22656d61696c223a226537406578616d706c652e636f6d222c226d657373616765223a22706c61696e7465787420636170747572652074657374227d
/api/contact	7b22737461747573223a227265636569766564227d0a
```

## HTTPS (tshark default packet summary - TLSv1.3 handshake then Application Data)
```
is opaque application data (no http dissection possible) ---
    1   0.000000 192.168.252.11 → 192.168.252.17 TCP 80 46164 → 443 [SYN] Seq=0 Win=64240 Len=0 MSS=1460 SACK_PERM TSval=3627311702 TSecr=0 WS=128
    2   0.000139 192.168.252.17 → 192.168.252.11 TCP 80 443 → 46164 [SYN, ACK] Seq=0 Ack=1 Win=65160 Len=0 MSS=1460 SACK_PERM TSval=3977634961 TSecr=3627311702 WS=256
    3   0.000604 192.168.252.11 → 192.168.252.17 TCP 72 46164 → 443 [ACK] Seq=1 Ack=1 Win=64256 Len=0 TSval=3627311703 TSecr=3977634961
    4   0.003452 192.168.252.11 → 192.168.252.17 TLSv1.2 1623 Client Hello
    5   0.003507 192.168.252.17 → 192.168.252.11 TCP 72 443 → 46164 [ACK] Seq=1 Ack=1552 Win=63744 Len=0 TSval=3977634965 TSecr=3627311706
    6   0.004883 192.168.252.17 → 192.168.252.11 TLSv1.3 1520 Server Hello, Change Cipher Spec, Application Data
    7   0.004888 192.168.252.17 → 192.168.252.11 TLSv1.3 581 Application Data, Application Data, Application Data
    8   0.006263 192.168.252.11 → 192.168.252.17 TCP 72 46164 → 443 [ACK] Seq=1552 Ack=1958 Win=62336 Len=0 TSval=3627311709 TSecr=3977634966
    9   0.008615 192.168.252.11 → 192.168.252.17 TLSv1.3 152 Change Cipher Spec, Application Data
   10   0.009326 192.168.252.11 → 192.168.252.17 TLSv1.3 306 Application Data
   11   0.009723 192.168.252.17 → 192.168.252.11 TLSv1.3 151 Application Data
   12   0.009818 192.168.252.11 → 192.168.252.17 TLSv1.3 120 Application Data
   13   0.010494 192.168.252.17 → 192.168.252.11 TLSv1.3 151 Application D
```
