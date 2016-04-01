#!/usr/bin/env python2.7

import requests
import sys
import os

requests.packages.urllib3.disable_warnings()

url = sys.argv[1]
response = requests.get(url, verify=False)
print response.url

