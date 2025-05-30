import std.stdio;
import std.socket;
import std.string;
import std.conv;

void main()
{
	writeln("Go to http://localhost:8080.");

	auto server = new TcpSocket();
	server.bind(new InternetAddress(8080));
	server.listen(10);

	scope (exit)
		server.close();

	while (true)
	{
		auto client = server.accept();
		scope (exit)
			client.close();

		ubyte[2056] buffer;
		auto bytesRead = client.receive(buffer);
		auto request = cast(string) buffer[0 .. bytesRead];
		writeln("Received request:\n", request);
		string bodya = "<html><body><h1>Hello from D!</h1></body></html>";
		string response = "HTTP/1.1 200 OK\r\n" ~
			"Content-Type: text/html\r\n" ~
			"Content-Length: " ~ to!string(
				bodya.length
			) ~ "\r\n" ~
			"Connection: close\r\n\r\n" ~ bodya;
		client.send(cast(ubyte[]) response);
	}
}
