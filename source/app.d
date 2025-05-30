import std.stdio;
import std.socket;
import std.string;
import std.conv;
import std.algorithm;
import std.array;
import std.exception;
import std.functional;
import std.typecons;
import std.format;

alias RouteHandler = string delegate();

class PrismApplication
{
	private TcpSocket server;
	private string[string] routes;

	this(ushort port = 8080)
	{
		server = new TcpSocket();
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
			scope (exit)
				client.close();

			ubyte[4096] buffer;
			auto bytesRead = client.receive(buffer);
			if (bytesRead <= 0)
				continue;

			auto request = cast(string) buffer[0 .. bytesRead];
			writeln("Received request:\n", request);

			auto path = extractPath(request);
			auto responseBody = handleRoute(path);

			string response = format(
				"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s",
				responseBody.length, responseBody
			);

			client.send(cast(ubyte[]) response);
		}
	}

	private string extractPath(string request)
	{
		auto lines = request.splitLines();
		if (lines.length == 0)
			return "/";
		auto requestLine = lines[0].split();
		if (requestLine.length >= 2)
			return requestLine[1];
		return "/";
	}

	private string handleRoute(string path)
	{
		if (auto handler = path in routes)
			return (*handler);
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
