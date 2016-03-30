#! /usr/bin/env python
# Cloudlets Edge Redirect module written by Jackie Chen
# 07/12/2015 - version 1.0 - Refernce "https://developer.akamai.com/api/luna/cloudlets/overview.html"

import requests, json, subprocess
from akamai.edgegrid import EdgeGridAuth
from urlparse import urljoin

class client(object):
	def __init__(self, baseUrl, clientToken, clientSecret, accessToken):
		self.baseUrl = baseUrl
		self.clientToken = clientToken
		self.clientSecret = clientSecret
		self.accessToken = accessToken
		self.session = requests.Session()
		self.session.auth = EdgeGridAuth(
				client_token=self.clientToken,
				client_secret=self.clientSecret,
				access_token=self.accessToken,
                                max_body=128*1024
				)
		self.headers = {'Content-Type': 'application/json'}

  # Groups
	def listGroups(self):
		return json.dumps(self.session.get(urljoin(self.baseUrl, '/cloudlets/api/v2/group-info')).json(), indent=2)

	def getGroup(self, groupId):
		self.groupId = groupId
		return json.dumps(self.session.get(urljoin(self.baseUrl, '/cloudlets/api/v2/group-info/'+self.groupId)).json(), indent=2)

  # Cloudlets
	def listCloudlets(self):
		return json.dumps(self.session.get(urljoin(self.baseUrl, '/cloudlets/api/v2/cloudlet-info')).json(), indent=2)

	def getCloudlet(self, cloudletId):
		self.cloudletId = cloudletId
		return json.dumps(self.session.get(urljoin(self.baseUrl, '/cloudlets/api/v2/cloudlet-info/'+self.cloudletId)).json(), indent=2)

	# Policies
	def listPolicies(self,groupId):
		self.groupId = groupId
		return json.dumps(self.session.get(urljoin(self.baseUrl, '/cloudlets/api/v2/policies?gid='+self.groupId+'&includeDeleted=false&cloudletId=0')).json(), indent=2)

	def getPolicy(self, policyId):
		self.policyId = policyId
		return json.dumps(self.session.get(urljoin(self.baseUrl, '/cloudlets/api/v2/policies/'+self.policyId)).json(), indent=2)

	# Policy Versions
	def getPolicyVersion(self, policyId, policyVersion):
		self.policyId = policyId
		self.policyVersion = policyVersion
		return json.dumps(self.session.get(urljoin(self.baseUrl, '/cloudlets/api/v2/policies/'+self.policyId+'/versions/'+self.policyVersion+'?omitRules=false&matchRuleFormat=1.0')).json(), indent=2)

	def updatePolicyVersion(self, policyId, policyVersion, policyRules):
		self.policyId = policyId
		self.policyVersion = policyVersion
		self.policyRules = """
		%(policyRules)s
		"""%{'policyRules':policyRules}
		return json.dumps(self.session.put(urljoin(self.baseUrl, '/cloudlets/api/v2/policies/'+self.policyId+'/versions/'+self.policyVersion+'?omitRules=false&matchRuleFormat=1.0'), data=self.policyRules, headers=self.headers).json(), indent=2)

	def createPolicyVersion(self, policyId, policyVersion, policyFile, policyNotes):
		self.policyId = policyId
		self.policyVersion = policyVersion
                self.policyFile = policyFile
                self.policyNotes = policyNotes
                with open(self.policyFile, 'r') as updates:
                    policyUpdates = updates.read()
                return json.dumps(self.session.post(urljoin(self.baseUrl, '/cloudlets/api/v2/policies/'+self.policyId+'/versions?includeRules=false&matchRuleFormat=1.0'), data="{\"matchRuleFormat\":\"1.0\", \"description\": \"Based on V"+self.policyVersion+self.policyNotes+"\", \"matchRules\":"+policyUpdates+"}", headers=self.headers).json(), indent=2)

  # Rules
	def createRule(self, fromUrl, toUrl, rule={}):
		self.fromUrl = fromUrl
		self.toUrl = toUrl
		self.rule = rule
		nSemi = fromUrl.find(':')
		nSlash = fromUrl.find('/', 8)
		fromHost = fromUrl[nSemi+3:nSlash]
		if '?' in self.fromUrl:
			nQuestion = fromUrl.find('?')
			fromProtocol = fromUrl[:nSemi]
			fromPath = fromUrl[nSlash:nQuestion]
			fromQuery = fromUrl[nQuestion+1:]
			#print "Use query string template"
			self.rule = """
			{
				"matchRules": [
					{
						"end": 0,
						"name": null,
						"matches": [
							{
								"matchValue": "%(fromProtocol)s",
								"caseSensitive": false,
								"matchType": "protocol",
								"negate": false,
								"matchOperator": "equals"
							},
							{
								"matchValue": "%(fromHost)s",
								"caseSensitive": false,
								"matchType": "hostname",
								"negate": false,
								"matchOperator": "equals"
							},
							{
								"matchValue": "%(fromPath)s",
								"caseSensitive": false,
								"matchType": "path",
								"negate": false,
								"matchOperator": "equals"
							},
							{
								"matchValue": "%(fromQuery)s",
								"caseSensitive": false,
								"matchType": "query",
								"negate": false,
								"matchOperator": "equals"
							}
						],
						"start": 0,
						"useIncomingQueryString": false,
						"redirectURL": "%(toUrl)s",
						"type": "erMatchRule",
						"id": 0,
						"matchURL": null,
						"statusCode": 301
					}
				]
			}
			"""%{'fromProtocol': fromProtocol, 'fromHost': fromHost, 'fromPath': fromPath, 'fromQuery': fromQuery, 'toUrl': self.toUrl}
		else:
			fromPath = fromUrl[nSlash:]
			#print "Use basic template"
			self.rule = """
			{
				"matchRules": [
					{
						"end": 0,
						"name": null,
						"start": 0,
						"useIncomingQueryString": false,
						"redirectURL": "%(toUrl)s",
						"type": "erMatchRule",
						"id": 0,
						"matchURL": "%(fromUrl)s",
						"statusCode": 301
					}
				]
			}
			"""%{'fromUrl': self.fromUrl, 'toUrl': self.toUrl}
		if len(fromPath) < 2:
			print "Error: Path (%s) is empty" %(fromPath)
			return False
		return self.rule

    # Activation
	def activateVersion(self, policyId, policyVersion, policyEnv):
		self.policyId = policyId
		self.policyVersion = policyVersion
                self.policyEnv = policyEnv
                return json.dumps(self.session.post(urljoin(self.baseUrl, '/cloudlets/api/v2/policies/'+self.policyId+'/versions/'+self.policyVersion+'/activations'), data="{\"network\":\""+self.policyEnv+"\"}", headers=self.headers).json(), indent=2)


