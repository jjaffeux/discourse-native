# Discourse Graphviz

The bundled reader plugin recognizes the official plugin's cooked
`div.graphviz[data-engine]` markup and the official theme component's
`pre[data-code-wrap="graphviz"] > code` markup. It renders locally in posts
and cooked chat messages, including locally cooked Graphviz fences. Existing
server-rendered images still use the standard image renderer.

The app runs Viz.js 3.31.0 in a local WebView worker with a 15-second layout
deadline. The worker emits SVG, and the document rasterizes it before passing
the image to Flutter. Graphviz links and external images are omitted from the
artwork. The source remains available from the diagram in the reader.

## Bundled software

`assets/viz-3.31.0.js` is the unmodified `dist/viz-global.js` from
[`@viz-js/viz@3.31.0`](https://www.npmjs.com/package/@viz-js/viz/v/3.31.0).
The archive integrity is
`sha512-r7zlQdRvcwvIpjHGgs+KNWHeE/P5/Dq7k8ZAKaMCbZqomxCBJV78gVuQYaHzFVca+kB0mX0fMW9UFevCOBG50A==`
and the script's SHA-256 is
`c9e0b310f9883910e01c66054b48b7ff4be3d8695141116635e72b0af152692e`.

Source and license references for the bundled build follow.

- [Viz.js source at c8ce050](https://github.com/mdaines/viz-js/tree/c8ce050d28eb0dc1ed1629ea32ab7f3dc117db0f) (MIT)
- [Graphviz 16.1.0 source archive](https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/16.1.0/graphviz-16.1.0.tar.gz) (EPL 2.0)
- [Expat 2.8.5 source archive](https://github.com/libexpat/libexpat/releases/download/R_2_8_5/expat-2.8.5.tar.gz) (MIT)
- [Emscripten 6.0.10 source](https://github.com/emscripten-core/emscripten/tree/6.0.10) (MIT and University of Illinois Open Source License)
