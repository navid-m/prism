module prism.server;

import std;

/** 
 * Some handlers that return a string response per GET or POST.
 */
alias RouteHandler = string delegate();
alias PostRouteHandler = string delegate(string body);

/** 
 * The application itself.
 */
class PrismApplication
{
	private TcpSocket server;
	private string[string] getRoutes;
	private PostRouteHandler[string] postRoutes;

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
		getRoutes[path] = handler();
	}

	/** 
	 * Set a POST method route.
	 *
	 * Params:
	 *   path = The path to set
	 *   handler = The handler/delegate for the route
	 */
	void post(string path, PostRouteHandler handler)
	{
		postRoutes[path] = handler;
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
					auto method = extractMethod(request);
					auto path = extractPath(request);
					auto requestBody = extractBody(request);
					auto responseBody = handleRoute(method, path, requestBody);
					bool keepAlive = request.toLower().canFind("connection: keep-alive");

					string responseHeader = "HTTP/1.1 200 OK\r\n"
						~ "Content-Type: text/html\r\n"
						~ "Content-Length: " ~ to!string(responseBody.length) ~ "\r\n"
						~ (keepAlive ? "Connection: keep-alive\r\n\r\n"
								: "Connection: close\r\n\r\n"
						);

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
	 * Extract the HTTP method from the request.
	 *
	 * Params:
	 *   request = The request itself
	 *
	 * Returns: The HTTP method (GET, POST, etc.)
	 */
	private string extractMethod(string request)
	{
		auto i = request.indexOf(" ");
		if (i == -1)
			return "GET";
		return request[0 .. i];
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
	 * Extract the request body from a POST request.
	 *
	 * Params:
	 *   request = The request itself
	 *
	 * Returns: The request body
	 */
	private string extractBody(string request)
	{
		auto headerEnd = request.indexOf("\r\n\r\n");
		if (headerEnd == -1)
			return "";
		return request[headerEnd + 4 .. $];
	}

	/** 
	 * Handle the route based on method and path.
	 *
	 * Params:
	 *   method = The HTTP method
	 *   path = The path of the route
	 *   body = The request body (for POST requests)
	 * Returns: The corresponding response
	 */
	private string handleRoute(string method, string path, string body)
	{
		if (method == "GET")
		{
			if (auto handler = path in getRoutes)
				return *handler;
		}
		else if (method == "POST")
		{
			if (auto handler = path in postRoutes)
				return (*handler)(body);
		}

		return "<html><body><h1>404 Not Found</h1></body></html>";
	}
}

unittest
{
	auto app = new PrismApplication();

	app.get("/", () => "<html><body><h1>Welcome to D Prism Framework</h1></body></html>");
	app.get("/about", () => "<html><body><h1>About Page</h1></body></html>");
	app.get("/hello", () => "<html><body><h1>Hello World!</h1></body></html>");

	app.post("/submit", delegate(string body) {
		return "<html><body><h1>Data Received</h1><p>Body: " ~ body ~ "</p></body></html>";
	});
	app.post("/api/data", delegate(string body) {
		return `{"status": "success", "received": "` ~ body ~ `"}`;
	});

	app.run();
}
