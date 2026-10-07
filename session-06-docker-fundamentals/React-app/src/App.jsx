import { useState, version } from "react";

export default function App() {
  const [clicks, setClicks] = useState(0);

  return (
    <main style={{ fontFamily: "sans-serif", textAlign: "center", marginTop: "15vh" }}>
      <h1>Hello World from React!</h1>
      <p>
        This page was rendered in the browser by React {version}. The app was built with Vite in a
        Node build stage and is served as static files by nginx.
      </p>
      <button onClick={() => setClicks(clicks + 1)}>Clicked {clicks} times</button>
      <p>
        <small>Session 06 - Vansh Srivastava (24bcs10567)</small>
      </p>
    </main>
  );
}
