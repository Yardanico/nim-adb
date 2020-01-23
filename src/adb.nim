# ADB protocol implementation in Nim
# References:
# https://android.googlesource.com/platform/system/core/+/master/adb/protocol.txt
# https://github.com/sidorares/node-adbhost/
# https://github.com/cstyan/adbDocumentation
# https://chromium.googlesource.com/infra/luci/python-adb/+/refs/heads/master/adb/adb_protocol.py
import strutils, tables, deques
import asyncnet, asyncdispatch

export deques, tables

type
  AdbCommand* = enum
    cmdSync, cmdConnect, cmdAuth, cmdOpen, cmdOkay, cmdClose, cmdWrite

  AdbMessage* = object ## Message object as described per ADB protocol
    command*: uint32
    arg0, arg1*: uint32
    dataLen*: uint32
    dataCrc32*: uint32
    magic*: uint32
    data*: string
  
  AdbStream* = ref object
    adb*: AdbClient
    localId: int
    remoteId: int
    path*: string
    data*: Deque[string]

  AdbClient* = ref object
    ip: string
    s: AsyncSocket
    nextStreamId: int
    streams: TableRef[int, AdbStream]
    onConnect*: proc (adb: AdbClient): Future[void]
    onData*: proc (adb: AdbStream): Future[void]


const
  AdbCommandToValue: array[AdbCommand, uint32] = [
    0x434e5953'u32,
    0x4e584e43,
    0x48545541,
    0x4e45504f,
    0x59414b4f,
    0x45534c43,
    0x45545257
  ]
  AdbVersion = 0x01000000
  MaxPayload = 4096

proc toEnum(cmd: uint32): AdbCommand = 
  AdbCommand(AdbCommandToValue.find(cmd))

proc toUint(cmd: AdbCommand): uint32 = 
  AdbCommandToValue[cmd]

proc `$`*(msg: AdbMessage): string = 
  result = "AdbMessage(cmd=" & $toEnum(msg.command) & ", arg0=" & $msg.arg0 & ", arg1=" & $msg.arg1
  if msg.dataLen == 0:
    result.add ")"
  else:
    result.add ", data=\"" & repr(msg.data) & "\")"

proc verifyCrc(msg: AdbMessage): bool = 
  var crc = 0
  for c in msg.data:
    crc += ord(c)
  msg.dataCrc32 == uint32(crc)

proc send*(adb: AdbClient, msg: AdbMessage) {.async.} = 
  var msg = msg # Copy message in memory
  when defined(adbDebug):
    echo "SEND: ", msg
  await adb.s.send(addr msg, 24)
  if msg.data.len != 0:
    await adb.s.send(msg.data)

proc recvMsg*(adb: AdbClient): Future[AdbMessage] {.async.} = 
  if (await adb.s.recvInto(addr result, 24)) != 24:
    raise newException(ValueError, "Expected 24 bytes!")
  # Check if the response is malformed
  if result.magic != (result.command xor 0xffffffff'u32):
    let cmd = toEnum(result.command)
    raise newException(ValueError, "Invalid magic for command " & $cmd)
  
  if result.dataLen > 0:
    result.data = await adb.s.recv(int(result.dataLen))
    if not result.verifyCrc():
      raise newException(ValueError, "Invalid CRC for answer data!")
  when defined(adbDebug):
    echo "RECV: ", result


proc newMessage(cmd: AdbCommand, arg0, arg1: int, data: string): AdbMessage = 
  ## Creates a new Message object
  result.command = toUint(cmd)
  result.arg0 = uint32(arg0)
  result.arg1 = uint32(arg1)
  result.magic = result.command xor 0xffffffff'u32
  # Lenght of our data payload
  result.dataLen = uint32(len(data))
  # Calculate checksum for our data payload
  for c in data:
    result.dataCrc32 += uint32(ord(c))
  result.data = data


proc newAdbClient*(host: string): AdbClient = 
  ## Create new ADB client with host server's IP `host`
  result = new(AdbClient)
  result.ip = host
  result.nextStreamId = 12345
  result.streams = newTable[int, AdbStream]()

proc getLocalId(adb: AdbClient): int = 
  result = adb.nextStreamId
  inc adb.nextStreamId

proc connect*(adb: AdbClient, port = Port(5555)) {.async.} = 
  ## Connect to ADB server with port `port`
  adb.s = newAsyncSocket()
  await adb.s.connect(adb.ip, port)
  await adb.send newMessage(cmdConnect, AdbVersion, MaxPayload, "host::\x00")

proc write(adb: AdbClient, localId: int, remoteId: int, data: string) {.async.} = 
  await adb.send newMessage(cmdWrite, localId, remoteId, data & "\x00")

proc okay(adb: AdbClient, localId: int, remoteId: int) {.async.} = 
  await adb.send newMessage(cmdOkay, localId, remoteId, "")

proc close(adb: AdbClient, localId: int, remoteId: int) {.async.} = 
  await adb.send newMessage(cmdClose, localId, remoteId, "")


proc openStream*(adb: AdbClient, dest: string): Future[AdbStream] {.async.} = 
  result = AdbStream(
    adb: adb, 
    localId: adb.getLocalId(), 
    remoteId: -1, 
    path: dest,
    data: initDeque[string]()
  )
  await adb.send newMessage(cmdOpen, result.localId, 0, dest & "\x00")
  adb.streams[result.localId] = result

proc write*(s: AdbStream, content: string) {.async.} = 
  await s.adb.write(s.localId, s.remoteId, content)

proc run*(adb: AdbClient) {.async.} = 
  await adb.connect()
  var curMsg: AdbMessage

  while true:
    curMsg = await adb.recvMsg()
    let cmd = toEnum(curMsg.command)
    case cmd
    of cmdWrite:
      let localId = int(curMsg.arg1)
      var usrStream = adb.streams[localId]
      usrStream.data.addLast(curMsg.data)
      await adb.okay(usrStream.localId, usrStream.remoteId)
      asyncCheck adb.onData(usrStream)
    of cmdOkay:
      let localId = int(curMsg.arg1)
      var usrStream = adb.streams[localId]
      if usrStream.remoteId == -1:
        usrStream.remoteId = int(curMsg.arg0)
        # have a callback for stream being ready?
    of cmdConnect:
      let hostVer = int(curMsg.arg0)
      let hostMaxData = int(curMsg.arg1)
      let banner = curMsg.data.split("::")
      # provide this info as well?
      asyncCheck adb.onConnect(adb)

    of cmdClose:
      let localId = int(curMsg.arg1)
      var usrStream = adb.streams[localId]
      # have a callback for closing the stream?
      adb.streams.del(localId)

    else: 
      discard