import std.stdio;
import std.socket;
import std.string;
import std.conv;
import std.array;
import std.functional;
import std.typecons;

alias RouteHandler = string delegate();

class PrismApplication
{
	private TcpSocket server;
	private string[string] routes;

	this(ushort port = 8080)
	{
		server = new TcpSocket();
		server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		server.bind(new InternetAddress(port));
		server.listen(10);
	}

	void get(string path, RouteHandler handler)
	{
		routes[path] = handler();
	}

	void run()
	{
		writeln("Server running at http://localhost:8080");
		scope (exit)
			server.close();
		import std.algorithm;

		while (true)
		{
			auto client = server.accept();
			scope (exit)
				client.close();

			ubyte[4096] buffer;
			size_t totalRead = 0;

			while (true)
			{
				auto bytesRead = client.receive(buffer[totalRead .. $]);
				if (bytesRead <= 0)
					break;
				totalRead += bytesRead;
				if (totalRead >= buffer.length || cast(string)(buffer[0 .. totalRead]))

					break;
			}

			if (totalRead == 0)
				continue;

			auto request = cast(string) buffer[0 .. totalRead];
			auto path = extractPath(request);
			auto responseBody = handleRoute(path);
			auto responseHeader = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: " ~
				to!string(
					responseBody.length) ~ "\r\nConnection: close\r\n\r\n";

			client.send(cast(ubyte[])(responseHeader ~ responseBody));
		}
	}

	private string extractPath(string request)
	{
		auto i = request.indexOf("\r\n");
		if (i == -1)
			return "/";
		auto requestLine = request[0 .. i].split();
		return requestLine.length >= 2 ? requestLine[1] : "/";
	}

	private string handleRoute(string path)
	{
		if (auto handler = path in routes)
			return *handler;
		return "<html><body><h1>404 Not Found</h1></body></html>";
	}
}

void main()
{
	auto app = new PrismApplication();

	app.get("/", () => "<html><body><h1>Welcome to D Prism Framework</h1></body></html>");
	app.get("/about", () => "<html><body><h1>About Page</h1></body></html>");
	app.get("/hello", () => "<html><body><h1>Hello World!</h1></body></html>");

	app.run();
}
