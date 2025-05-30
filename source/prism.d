module prism;

import std;

/** 
 * Some handler that returns a string response.
 */
alias RouteHandler = string delegate();

/** 
 * The application itself.
 */
class PrismApplication
{
	private TcpSocket server;
	private string[string] routes;

	/** 
	 * Instantiate a new application.
	 *
	 * Params:
	 *   port = Port to operate on
	 */
	this(ushort port = 8080)
	{
		server = new TcpSocket();
		server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		server.bind(new InternetAddress(port));
		server.listen(1000);
	}

	/** 
	 * Set a GET method route.
	 *
	 * Params:
	 *   path = The path to set
	 *   handler = The handler/delegate for the route
	 */
	void get(string path, RouteHandler handler)
	{
		routes[path] = handler();
	}

	/** 
	 * Run the application.
	 */
	void run()
	{
		writeln("Go to http://localhost:8080");

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

	/** 
	 * Extract the path given some URI request in string form.
	 *
	 * Params:
	 *   request = The request itself
	 *
	 * Returns: The extracted path
	 */
	private string extractPath(string request)
	{
		auto i = request.indexOf("\r\n");
		if (i == -1)
			return "/";
		auto requestLine = request[0 .. i].split();
		return requestLine.length >= 2 ? requestLine[1] : "/";
	}

	/** 
	 * Handle the route.
	 *
	 * Params:
	 *   path = The path of the route
	 * Returns: The corresponding response
	 */
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
