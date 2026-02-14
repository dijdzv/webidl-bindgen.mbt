'use strict';

// Build a throws map for a spec by analyzing webref algorithms + dfns data.
// Input: spec name (e.g., "dom", "html", "fetch")
// Output: JS Map<string, string[]> ("Interface.method" -> ["ExceptionName", ...])

// Module-level cache: maps @webref/idl spec name -> actual algorithms file name
// e.g., "IndexedDB" -> "IndexedDB-3", "dom" -> "dom" (exact)
let _algoNameMap = null;

async function resolveAlgoName(specName) {
  if (!_algoNameMap) {
    _algoNameMap = new Map();
    for (let page = 1; page <= 5; page++) {
      try {
        const r = await fetch(
          `https://api.github.com/repos/w3c/webref/contents/ed/algorithms?per_page=100&page=${page}`
        );
        if (!r.ok) break;
        const files = await r.json();
        if (!Array.isArray(files) || files.length === 0) break;
        for (const f of files) {
          const name = f.name.replace('.json', '');
          _algoNameMap.set(name, name);
          // Map base name (without version suffix) to versioned name
          // e.g., "IndexedDB-3" -> base "IndexedDB" maps to "IndexedDB-3"
          const base = name.replace(/-[\d.]+$/, '');
          if (base !== name && !_algoNameMap.has(base)) {
            _algoNameMap.set(base, name);
          }
        }
      } catch {
        break;
      }
    }
  }
  return _algoNameMap.get(specName) || null;
}

module.exports = async function buildThrowsMap(specName) {
  const map = new Map();

  // Layer 1: Fetch algorithms JSON (with version-suffix fallback)
  const resolvedName = await resolveAlgoName(specName);
  if (!resolvedName) return map;

  const algoData = await fetchJson(
    `https://raw.githubusercontent.com/w3c/webref/main/ed/algorithms/${resolvedName}.json`
  );
  if (!algoData) return map;

  const algorithms = algoData.algorithms || [];
  if (algorithms.length === 0) return map;

  // Build algorithm graph (direct throws + cross-references)
  const graph = buildAlgorithmGraph(algorithms);

  // Layer 2: Spec HTML bridge
  // Some algorithms have empty steps in webref (Reffy couldn't extract them).
  // Fetch spec HTML to fill in missing cross-references and bridge method dfns
  // to concept algorithms they delegate to.
  const specUrl = algoData.spec && algoData.spec.url;
  const specHtml = specUrl ? await fetchText(specUrl) : null;
  if (specHtml) {
    graph.augmentFromSpecHtml(specHtml);
  }

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

  // Layer 3: dfns JSON + spec HTML bridge for method discovery
  // Use resolved name (webref uses consistent naming across algorithms/dfns)
  const dfnsData = await fetchJson(
    `https://raw.githubusercontent.com/w3c/webref/main/ed/dfns/${resolvedName}.json`
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
      if (!frag) continue;

      // Try direct fragment match (algorithm graph, now augmented with spec HTML refs)
      if (graph.hasFragment(frag)) {
        const exceptions = graph.resolveThrows(frag);
        if (exceptions.size > 0) {
          map.set(key, [...exceptions].sort());
          continue;
        }
      }

      // Spec HTML bridge: find method dfn in spec HTML and follow links to algorithms
      if (specHtml) {
        const exceptions = resolveViaSpecHtml(specHtml, frag, graph);
        if (exceptions.size > 0) {
          map.set(key, [...exceptions].sort());
        }
      }
    }
  }

  return map;
};

// Find a fragment ID in spec HTML and resolve throws via linked algorithm fragments
function resolveViaSpecHtml(specHtml, frag, graph) {
  const exceptions = new Set();
  const idIdx = specHtml.indexOf(`id="${frag}"`);
  if (idIdx < 0) return exceptions;

  // Extract from the id to the next closing block element
  const contextEnd = Math.min(specHtml.length, idIdx + 2000);
  const context = specHtml.slice(idIdx, contextEnd);
  const blockEnd = context.search(/<\/(p|dd|li|ol)>/i);
  const block = blockEnd > 0 ? context.slice(0, blockEnd) : context.slice(0, 500);

  // Find href fragments that point to known algorithms
  const hrefRegex = /href="#([^"]+)"/g;
  let m;
  while ((m = hrefRegex.exec(block)) !== null) {
    if (graph.hasFragment(m[1])) {
      for (const ex of graph.resolveThrows(m[1])) {
        exceptions.add(ex);
      }
    }
  }
  return exceptions;
}

async function fetchJson(url) {
  try {
    const resp = await fetch(url);
    if (!resp.ok) return null;
    return resp.json();
  } catch {
    return null;
  }
}

async function fetchText(url) {
  try {
    const resp = await fetch(url);
    if (!resp.ok) return null;
    return resp.text();
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

    // Augment graph with references from spec HTML for algorithms with empty steps.
    // Some algorithms (e.g., "append" in DOM) have empty steps in webref because
    // Reffy couldn't extract them, but their spec HTML definition contains links
    // to other algorithm fragments.
    augmentFromSpecHtml(specHtml) {
      for (const frag of fragments) {
        const refs = references.get(frag);
        // Only augment if this fragment has no references from steps
        if (refs && refs.size > 0) continue;
        const dt = directThrows.get(frag);
        if (dt && dt.size > 0) continue;

        const idIdx = specHtml.indexOf(`id="${frag}"`);
        if (idIdx < 0) continue;

        // Extract the definition block
        const contextEnd = Math.min(specHtml.length, idIdx + 2000);
        const context = specHtml.slice(idIdx, contextEnd);
        // Look for an <ol> algorithm block after the dfn, or a <p> if one-liner
        const blockEnd = context.search(/<\/(p|dd|li|ol)>/i);
        const block = blockEnd > 0 ? context.slice(0, blockEnd) : context.slice(0, 500);

        // Extract throws from the definition text itself
        const specThrows = extractThrows(block);
        if (specThrows.size > 0) {
          directThrows.set(frag, specThrows);
        }

        // Extract cross-references to other known algorithm fragments
        const hrefRegex = /href="#([^"]+)"/g;
        const newRefs = new Set();
        let m;
        while ((m = hrefRegex.exec(block)) !== null) {
          if (m[1] !== frag && fragments.has(m[1])) {
            newRefs.add(m[1]);
          }
        }
        if (newRefs.size > 0) {
          references.set(frag, newRefs);
        }
      }
    },

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
