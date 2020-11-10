#!/bin/bash
source config.sh

psql -q $RECIPE_ENGINE -f sql/build.sql
