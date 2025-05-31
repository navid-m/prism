## Usage

```d
auto app = new PrismApplication(2000);

app.get("/", (context) => html("<h1>Hello</h1>"));

app.post("/submit", (context) => json(`{"received": true}`));

app.run();
```

## Features

-  Fluent and intuitive URL routing
-  WebSocket support
-  Static file serving middleware
-  Full support for HTTP methods: GET, POST, PUT, PATCH, DELETE
-  Automatic handling of all MIME types

## Route Parameters

Supports routes like:

```d
app.get("/users/:id", (context) {
    auto id = context.params["id"];
    return text("User ID: " ~ id);
});
```

## Query Parameters

```d
app.get("/search", (context) {
    auto q = context.query.get("q", "");
    return text("Search query: " ~ q);
});
```

## Response Types

```d
html("<h1>HTML</h1>");
json(`{"key": "value"}`);
text("Plain text");
blob([0x42, 0x69, 0x6E, 0x61, 0x72, 0x79]);
```

---

Navid M © 2025

No warranty. Not ever.
