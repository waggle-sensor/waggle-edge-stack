#!/bin/bash

kubectl exec svc/wes-rabbitmq -- openssl x509 -in /etc/rabbitmq/cert.pem -text