## Usage

```d
auto app = new PrismApplication(2000);

app.get("/", (context) => html("<h1>Hello</h1>"));

app.post("/submit", (context) => json(`{"received": true}`));

app.run();
```

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
```

---

Navid M © 2025
