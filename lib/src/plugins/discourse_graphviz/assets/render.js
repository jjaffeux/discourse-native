/* The worker can be terminated even while Graphviz is computing a layout. */
function graphvizWorker() {
  self.onmessage = async ({ data: { source, engine } }) => {
    try {
      const viz = await self.Viz.instance();
      const svg = viz.renderString(source, { engine, format: "svg" });
      if (svg.length > 4000000) throw new Error("The diagram is too large.");
      // Drop the XML declaration and external SVG doctype.
      const start = svg.indexOf("<svg ");
      if (start === -1) throw new Error("No diagram was produced.");
      self.postMessage({ svg: svg.slice(start) });
    } catch (error) {
      self.postMessage({ message: String(error.message || error).slice(0, 500) });
    }
  };
}

function graphvizLayout(runtime, options) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(new Blob(
      [runtime, "\n(", graphvizWorker.toString(), ")();"],
      { type: "text/javascript" },
    ));
    let worker;
    try {
      worker = new Worker(url);
    } finally {
      URL.revokeObjectURL(url);
    }
    const finish = (callback, result) => {
      clearTimeout(timeout);
      worker.terminate();
      callback(result);
    };
    const timeout = setTimeout(
      () => finish(reject, new Error("Diagram rendering timed out.")),
      15000,
    );
    worker.onmessage = ({ data }) => {
      if (typeof data.svg === "string") {
        finish(resolve, data.svg);
      } else {
        finish(reject, new Error(data.message));
      }
    };
    worker.onerror = () => finish(reject, new Error("Could not start Graphviz."));
    worker.postMessage(options);
  });
}

function graphvizImage(svg) {
  const namespace = "http://www.w3.org/2000/svg";
  const xml = new DOMParser().parseFromString(svg, "image/svg+xml");
  const element = xml.documentElement;
  if (element.localName !== "svg" || element.namespaceURI !== namespace ||
      xml.querySelector("parsererror")) {
    throw new Error("Graphviz produced invalid artwork.");
  }
  // Rasterize only Graphviz's drawing elements. Preserve local paint
  // references for gradients but strip links and external image references.
  const allowed = new Set([
    "svg", "g", "a", "path", "polygon", "polyline", "ellipse", "circle", "rect",
    "line", "text", "tspan", "title", "desc", "defs", "linearGradient",
    "radialGradient", "stop",
  ]);
  for (const child of [element, ...element.querySelectorAll("*")]) {
    if (child.namespaceURI !== namespace || !allowed.has(child.localName)) {
      child.remove();
      continue;
    }
    for (const attribute of [...child.attributes]) {
      const name = attribute.localName.toLowerCase();
      const value = attribute.value;
      if (name.startsWith("on") || name === "href" || name === "style" ||
          (/url\s*\(/i.test(value) && !/^url\(#[\w.-]+\)$/.test(value))) {
        child.removeAttributeNode(attribute);
      }
    }
  }
  return element;
}

async function renderNativeGraphviz(runtime, options) {
  const report = (value) => NativeGraphviz.postMessage(JSON.stringify(value));
  let url;
  try {
    const element = graphvizImage(await graphvizLayout(runtime, options));
    const { width, height } = element.viewBox.baseVal;
    if (!(width > 0 && height > 0 && Number.isFinite(width * height))) {
      throw new Error("The diagram has invalid dimensions.");
    }
    const scale = Math.min(2, 4096 / width, 4096 / height,
      Math.sqrt(4000000 / (width * height)));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.floor(width * scale));
    canvas.height = Math.max(1, Math.floor(height * scale));
    element.setAttribute("width", String(canvas.width));
    element.setAttribute("height", String(canvas.height));
    url = URL.createObjectURL(new Blob(
      [new XMLSerializer().serializeToString(element)],
      { type: "image/svg+xml;charset=utf-8" },
    ));
    const image = new Image();
    image.src = url;
    await image.decode();
    canvas.getContext("2d").drawImage(image, 0, 0);
    report({ type: "rendered", width, height,
      png: canvas.toDataURL("image/png").split(",")[1] });
  } catch (error) {
    report({ type: "error", message: String(error.message || error).slice(0, 500) });
  } finally {
    if (url) URL.revokeObjectURL(url);
  }
}
