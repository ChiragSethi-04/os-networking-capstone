# E7 encryption proof

Source: `E7_20261121T235947.txt`

- HTTP payload readable in capture: YES
- HTTPS payload opaque (no plaintext contact-form data visible): YES

## HTTP plaintext payload, decoded from tshark's hex field output
```
{"name":"E7","email":"e7@example.com","message":"plaintext capture test"}
```

## HTTP (tshark http.file_data, raw fields output)
```
+ visible payload ---
/api/contact	7b226e616d65223a224537222c22656d61696c223a226537406578616d706c652e636f6d222c226d657373616765223a22706c61696e7465787420636170747572652074657374227d
/api/contact	7b22737461747573223a227265636569766564227d0a
```

## HTTPS (tshark tls.record.content_type - opaque application data, type 23)
```
is opaque application data (no http dissection possible) ---
22
22,20

20









22
22,20
20
```
