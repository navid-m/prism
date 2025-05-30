module prism;

import std;

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

		while (true)
		{
			auto client = server.accept();

			client.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, true);
			client.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(5));

			void handleClient(Socket client)
			{
				scope (exit)
					client.close();

				while (true)
				{
					ubyte[4096] buffer;
					size_t totalRead = 0;

					while (true)
					{
						auto bytesRead = client.receive(buffer[totalRead .. $]);
						if (bytesRead <= 0)
							return;
						totalRead += bytesRead;
						auto chunk = cast(string) buffer[0 .. totalRead];
						if (chunk.canFind("\r\n\r\n"))
							break;
					}

					auto request = cast(string) buffer[0 .. totalRead];
					auto responseBody = handleRoute(extractPath(request));
					bool keepAlive = request.toLower().canFind("connection: keep-alive");
					string responseHeader = "HTTP/1.1 200 OK\r\n"
						~ "Content-Type: text/html\r\n"
						~ "Content-Length: " ~ to!string(responseBody.length) ~ "\r\n"
						~ (keepAlive ? "Connection: keep-alive\r\n\r\n"
								: "Connection: close\r\n\r\n");
					client.send(
						cast(ubyte[])(responseHeader ~ responseBody));
					if (!keepAlive)
						break;
				}
			}

			handleClient(client);
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
