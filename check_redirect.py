#!/usr/bin/env python2.7

import requests
import sys
import os

url = sys.argv[1]
response = requests.get(url)
print response.url

