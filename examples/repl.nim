# A simple example to connect to remote ADB shell and issue commands
# Uses threadpool to read stdin while running async code
import asyncdispatch, threadpool
import adb

var client = newAdbClient("1.2.3.4")
var stream: AdbStream

proc onConnect(adb: AdbClient) {.async.} = 
  echo "Connected, opening \"shell:\" stream..."
  stream = await adb.openStream("shell:")
  echo "REPL ready!"

proc onData(stream: AdbStream) {.async.} = 
  var data = ""
  #echo stream.data
  while len(stream.data) > 0:
    data.add stream.data.popFirst()
  stdout.write(data)
  stdout.flushFile()

client.onConnect = onConnect
client.onData = onData

var messageFlowVar = spawn stdin.readLine()

proc repl {.async.} = 
  while true:
    if messageFlowVar.isReady():
      # Write a shell command with \r (like pressing Enter)
      await stream.write(^messageFlowVar & "\r")
      messageFlowVar = spawn stdin.readLine()
    asyncdispatch.poll()

echo "Connecting..."

asyncCheck client.run()
waitFor repl()