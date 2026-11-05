import http.server,json,threading
class Handler(http.server.BaseHTTPRequestHandler):
 protocol_version='HTTP/1.1'
 def log_message(self,*a):pass
 def reply(self,status,body=b'',content='application/json',headers={}):
  self.send_response(status);self.send_header('Content-Type',content);self.send_header('Content-Length',str(len(body)))
  for k,v in headers.items():self.send_header(k,v)
  self.end_headers();self.wfile.write(body)
 def do_GET(self):self.reply(405)
 def do_DELETE(self):self.reply(204)
 def do_POST(self):
  req=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
  method=req.get('method');id=req.get('id')
  if self.headers.get('Authorization')!='Bearer fixture-token':return self.reply(401,b'{}')
  if method not in ['initialize','server/discover'] and self.headers.get('Mcp-Session-Id')!='fixture-session':return self.reply(400,b'{}')
  if id is None:return self.reply(202)
  if method=='initialize':result={'protocolVersion':'2025-06-18','capabilities':{'tools':{'listChanged':False}},'serverInfo':{'name':'T3 fixture','version':'1.0'}}
  elif method=='tools/list':result={'tools':[{'name':'t3_thread_list','description':'List threads','inputSchema':{'type':'object','properties':{}}}]}
  elif method=='tools/call' and req['params']['name']=='http_error':return self.reply(503,b'{}')
  elif method=='tools/call' and req['params']['name']=='rpc_error':return self.reply(200,json.dumps({'jsonrpc':'2.0','id':id,'error':{'code':-32602,'message':'Bad argument'}}).encode())
  elif method=='tools/call' and req['params']['name']=='tool_error':result={'content':[{'type':'text','text':'failed'}],'isError':True}
  elif method=='tools/call':result={'content':[{'type':'text','text':'{"threads":[]}'}],'structuredContent':{'threads':[]},'isError':False}
  else:return self.reply(200,json.dumps({'jsonrpc':'2.0','id':id,'error':{'code':-32601,'message':'Method not found'}}).encode())
  data=json.dumps({'jsonrpc':'2.0','id':id,'result':result}).encode()
  headers={'Mcp-Session-Id':'fixture-session'} if method=='initialize' else {}
  if '/sse' in self.path:self.reply(200,b'event: message\ndata: '+data+b'\n\n','text/event-stream',headers)
  else:self.reply(200,data,headers=headers)
http.server.ThreadingHTTPServer(('127.0.0.1',47831),Handler).serve_forever()
