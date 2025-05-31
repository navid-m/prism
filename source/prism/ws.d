module prism.ws;

import std;
import std.socket;
import std.exception;
import std.conv;
import std.array;

/**
 * WebSocket frame opcodes (RFC 6455, Section 5.2)
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
 * WebSocket frame structure (RFC 6455, Section 5)
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
 * WebSocket connection wrapper (RFC 6455)
 */
class WebSocketConnection
{
    private Socket socket;
    private bool isOpen = true;

    this(Socket socket)
    {
        this.socket = socket;
        this.socket.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, true);
    }

    /// Send a text message to the client (RFC 6455 5.6)
    void sendText(string message)
    {
        sendFrame(WebSocketOpcode.TEXT, cast(ubyte[]) message);
    }

    /// Send binary data to the client
    void sendBinary(ubyte[] data)
    {
        sendFrame(WebSocketOpcode.BINARY, data);
    }

    /// Send ping control frame (RFC 6455 5.5.2)
    void ping(ubyte[] data = [])
    {
        enforce(data.length <= 125, "Ping frame payload too large");
        sendFrame(WebSocketOpcode.PING, data);
    }

    /// Send pong control frame (RFC 6455 5.5.3)
    void pong(ubyte[] data = [])
    {
        enforce(data.length <= 125, "Pong frame payload too large");
        sendFrame(WebSocketOpcode.PONG, data);
    }

    /// Close the WebSocket connection (RFC 6455 5.5.1)
    void close(ushort code = 1000, string reason = "")
    {
        if (!isOpen)
            return;

        ubyte[] closeData;
        closeData ~= cast(ubyte)(code >> 8);
        closeData ~= cast(ubyte)(code & 0xFF);
        if (!reason.empty)
            closeData ~= cast(ubyte[]) reason;

        sendFrame(WebSocketOpcode.CLOSE, closeData);
        isOpen = false;
        socket.close();
    }

    /// Check if the WebSocket connection is still open
    bool isConnectionOpen() => isOpen;

    /// Send a WebSocket frame (RFC 6455 5.2)
    private void sendFrame(WebSocketOpcode opcode, ubyte[] payload)
    {
        if (!isOpen)
            return;

        ubyte[] frame;
        frame ~= 0x80 | cast(ubyte) opcode;
        size_t len = payload.length;

        if (len < 126)
        {
            frame ~= cast(ubyte) len;
        }
        else if (len <= 0xFFFF)
        {
            frame ~= 126;
            frame ~= cast(ubyte)((len >> 8) & 0xFF);
            frame ~= cast(ubyte)(len & 0xFF);
        }
        else
        {
            frame ~= 127;
            foreach_reverse (i; 0 .. 8)
                frame ~= cast(ubyte)((len >> (i * 8)) & 0xFF);
        }

        frame ~= payload;

        try
        {
            socket.send(frame);
        }
        catch (Exception)
        {
            isOpen = false;
        }
    }

    /// Receive and parse a WebSocket frame (RFC 6455 5.2)
    WebSocketFrame receiveFrame()
    {
        WebSocketFrame frame;
        ubyte[2] header;

        if (socket.receive(header) != 2)
            throw new Exception("Failed to read frame header");

        frame.fin = (header[0] & 0x80) != 0;
        frame.opcode = cast(WebSocketOpcode)(header[0] & 0x0F);
        frame.masked = (header[1] & 0x80) != 0;

        ulong payloadLen = header[1] & 0x7F;
        if (payloadLen == 126)
        {
            ubyte[2] extLen;
            enforce(socket.receive(extLen) == 2, "Failed to read extended payload length (16-bit)");
            frame.payloadLength = (extLen[0] << 8) | extLen[1];
        }
        else if (payloadLen == 127)
        {
            ubyte[8] extLen;
            enforce(socket.receive(extLen) == 8, "Failed to read extended payload length (64-bit)");
            frame.payloadLength = 0;
            foreach (b; extLen)
                frame.payloadLength = (frame.payloadLength << 8) | b;
        }
        else
        {
            frame.payloadLength = payloadLen;
        }

        if (frame.masked)
        {
            enforce(socket.receive(frame.maskingKey) == 4, "Failed to read masking key");
        }

        if (frame.payloadLength > 0)
        {
            frame.payload.length = frame.payloadLength;
            size_t received = 0;

            while (received < frame.payloadLength)
            {
                auto chunk = socket.receive(frame.payload[received .. $]);
                if (chunk <= 0)
                    throw new Exception("Incomplete payload data received");
                received += chunk;
            }

            if (frame.masked)
            {
                foreach (i; 0 .. frame.payload.length)
                {
                    frame.payload[i] ^= frame.maskingKey[i % 4];
                }
            }
        }

        return frame;
    }
}
