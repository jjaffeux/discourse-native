/* The WebView is a local rendering worker. Only a bounded PNG crosses back. */
async function renderNativeMermaid({ source, dark }) {
  const report = (value) => NativeMermaid.postMessage(JSON.stringify(value));
  let imageUrl;
  try {
    const root = document.getElementById("diagram");
    const { svg } = pele.render(source, {
      limit: 50000,
      outputLimit: 4000000,
      maxEdges: 500,
      fontFamily: "Arial, sans-serif",
      fontFamilyMono: "monospace",
      idPrefix: "native-diagram",
      responsive: false,
      maxWidth: 1200,
      autoDirection: false,
      links: false,
      images: false,
    });
    root.innerHTML = svg;
    const element = root.querySelector("svg");
    if (!element) throw new Error("No diagram was produced.");
    // Keep variables on the SVG itself: inherited page styles do not travel
    // with the standalone image used for PNG export.
    const palette = dark ? {
      bg: "#202020", fg: "#eeeeee", muted: "#aaaaaa", line: "#dddddd",
      surface: "#303030", "surface-alt": "#404040", border: "#888888",
      accent: "#8aaaff", critical: "#ff8585",
    } : {
      bg: "#ffffff", fg: "#1f1f1f", muted: "#6e6e6e", line: "#1f1f1f",
      surface: "#f3f3f3", "surface-alt": "#e6e6e6", border: "#8a8a8a",
      accent: "#5b7bd5", critical: "#c43c3b",
    };
    for (const [name, color] of Object.entries(palette)) {
      element.style.setProperty(`--pele-${name}`, color);
    }
    if (element.querySelector("foreignObject")) {
      throw new Error("This diagram requires HTML labels. Use plain text labels.");
    }
    const box = element.viewBox.baseVal;
    const width = box.width || element.getBoundingClientRect().width;
    const height = box.height || element.getBoundingClientRect().height;
    if (!(width > 0 && height > 0 && Number.isFinite(width + height))) {
      throw new Error("The diagram has invalid dimensions.");
    }
    // Keep decoded artwork below 16 MiB, even for unusually long diagrams.
    const scale = Math.min(2, 4096 / width, 4096 / height,
      Math.sqrt(4000000 / (width * height)));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.floor(width * scale));
    canvas.height = Math.max(1, Math.floor(height * scale));
    element.setAttribute("width", String(width));
    element.setAttribute("height", String(height));
    element.style.maxWidth = "none";
    element.setAttribute("xmlns", "http://www.w3.org/2000/svg");
    imageUrl = URL.createObjectURL(new Blob(
      [new XMLSerializer().serializeToString(element)],
      { type: "image/svg+xml;charset=utf-8" },
    ));
    const image = new Image();
    image.src = imageUrl;
    await image.decode();
    canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height);
    report({ type: "rendered", width, height,
      png: canvas.toDataURL("image/png").split(",")[1] });
  } catch (error) {
    report({ type: "error", message: String(error.message || error).slice(0, 500) });
  } finally {
    if (imageUrl) URL.revokeObjectURL(imageUrl);
    document.getElementById("diagram").replaceChildren();
  }
}
