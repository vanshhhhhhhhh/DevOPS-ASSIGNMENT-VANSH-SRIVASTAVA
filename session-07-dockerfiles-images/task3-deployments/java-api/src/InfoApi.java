import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.lang.management.ManagementFactory;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;

/** Small "runtime info" API using only the JDK (java.base + jdk.httpserver modules). */
public class InfoApi {
    private static final String VARIANT = System.getenv().getOrDefault("IMAGE_VARIANT", "unknown");

    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);

        server.createContext("/health", ex -> send(ex, 200, "application/json", "{\"status\":\"ok\"}"));
        server.createContext("/api/info", ex -> send(ex, 200, "application/json", infoJson()));
        server.createContext("/", ex -> {
            if (!ex.getRequestURI().getPath().equals("/")) {
                send(ex, 404, "application/json", "{\"error\":\"not found\"}");
                return;
            }
            String html = """
                    <!DOCTYPE html><html><head><meta charset="utf-8"><title>Java Info API</title></head>
                    <body style="font-family: sans-serif; margin: 40px;">
                    <h1>Java Runtime Info API</h1>
                    <p>Image variant: <b>%s</b> | Java %s | container %s</p>
                    <p>Modules in this Java runtime: <b>%d</b></p>
                    <p>JSON: <code>/api/info</code>, health: <code>/health</code></p>
                    <p><small>Session 07 Task 3 - Vansh Srivastava (24bcs10567)</small></p>
                    </body></html>
                    """.formatted(VARIANT, System.getProperty("java.version"), host(), moduleCount());
            send(ex, 200, "text/html; charset=utf-8", html);
        });

        server.start();
        System.out.println("Info API (" + VARIANT + ") listening on port " + port);
    }

    private static String infoJson() {
        return "{\"variant\":\"%s\",\"javaVersion\":\"%s\",\"vendor\":\"%s\",\"modules\":%d,\"uptimeMs\":%d}"
                .formatted(VARIANT, System.getProperty("java.version"), System.getProperty("java.vendor"),
                        moduleCount(), ManagementFactory.getRuntimeMXBean().getUptime());
    }

    private static long moduleCount() {
        return ModuleLayer.boot().modules().size();
    }

    private static String host() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (IOException e) {
            return "unknown";
        }
    }

    private static void send(HttpExchange ex, int status, String type, String body) throws IOException {
        System.out.println(Instant.now() + " " + ex.getRequestMethod() + " " + ex.getRequestURI() + " " + status);
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().set("Content-Type", type);
        ex.sendResponseHeaders(status, bytes.length);
        try (OutputStream os = ex.getResponseBody()) {
            os.write(bytes);
        }
    }
}
