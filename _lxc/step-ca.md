---
slug: step-ca
title: step-ca
tags: [certificate-authority, pki, acme-server]
logo: /assets/logos/step-ca.webp
by: heinemannj
repo: https://github.com/smallstep/certificates
site: https://smallstep.com/docs/step-ca/
port: 443
cpu: 1
ram: 512
disk: 2
maintainer: heinemannj
---

step-ca is an online certificate authority for secure, automated X.509 and SSH certificate management for DevOps.

## Notes

- Access the provisioners dashboard at `https://{ip}/provisioners`.
- The CA listens on port 443 and an insecure port 80.
- Certificates, keys, and configuration are stored in `/etc/step-ca/`.
- A step-badger web UI is installed alongside step-ca.

## Links

- [GitHub](https://github.com/smallstep/certificates)
- [Documentation](https://smallstep.com/docs/step-ca/)
