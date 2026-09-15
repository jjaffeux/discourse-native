/* The WebView is a local rendering worker. Only a bounded PNG crosses back. */
async function renderNativeMermaid({ source, dark }) {
  const report = (value) => NativeMermaid.postMessage(JSON.stringify(value));
  let imageUrl;
  try {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      suppressErrorRendering: true,
      maxTextSize: 50000,
      maxEdges: 500,
      theme: dark ? "dark" : "default",
      fontFamily: "Arial, sans-serif",
      htmlLabels: false,
      flowchart: { htmlLabels: false },
      journey: { textPlacement: "svg" },
      c4: { textPlacement: "svg" },
      secure: [
        "secure", "securityLevel", "startOnLoad", "suppressErrorRendering",
        "maxTextSize", "maxEdges", "htmlLabels", "flowchart", "journey", "c4", "dompurifyConfig",
      ],
    });
    const root = document.getElementById("diagram");
    // Width-dependent renderers (notably Gantt) measure this container. The
    // native worker's viewport is only 1px, so never render into document.body.
    const { svg } = await mermaid.render("native-diagram", source, root);
    root.innerHTML = svg;
    const element = root.querySelector("svg");
    if (!element) throw new Error("No diagram was produced.");
    // Mermaid 11.15 positions circular mindmap SVG labels at the center but
    // leaves their anchor at "start". Rectangular labels already offset x.
    for (const text of element.querySelectorAll(".mindmap-node > circle ~ .label text")) {
      text.setAttribute("text-anchor", "middle");
    }
    // Journey assigns its section background class to SVG text too. Restore
    // the active theme's text color when using its non-HTML label renderer.
    if (element.querySelector("text.journey-section")) {
      const color = mermaid.mermaidAPI.getConfig().themeVariables.textColor;
      for (const text of element.querySelectorAll("text.journey-section, text.task")) {
        text.style.fill = color;
      }
    }
    // HTML labels cannot be safely painted onto a canvas. Mermaid's native SVG
    // labels are selected above, including for markdown labels in flowcharts.
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
