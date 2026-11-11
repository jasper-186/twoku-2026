' Clean RFC 6455 WebSocket client for BrightScript.
'
' Supports ws:// only. wss:// will fail with an on_error event explaining why
' (Roku's roStreamSocket has no TLS, and the hand-rolled TLS that was in
' components/web_socket_client/ could not complete a handshake - see
' .known_issues/stashed-websocket-client.md).
'
' Drive m.run() from a task loop. Events are posted to the message port set
' via set_message_port(). Each event is an roAssociativeArray:
'   { id: "on_open",    data: { protocol: <String> } }
'   { id: "on_message", data: { type: 0|1, message: <String|roArray> } }   ' type 0 = text, 1 = binary
'   { id: "on_close",   data: "" }
'   { id: "on_error",   data: { code: <Integer>, message: <String> } }
'   { id: "ready_state",data: <Integer> }                                   ' STATE.* values
'
' Usage:
'   ws = NewWebSocket()
'   port = createObject("roMessagePort")
'   ws.set_message_port(port)
'   ws.open("ws://host:port/path")
'   ' poll ws.run() and wait(0, port) from a task loop
'   ws.send("hello")
'   ws.close()

function NewWebSocket() as Object
    ws = {}

    ws.STATE = { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 }
    ws.OPCODE = { CONTINUATION: 0, TEXT: 1, BINARY: 2, CLOSE: 8, PING: 9, PONG: 10 }

    ws._state = ws.STATE.CLOSED
    ws._socket = invalid
    ws._sock_port = createObject("roMessagePort")
    ws._event_port = invalid
    ws._handshake = invalid
    ws._sent_handshake = false
    ws._got_response = false
    ws._sec_key = invalid
    ws._buffer = createObject("roByteArray")
    ws._max_buffer = 1024 * 1024
    ws._frame_data = createObject("roByteArray")
    ws._frame_opcode = invalid
    ws._closing_started = 0
    ws._closing_timeout = 5
    ws._protocols = []
    ws._headers = []

    ws._NL = chr(13) + chr(10)
    ws._URL_REGEX = createObject("roRegex", "(\w+):\/\/([^/:]+)(?::(\d+))?(.*)?", "")
    ws._STATUS_REGEX = createObject("roRegex", "HTTP\/\d+(?:.\d)?\s(\d{3})\s.*", "")
    ws._HEADER_REGEX = createObject("roRegex", "(\S+):\s?(.*)", "")
    ws._WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    ' ---------- public API ----------

    ws.set_message_port = function (port as Object) as Void
        m._event_port = port
    end function

    ws.set_protocols = function (protocols as Object) as Void
        m._protocols = protocols
    end function

    ' headers must be a flat roArray of [key1, val1, key2, val2, ...]
    ws.set_headers = function (headers as Object) as Void
        m._headers = headers
    end function

    ws.set_max_buffer = function (size as Integer) as Void
        m._max_buffer = size
    end function

    ws.get_ready_state = function () as Integer
        return m._state
    end function

    ws.open = function (url as String) as Void
        if m._state <> m.STATE.CLOSED
            m._emit_error(13, "open() called while not in CLOSED state")
            return
        end if
        if not m._URL_REGEX.isMatch(url)
            m._emit_error(1, "Invalid URL: " + url)
            return
        end if
        match = m._URL_REGEX.match(url)
        scheme = lcase(match[1])
        host = lcase(match[2])
        port_str = match[3]
        path = match[4]
        if path = ""
            path = "/"
        end if
        if scheme = "wss"
            m._emit_error(2, "wss:// is not supported on Roku. Use ws:// or a server-side relay.")
            return
        end if
        if scheme <> "ws"
            m._emit_error(3, "Unsupported scheme: " + scheme)
            return
        end if
        port = 80
        if port_str <> ""
            port = val(port_str, 10)
        end if

        addr = createObject("roSocketAddress")
        addr.setHostName(host)
        addr.setPort(port)
        if not addr.isAddressValid()
            m._emit_error(4, "Invalid hostname: " + host)
            return
        end if

        m._socket = createObject("roStreamSocket")
        m._socket.setMessagePort(m._sock_port)
        m._socket.notifyReadable(true)
        m._socket.notifyWritable(true)
        m._socket.notifyException(true)
        m._socket.setSendToAddress(addr)

        m._sec_key = m._make_sec_key()
        m._handshake = m._build_handshake(host, port, path)
        m._sent_handshake = false
        m._got_response = false
        m._buffer = createObject("roByteArray")
        m._frame_data = createObject("roByteArray")
        m._frame_opcode = invalid

        m._set_state(m.STATE.CONNECTING)
        if not m._socket.connect()
            m._emit_error(5, "Socket connect failed: " + m._socket.status().toStr())
            m._fail()
            return
        end if
    end function

    ws.send = function (message as Object, force_opcode = -1 as Integer) as Integer
        if m._state <> m.STATE.OPEN or m._socket = invalid or not m._socket.isWritable()
            return -1
        end if

        bytes = createObject("roByteArray")
        opcode = 0
        msg_type = type(message)
        if msg_type = "roString" or msg_type = "String"
            bytes.fromAsciiString(message)
            opcode = m.OPCODE.TEXT
        else if msg_type = "roByteArray"
            bytes.append(message)
            opcode = m.OPCODE.BINARY
        else if msg_type = "roArray"
            for each byte in message
                bytes.push(byte)
            end for
            opcode = m.OPCODE.BINARY
        else
            return -1
        end if

        if force_opcode >= 0
            if (force_opcode >> 3) <> 1
                return -1
            end if
            if bytes.count() > 125
                return -1
            end if
            opcode = force_opcode
        end if

        return m._send_frame(opcode, bytes)
    end function

    ws.close = function (code = 1000 as Integer, reason = "" as String) as Void
        if m._state <> m.STATE.OPEN
            return
        end if
        body = createObject("roByteArray")
        body.push((code >> 8) and &hff)
        body.push(code and &hff)
        if reason <> ""
            reason_bytes = createObject("roByteArray")
            reason_bytes.fromAsciiString(reason)
            body.append(reason_bytes)
        end if
        m._send_frame(m.OPCODE.CLOSE, body)
        m._closing_started = uptime(0)
        m._set_state(m.STATE.CLOSING)
    end function

    ws.run = function () as Void
        msg = wait(50, m._sock_port)
        if type(msg) = "roSocketEvent" and m._socket <> invalid
            if not m._sent_handshake and m._socket.isWritable() and m._handshake <> invalid
                sent = m._socket.sendStr(m._handshake)
                if sent <= 0
                    m._emit_error(6, "Failed to send WebSocket handshake: status " + m._socket.status().toStr())
                    m._fail()
                    return
                end if
                m._sent_handshake = true
            end if
            m._read_socket()
        end if
        if m._state = m.STATE.CLOSING and uptime(0) - m._closing_started >= m._closing_timeout
            m._fail()
        end if
    end function

    ' ---------- internal ----------

    ws._read_socket = function () as Void
        if m._socket = invalid or m._state = m.STATE.CLOSED
            return
        end if
        if not m._socket.isReadable() or m._socket.getCountRcvBuf() = 0
            return
        end if
        chunk = createObject("roByteArray")
        chunk[1024] = 0
        n = m._socket.receive(chunk, 0, 1024)
        if n <= 0
            return
        end if

        if m._buffer.count() + n > m._max_buffer
            m._emit_error(7, "Inbound buffer would exceed " + m._max_buffer.toStr() + " bytes")
            m._fail()
            return
        end if
        for i = 0 to n - 1
            m._buffer.push(chunk[i])
        end for

        if not m._got_response
            m._try_parse_handshake_response()
        end if
        if m._got_response and m._state = m.STATE.OPEN
            m._parse_frames()
        end if
    end function

    ws._try_parse_handshake_response = function () as Void
        as_string = m._buffer.toAsciiString()
        marker_idx = Instr(1, as_string, m._NL + m._NL)
        if marker_idx = 0
            return
        end if

        headers_text = Left(as_string, marker_idx - 1)
        consumed = marker_idx + 3
        m._buffer = m._slice_buffer(consumed)

        lines = headers_text.split(m._NL)
        if lines.count() = 0
            m._emit_error(8, "Empty handshake response")
            m._fail()
            return
        end if

        status_match = m._STATUS_REGEX.match(lines[0])
        if status_match.count() < 2
            m._emit_error(9, "Malformed status line: " + lines[0])
            m._fail()
            return
        end if
        if status_match[1] <> "101"
            m._emit_error(10, "Expected HTTP 101, got " + status_match[1])
            m._fail()
            return
        end if

        upgrade_ok = false
        connection_ok = false
        accept_ok = false
        chosen_protocol = ""
        for i = 1 to lines.count() - 1
            if m._HEADER_REGEX.isMatch(lines[i])
                h = m._HEADER_REGEX.match(lines[i])
                name = lcase(h[1])
                value = h[2].trim()
                if name = "upgrade" and lcase(value) = "websocket"
                    upgrade_ok = true
                else if name = "connection" and Instr(1, lcase(value), "upgrade") > 0
                    connection_ok = true
                else if name = "sec-websocket-accept"
                    expected = m._compute_accept(m._sec_key)
                    if expected = value
                        accept_ok = true
                    else
                        m._emit_error(11, "Sec-WebSocket-Accept mismatch: expected " + expected + ", got " + value)
                        m._fail()
                        return
                    end if
                else if name = "sec-websocket-protocol"
                    chosen_protocol = value
                end if
            end if
        end for

        if not (upgrade_ok and connection_ok and accept_ok)
            m._emit_error(12, "Handshake response missing required header")
            m._fail()
            return
        end if

        m._got_response = true
        m._set_state(m.STATE.OPEN)
        m._emit("on_open", { protocol: chosen_protocol })
    end function

    ws._parse_frames = function () as Void
        while m._buffer.count() >= 2
            byte0 = m._buffer[0]
            byte1 = m._buffer[1]
            final = (byte0 >> 7) = 1
            opcode = byte0 and &h0f
            is_control = (opcode >> 3) = 1
            masked = (byte1 >> 7) = 1
            payload_size = byte1 and &h7f

            header_size = 2
            if payload_size = 126
                if m._buffer.count() < 4
                    return
                end if
                payload_size = (m._buffer[2] << 8) or m._buffer[3]
                header_size = 4
            else if payload_size = 127
                if m._buffer.count() < 10
                    return
                end if
                payload_size = 0
                for b = 0 to 7
                    payload_size = (payload_size << 8) or m._buffer[2 + b]
                end for
                header_size = 10
            end if

            mask_bytes = invalid
            if masked
                if m._buffer.count() < header_size + 4
                    return
                end if
                mask_bytes = [m._buffer[header_size], m._buffer[header_size + 1], m._buffer[header_size + 2], m._buffer[header_size + 3]]
                header_size += 4
            end if

            if m._buffer.count() < header_size + payload_size
                return
            end if

            payload = createObject("roByteArray")
            for i = 0 to payload_size - 1
                b = m._buffer[header_size + i]
                if mask_bytes <> invalid
                    b = m._xor(b, mask_bytes[i mod 4])
                end if
                payload.push(b)
            end for

            m._buffer = m._slice_buffer(header_size + payload_size)

            m._handle_frame(final, is_control, opcode, payload)
            if m._state = m.STATE.CLOSED
                return
            end if
        end while
    end function

    ws._handle_frame = function (final as Boolean, is_control as Boolean, opcode as Integer, payload as Object) as Void
        if is_control
            if opcode = m.OPCODE.CLOSE
                m._handle_close_frame(payload)
            else if opcode = m.OPCODE.PING
                m._send_frame(m.OPCODE.PONG, payload)
            end if
            return
        end if

        if not final
            if m._frame_data.count() = 0
                m._frame_opcode = opcode
            end if
            m._frame_data.append(payload)
            return
        end if

        effective_opcode = opcode
        if opcode = m.OPCODE.CONTINUATION and m._frame_opcode <> invalid
            effective_opcode = m._frame_opcode
        end if
        if m._frame_data.count() > 0
            full = createObject("roByteArray")
            full.append(m._frame_data)
            full.append(payload)
            payload = full
            m._frame_data = createObject("roByteArray")
            m._frame_opcode = invalid
        end if

        if effective_opcode = m.OPCODE.TEXT
            m._emit("on_message", { type: 0, message: payload.toAsciiString() })
        else if effective_opcode = m.OPCODE.BINARY
            arr = []
            for each byte in payload
                arr.push(byte)
            end for
            m._emit("on_message", { type: 1, message: arr })
        end if
    end function

    ws._handle_close_frame = function (payload as Object) as Void
        if m._state = m.STATE.OPEN
            m._send_frame(m.OPCODE.CLOSE, payload)
        end if
        m._fail()
    end function

    ws._send_frame = function (opcode as Integer, payload as Object) as Integer
        if m._socket = invalid or not m._socket.isWritable()
            return -1
        end if

        frame = createObject("roByteArray")
        frame.push(&h80 or opcode)

        plen = payload.count()
        if plen <= 125
            frame.push(&h80 or plen)
        else if plen <= &hffff
            frame.push(&h80 or 126)
            frame.push((plen >> 8) and &hff)
            frame.push(plen and &hff)
        else
            frame.push(&h80 or 127)
            for shift = 56 to 0 step -8
                frame.push((plen >> shift) and &hff)
            end for
        end if

        mask_int = (rnd(&hffff) << 16) or rnd(&hffff)
        mask_bytes = [(mask_int >> 24) and &hff, (mask_int >> 16) and &hff, (mask_int >> 8) and &hff, mask_int and &hff]
        for i = 0 to 3
            frame.push(mask_bytes[i])
        end for

        for i = 0 to plen - 1
            frame.push(m._xor(payload[i], mask_bytes[i mod 4]))
        end for

        sent = m._socket.send(frame, 0, frame.count())
        if sent < frame.count()
            return -1
        end if
        return sent
    end function

    ws._build_handshake = function (host as String, port as Integer, path as String) as String
        out = "GET " + path + " HTTP/1.1" + m._NL
        out += "Host: " + host + ":" + port.toStr() + m._NL
        out += "Upgrade: websocket" + m._NL
        out += "Connection: Upgrade" + m._NL
        out += "Sec-WebSocket-Key: " + m._sec_key + m._NL
        out += "Sec-WebSocket-Version: 13" + m._NL
        if m._protocols.count() > 0
            joined = ""
            for i = 0 to m._protocols.count() - 1
                if i > 0
                    joined += ", "
                end if
                joined += m._protocols[i]
            end for
            out += "Sec-WebSocket-Protocol: " + joined + m._NL
        end if
        i = 0
        while i + 1 < m._headers.count()
            out += m._headers[i] + ": " + m._headers[i + 1] + m._NL
            i += 2
        end while
        out += m._NL
        return out
    end function

    ws._make_sec_key = function () as String
        bytes = createObject("roByteArray")
        for i = 1 to 16
            bytes.push(rnd(256) - 1)
        end for
        return bytes.toBase64String()
    end function

    ws._compute_accept = function (sec_key as String) as String
        accept_bytes = createObject("roByteArray")
        accept_bytes.fromAsciiString(sec_key + m._WS_GUID)
        digest = createObject("roEVPDigest")
        digest.setup("sha1")
        digest_hex = digest.process(accept_bytes)
        digest_bytes = createObject("roByteArray")
        digest_bytes.fromHexString(digest_hex)
        return digest_bytes.toBase64String()
    end function

    ws._slice_buffer = function (start as Integer) as Object
        result = createObject("roByteArray")
        total = m._buffer.count()
        if start >= total
            return result
        end if
        for i = start to total - 1
            result.push(m._buffer[i])
        end for
        return result
    end function

    ws._xor = function (a as Integer, b as Integer) as Integer
        return (a or b) and not (a and b)
    end function

    ws._set_state = function (s as Integer) as Void
        m._state = s
        m._emit("ready_state", s)
    end function

    ws._emit = function (id as String, data as Object) as Void
        if m._event_port <> invalid
            m._event_port.postMessage({ id: id, data: data })
        end if
    end function

    ws._emit_error = function (code as Integer, message as String) as Void
        m._emit("on_error", { code: code, message: message })
    end function

    ws._fail = function () as Void
        if m._socket <> invalid
            m._socket.close()
            m._socket = invalid
        end if
        if m._state <> m.STATE.CLOSED
            m._set_state(m.STATE.CLOSED)
            m._emit("on_close", "")
        end if
    end function

    return ws
end function
