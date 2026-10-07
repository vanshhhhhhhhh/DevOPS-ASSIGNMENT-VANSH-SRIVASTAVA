import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;

/** Minimal Hello World web server using the JDK's built-in HTTP server (no frameworks). */
public class HelloWorld {
    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));
        String page = """
                <!DOCTYPE html>
                <html>
                <head><meta charset="utf-8"><title>Java Hello World</title></head>
                <body style="font-family: sans-serif; text-align: center; margin-top: 15vh;">
                  <h1>Hello World from Java!</h1>
                  <p>Served by Java %s (com.sun.net.httpserver) inside a Docker container.</p>
                  <p>Container hostname: %s</p>
                  <p><small>Session 06 - Vansh Srivastava (24bcs10567)</small></p>
                </body>
                </html>
                """.formatted(System.getProperty("java.version"), InetAddress.getLocalHost().getHostName());
        byte[] body = page.getBytes(StandardCharsets.UTF_8);

        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);
        server.createContext("/", exchange -> {
            System.out.println(Instant.now() + " " + exchange.getRequestMethod() + " " + exchange.getRequestURI());
            exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
            exchange.sendResponseHeaders(200, body.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body);
            }
        });
        server.start();
        System.out.println("Java app listening on port " + port);
    }
}
