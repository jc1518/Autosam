#!/bin/bash
clear
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "Autosam works at" `date +%Y-%m-%d-%H:%M`
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo ""

echo "============================================================"
echo " Step one: Test changes in staging if there are any"
echo "============================================================"
./test_staging.sh

echo ""
echo "============================================================"
echo " Step two: Test changes in production if there are any"
echo "============================================================"
./test_production.sh

echo ""
echo "============================================================"
echo " Step there: Add new redirect if there are any"
echo "============================================================"
./autosam_v2.sh
