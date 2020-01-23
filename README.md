# nim-adb
ADB protocol implementation (client-side) in Nim.

Examples are available in the `examples` directory.

Compile with `-d:adbDebug` to see all ADB messages which are being sent/received

Example output of the REPL with `-d:adbDebug`:
```
Connecting...
SEND: AdbMessage(cmd=cmdConnect, arg0=16777216, arg1=4096, data="0x7f6259b931e8"host::\0"")
RECV: AdbMessage(cmd=cmdConnect, arg0=16777216, arg1=4096, data="0x7f6259baf058"device::ro.product.name=NV310WAC;ro.product.model=NV310WAC;ro.product.device=NV310WAC;\0"")
Connected, opening "shell:" stream...
SEND: AdbMessage(cmd=cmdOpen, arg0=12345, arg1=0, data="0x7f6259b93620"shell:\0"")
REPL ready!
RECV: AdbMessage(cmd=cmdOkay, arg0=691, arg1=12345)
RECV: AdbMessage(cmd=cmdWrite, arg0=691, arg1=12345, data="0x7f6259b972c0"shell@NV310WAC:/ $ "")
SEND: AdbMessage(cmd=cmdOkay, arg0=12345, arg1=691)
shell@NV310WAC:/ $ date
SEND: AdbMessage(cmd=cmdWrite, arg0=12345, arg1=691, data="0x7f6259b93d50"date\13\0"")
RECV: AdbMessage(cmd=cmdOkay, arg0=691, arg1=12345)
RECV: AdbMessage(cmd=cmdWrite, arg0=691, arg1=12345, data="0x7f6259bb90d0"date\13\13\10"
""")
SEND: AdbMessage(cmd=cmdOkay, arg0=12345, arg1=691)
date
RECV: AdbMessage(cmd=cmdWrite, arg0=691, arg1=12345, data="0x7f6259b96758"Thu Jan 23 17:40:40 +07 2020\13\10"
""")
SEND: AdbMessage(cmd=cmdOkay, arg0=12345, arg1=691)
Thu Jan 23 17:40:40 +07 2020
RECV: AdbMessage(cmd=cmdWrite, arg0=691, arg1=12345, data="0x7f6259b97598"shell@NV310WAC:/ $ \7"")
SEND: AdbMessage(cmd=cmdOkay, arg0=12345, arg1=691)
shell@NV310WAC:/ $ 
```