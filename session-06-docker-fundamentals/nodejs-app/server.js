// Minimal Hello World web server using only Node's built-in http module (no npm dependencies).
const http = require("http");
const os = require("os");

const PORT = process.env.PORT || 3000;

const page = `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Node.js Hello World</title></head>
<body style="font-family: sans-serif; text-align: center; margin-top: 15vh;">
  <h1>Hello World from Node.js!</h1>
  <p>Served by Node ${process.version} inside a Docker container.</p>
  <p>Container hostname: ${os.hostname()}</p>
  <p><small>Session 06 - Vansh Srivastava (24bcs10567)</small></p>
</body>
</html>`;

const server = http.createServer((req, res) => {
  console.log(`${new Date().toISOString()} ${req.method} ${req.url}`);
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(page);
});

server.listen(PORT, () => console.log(`Node.js app listening on port ${PORT}`));

// Exit cleanly when Docker sends SIGTERM (docker stop).
process.on("SIGTERM", () => server.close(() => process.exit(0)));
