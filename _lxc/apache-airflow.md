---
slug: apache-airflow
title: Apache Airflow
tags: [workflow, scheduler, automation]
logo: /assets/logos/apache-airflow.webp
by: MickLesk
repo: https://github.com/apache/airflow
site: https://airflow.apache.org/
port: 8080
cpu: 2
ram: 4096
disk: 16
maintainer: MickLesk
---

Apache Airflow is an open-source platform for developing, scheduling, and monitoring batch-oriented workflows. It uses Python to author DAGs (Directed Acyclic Graphs) that represent workflows, and provides a rich web UI for managing and observing pipelines.

## Notes

- The initial admin password is randomly generated and stored in /opt/airflow/.env (AIRFLOW_ADMIN_PASSWORD).
- Place your DAG files in /opt/airflow/dags/. The scheduler will pick them up automatically.
- This installs Airflow with LocalExecutor. For distributed task execution, configure CeleryExecutor manually.

## Links

- [Website](https://airflow.apache.org/)
- [GitHub](https://github.com/apache/airflow)
- [Documentation](https://airflow.apache.org/docs/)
