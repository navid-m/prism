module prism.ws;

import std;

/**
 * WebSocket frame opcodes
 */
enum WebSocketOpcode : ubyte
{
    CONTINUATION = 0x0,
    TEXT = 0x1,
    BINARY = 0x2,
    CLOSE = 0x8,
    PING = 0x9,
    PONG = 0xA
}

/**
 * WebSocket frame structure
 */
struct WebSocketFrame
{
    bool fin;
    WebSocketOpcode opcode;
    bool masked;
    ulong payloadLength;
    ubyte[4] maskingKey;
    ubyte[] payload;
}

/**
 * WebSocket connection wrapper
 */
class WebSocketConnection
{
    private Socket socket;
    private bool isOpen = true;

    this(Socket socket)
    {
        this.socket = socket;
    }

    /**
	 * Send text message to WebSocket client
	 */
    void sendText(string message)
    {
        sendFrame(WebSocketOpcode.TEXT, cast(ubyte[]) message);
    }

    /**
	 * Send binary message to WebSocket client
	 */
    void sendBinary(ubyte[] data)
    {
        sendFrame(WebSocketOpcode.BINARY, data);
    }

    /**
	 * Send ping frame
	 */
    void ping(ubyte[] data = [])
    {
        sendFrame(WebSocketOpcode.PING, data);
    }

    /**
	 * Send pong frame
	 */
    void pong(ubyte[] data = [])
    {
        sendFrame(WebSocketOpcode.PONG, data);
    }

    /**
	 * Close WebSocket connection
	 */
    void close(ushort code = 1000, string reason = "")
    {
        if (!isOpen)
            return;

        ubyte[] closeData;
        closeData ~= cast(ubyte)(code >> 8);
        closeData ~= cast(ubyte)(code & 0xFF);
        closeData ~= cast(ubyte[]) reason;

        sendFrame(WebSocketOpcode.CLOSE, closeData);
        isOpen = false;
        socket.close();
    }

    /**
	 * Check if connection is open
	 */
    bool isConnectionOpen()
    {
        return isOpen;
    }

    /**
	 * Send WebSocket frame
	 */
    private void sendFrame(WebSocketOpcode opcode, ubyte[] payload)
    {
        if (!isOpen)
            return;

        ubyte[] frame;
        frame ~= 0x80 | cast(ubyte) opcode;

        if (payload.length < 126)
        {
            frame ~= cast(ubyte) payload.length;
        }
        else if (payload.length <= 65_535)
        {
            frame ~= 126;
            frame ~= cast(ubyte)(payload.length >> 8);
            frame ~= cast(ubyte)(payload.length & 0xFF);
        }
        else
        {
            frame ~= 127;
            for (int i = 7; i >= 0; i--)
            {
                frame ~= cast(ubyte)((payload.length >> (i * 8)) & 0xFF);
            }
        }

        frame ~= payload;

        try
        {
            socket.send(frame);
        }
        catch (Exception e)
        {
            isOpen = false;
        }
    }

    /**
	 * Receive and parse WebSocket frame
	 */
    WebSocketFrame receiveFrame()
    {
        WebSocketFrame frame;
        ubyte[2] header;

        auto received = socket.receive(header);
        if (received <= 0)
        {
            throw new Exception("Connection closed");
        }

        frame.fin = (header[0] & 0x80) != 0;
        frame.opcode = cast(WebSocketOpcode)(header[0] & 0x0F);
        frame.masked = (header[1] & 0x80) != 0;

        ulong payloadLen = header[1] & 0x7F;
        if (payloadLen == 126)
        {
            ubyte[2] extLen;
            socket.receive(extLen);
            frame.payloadLength = (extLen[0] << 8) | extLen[1];
        }
        else if (payloadLen == 127)
        {
            ubyte[8] extLen;
            socket.receive(extLen);
            frame.payloadLength = 0;
            for (int i = 0; i < 8; i++)
            {
                frame.payloadLength = (frame.payloadLength << 8) | extLen[i];
            }
        }
        else
            frame.payloadLength = payloadLen;
        if (frame.masked)
            socket.receive(frame.maskingKey);

        if (frame.payloadLength > 0)
        {
            frame.payload = new ubyte[frame.payloadLength];
            size_t totalReceived = 0;
            while (totalReceived < frame.payloadLength)
            {
                auto rcvd = socket.receive(frame.payload[totalReceived .. $]);
                if (rcvd <= 0)
                    break;
                totalReceived += rcvd;
            }
            if (frame.masked)
            {
                for (size_t i = 0; i < frame.payload.length; i++)
                {
                    frame.payload[i] ^= frame.maskingKey[i % 4];
                }
            }
        }
        return frame;
    }
}
