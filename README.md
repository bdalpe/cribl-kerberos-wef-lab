# Mock Windows Event Forwarder + Kerberos Lab

This repo is a self-contained lab with the following:
* [Kerberos Key Distribution Center (KDC)](kdc)
* [Standalone Cribl Stream instance](cribl)
* [Custom Python WEF Client](sender)

It is mean to experiment with the Cribl Windows Event Forwarder (WEF) source without having to set up a full Microsoft Windows Active Directory (AD) infrastructure.

## Using

To use this lab, run the following command:

```bash
docker compose up
```

Cribl Stream can be accessed at http://localhost:9000 (username: `cribl`/ password: `cribl`)

To see additional logging from the sender, change the `LOG_LEVEL` environment variable to `DEBUG` for the sender service in [docker-compose.yml](docker-compose.yml).

## Reference

The Python script is inspired by this StackOverflow post: [Encrypt message body using kerberos](https://stackoverflow.com/questions/78571748/encrypt-message-body-using-kerberos)

Details regarding the WEC server and HTTP payloads can be found in [this presentation on OpenWEC](https://www.sstic.org/media/SSTIC2023/SSTIC-actes/openwec/SSTIC2023-Slides-openwec-ruello_bruneau_UYtGHmF.pdf) (an open source implementation of the WEC).

The Dockerized Kerberos KDC is from this GitHub project: [docker-kerberos](https://github.com/ist-dsi/docker-kerberos
)

General purpose troubleshooting resources for Kerberos can be found here: [Use Kerberos authentication to connect to Windows hosts](https://github.com/kurokobo/awx-on-k3s/blob/main/tips/use-kerberos.md)
