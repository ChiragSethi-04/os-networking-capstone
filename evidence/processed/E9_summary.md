# E9 TLS quality (testssl.sh)

## Before hardening
Grade: N/A_no_TLS_listener
```

```

## After hardening
Grade: B
```
 SSLv2      not offered (OK)
 SSLv3      not offered (OK)
 TLS 1      not offered
 TLS 1.1    not offered
 TLS 1.2    offered (OK)
 TLS 1.3    offered (OK): final
SSLv2
SSLv3
 TLS 1.2 sig_algs offered:    ECDSA+SHA512 ECDSA+SHA384 ECDSA+SHA256 
 TLS 1.3 sig_algs offered:    ECDSA+SHA256 
 TLS 1.3 early data support   no early data offered
 POODLE, SSL (CVE-2014-3566)               not vulnerable (OK), no SSLv3 support
 TLS_FALLBACK_SCSV (RFC 7507)              No fallback possible (OK), no protocol below TLS 1.2 offered
                                           no RSA certificate, thus certificate can't be used with SSLv2 elsewhere
 LOGJAM (CVE-2015-4000), experimental      not vulnerable (OK): no DH EXPORT ciphers, no DH key detected with <= TLS 1.2
```
