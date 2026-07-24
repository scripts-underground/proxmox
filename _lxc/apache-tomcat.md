---
slug: apache-tomcat
title: Apache Tomcat
tags: [webserver]
logo: /assets/logos/apache-tomcat.webp
by: MickLesk
repo: https://github.com/apache/tomcat
site: https://tomcat.apache.org/
port: 8080
cpu: 1
ram: 1024
disk: 5
maintainer: MickLesk
---

Apache Tomcat is an open-source implementation of the Jakarta Servlet, Jakarta Expression Language, and WebSocket technologies.

## Notes

- Access the web UI at `http://<ip>:8080` to verify the installation.
- Tomcat version and Java version can be customized by setting `TOMCAT_VERSION` and `JAVA_VERSION` environment variables before creation.
- Java 21 is installed by default with Tomcat 11.
- Updates preserve your configuration, webapps, and custom library jars.

## Links

- [GitHub](https://github.com/apache/tomcat)
- [Website](https://tomcat.apache.org/)
