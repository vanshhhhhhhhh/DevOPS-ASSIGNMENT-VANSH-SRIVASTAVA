// Small "task list" API written in TypeScript. It only uses Node's built-in modules,
// so the compiled JavaScript needs no node_modules at runtime.
import { createServer, IncomingMessage, ServerResponse } from "node:http";
import { hostname } from "node:os";

interface Task {
  id: number;
  title: string;
  done: boolean;
}

const PORT = Number(process.env.PORT ?? 3000);
const VARIANT = process.env.IMAGE_VARIANT ?? "unknown";

const tasks: Task[] = [
  { id: 1, title: "Write a single-stage Dockerfile", done: true },
  { id: 2, title: "Rewrite it as a multi-stage Dockerfile", done: true },
  { id: 3, title: "Compare the image sizes", done: false },
];

function send(res: ServerResponse, status: number, type: string, body: string): void {
  res.writeHead(status, { "Content-Type": type });
  res.end(body);
}

function handler(req: IncomingMessage, res: ServerResponse): void {
  console.log(`${new Date().toISOString()} ${req.method} ${req.url}`);
  switch (req.url) {
    case "/health":
      return send(res, 200, "application/json", JSON.stringify({ status: "ok" }));
    case "/api/tasks":
      return send(res, 200, "application/json", JSON.stringify({ variant: VARIANT, tasks }));
    case "/": {
      const rows = tasks.map((t) => `<li>${t.done ? "[x]" : "[ ]"} ${t.title}</li>`).join("");
      return send(
        res,
        200,
        "text/html; charset=utf-8",
        `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Node.js Task API</title></head>
<body style="font-family: sans-serif; margin: 40px;">
<h1>Node.js (TypeScript) Task API</h1>
<p>Image variant: <b>${VARIANT}</b> | Node ${process.version} | container ${hostname()}</p>
<ul>${rows}</ul>
<p>JSON: <code>/api/tasks</code>, health: <code>/health</code></p>
<p><small>Session 07 Task 3 - Vansh Srivastava (24bcs10567)</small></p>
</body></html>`
      );
    }
    default:
      return send(res, 404, "application/json", JSON.stringify({ error: "not found" }));
  }
}

const server = createServer(handler);
server.listen(PORT, () => console.log(`Task API (${VARIANT}) listening on port ${PORT}`));
process.on("SIGTERM", () => server.close(() => process.exit(0)));
