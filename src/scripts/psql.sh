#!/bin/bash
echo "Running psql: $DATABASE_USERNAME@$DATABASE_HOSTNAME:$DATABASE_PORT - $DATABASE_NAME"
PGCONNECT_TIMEOUT=3 PGPASSWORD=$DATABASE_PASSWORD psql -h $DATABASE_HOSTNAME -p $DATABASE_PORT -U $DATABASE_USERNAME $DATABASE_NAME $@
