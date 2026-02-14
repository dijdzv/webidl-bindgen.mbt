'use strict';

// Build a throws map for a spec by analyzing webref algorithms + dfns data.
// Input: spec name (e.g., "dom", "html", "fetch")
// Output: JS Map<string, string[]> ("Interface.method" -> ["ExceptionName", ...])

module.exports = async function buildThrowsMap(specName) {
  const map = new Map();

  // Layer 1: Fetch algorithms JSON
  const algoData = await fetchJson(
    `https://raw.githubusercontent.com/w3c/webref/main/ed/algorithms/${specName}.json`
  );
  if (!algoData) return map;

  const algorithms = algoData.algorithms || [];
  if (algorithms.length === 0) return map;

  // Build algorithm graph (direct throws + cross-references)
  const graph = buildAlgorithmGraph(algorithms);

  // Map Interface.method -> fragment for algorithms with method-style names
  for (const algo of algorithms) {
    const frag = getFragment(algo.href);
    if (!frag || !algo.name) continue;

    // Pattern: "Interface/method(args)" or "Interface/constructor(args)"
    const match = algo.name.match(/^(\w+)\/(\w+)\(.*\)$/);
    if (!match) continue;

    const [, iface, method] = match;
    const key = method === 'constructor'
      ? `${iface}.constructor`
      : `${iface}.${method}`;

    const exceptions = graph.resolveThrows(frag);
    if (exceptions.size > 0) {
      map.set(key, [...exceptions].sort());
    }
  }

  // Layer 2: dfns JSON for additional method discovery
  const dfnsData = await fetchJson(
    `https://raw.githubusercontent.com/w3c/webref/main/ed/dfns/${specName}.json`
  );
  if (dfnsData && dfnsData.dfns) {
    for (const dfn of dfnsData.dfns) {
      if (dfn.type !== 'method' && dfn.type !== 'constructor') continue;
      const iface = dfn.for && dfn.for[0];
      if (!iface) continue;

      let method;
      if (dfn.type === 'constructor') {
        method = 'constructor';
      } else {
        const lt = (dfn.linkingText && dfn.linkingText[0]) || '';
        method = lt.replace(/\(.*\)$/, '');
      }
      if (!method) continue;

      const key = `${iface}.${method}`;
      if (map.has(key)) continue; // Already resolved via direct algorithm

      const frag = getFragment(dfn.href);
      if (frag && graph.hasFragment(frag)) {
        const exceptions = graph.resolveThrows(frag);
        if (exceptions.size > 0) {
          map.set(key, [...exceptions].sort());
        }
      }
    }
  }

  return map;
};

async function fetchJson(url) {
  try {
    const resp = await fetch(url);
    if (!resp.ok) return null;
    return resp.json();
  } catch {
    return null;
  }
}

function getFragment(href) {
  if (!href) return null;
  try {
    const hash = new URL(href).hash;
    return hash ? hash.slice(1) : null;
  } catch {
    return null;
  }
}

function buildAlgorithmGraph(algorithms) {
  const fragments = new Set();
  const directThrows = new Map(); // fragment -> Set<string>
  const references = new Map();   // fragment -> Set<string>

  // First pass: collect all known fragments
  for (const algo of algorithms) {
    const frag = getFragment(algo.href);
    if (frag) fragments.add(frag);
  }

  // Second pass: extract throws and cross-references from STEPS (not just html heading)
  for (const algo of algorithms) {
    const frag = getFragment(algo.href);
    if (!frag) continue;
    // Collect all HTML from steps recursively
    const allHtml = collectAllStepsHtml(algo.steps || []);
    directThrows.set(frag, extractThrows(allHtml));
    references.set(frag, extractRefs(allHtml, frag, fragments));
  }

  return {
    hasFragment(frag) { return fragments.has(frag); },
    resolveThrows(startFrag) {
      const result = new Set();
      const visited = new Set();
      const queue = [startFrag];
      while (queue.length > 0) {
        const frag = queue.shift();
        if (visited.has(frag)) continue;
        visited.add(frag);
        const dt = directThrows.get(frag);
        if (dt) for (const ex of dt) result.add(ex);
        const refs = references.get(frag);
        if (refs) for (const ref of refs) {
          if (!visited.has(ref)) queue.push(ref);
        }
      }
      return result;
    }
  };
}

function collectAllStepsHtml(steps) {
  let html = '';
  for (const step of steps) {
    if (step.html) html += step.html + ' ';
    if (step.steps) html += collectAllStepsHtml(step.steps);
  }
  return html;
}

function extractThrows(html) {
  if (!html) return new Set();
  const exceptions = new Set();

  // Strip HTML tags first, then match on clean text
  const clean = html.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ');

  const patterns = [
    // "ErrorName" DOMException (quoted exception name before DOMException, with optional spaces from tag stripping)
    /[Tt]hrow\s+(?:a[n]?\s+)?"\s*(\w+)\s*"\s+DOMException/g,
    // throw a TypeError / throw a RangeError (built-in JS error types)
    /[Tt]hrow\s+a[n]?\s+"?\s*(\w+Error)\s*"?/g,
    // "ErrorName" DOMException (without explicit "throw" verb)
    /"\s*(\w+)\s*"\s+DOMException/g,
  ];

  for (const regex of patterns) {
    regex.lastIndex = 0;
    let m;
    while ((m = regex.exec(clean)) !== null) {
      const name = m[1];
      // Filter out non-exception matches
      if (name !== 'DOMException' && name !== 'Error' && name !== 'is') {
        exceptions.add(name);
      }
    }
  }

  return exceptions;
}

function extractRefs(html, selfFragment, allFragments) {
  if (!html) return new Set();
  const refs = new Set();
  const regex = /href="[^"]*#([^"]+)"/g;
  let m;
  while ((m = regex.exec(html)) !== null) {
    const frag = m[1];
    if (frag !== selfFragment && allFragments.has(frag)) {
      refs.add(frag);
    }
  }
  return refs;
}
