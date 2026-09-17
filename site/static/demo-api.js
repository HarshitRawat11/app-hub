// A stand-in for gateway's API, so the REAL dashboard runs with no backend.
//
// WHY A FETCH SHIM RATHER THAN A MODIFIED app.js
//
// app.js is vendored from gateway BYTE FOR BYTE and checked by
// `scripts/check-doc-drift.py`. The moment this demo needs its own edited copy,
// the two versions start drifting and the portfolio page quietly stops showing
// the thing it claims to show -- which is the failure this whole project keeps
// meeting in other clothes.
//
// So nothing in app.js changes. Every call it makes goes through one `api()`
// helper that calls `fetch(path, ...)`, so replacing `window.fetch` before
// app.js loads intercepts all of them. The dashboard cannot tell the
// difference, which is the point: what you see here is the real UI, not a
// screenshot or a re-implementation.
//
// THE SCRIPT ORDER IN demo.html IS LOAD-BEARING. This must be parsed before
// app.js, or app.js will have captured the real `fetch` and every request will
// 404 against Netlify's static host.
//
// WHAT IS DELIBERATELY NOT FAKED: nothing is persisted. Adds and deletes live
// in the array below for as long as the tab is open. A reload restores the
// seed data. localStorage would have been easy and would have made the demo
// lie in a subtler way -- someone returning a week later would see their own
// edits and think it was a live backend.

(function () {
  "use strict";

  // Captured BEFORE window.fetch is replaced below, so the shim can still make
  // one real network request -- for projects.json. Calling the replaced fetch
  // would route it back into this shim and 404 against its own router.
  const realFetch = window.fetch.bind(window);

  // The seed catalogue. Real tools, because a portfolio demo full of "Example
  // Service 1" tells a visitor nothing about what the thing is for.
  let links = [
    { id: "8f14e45f-ceea-467a-9e1e-7a6b1d3f2c01", name: "Grafana",     url: "https://grafana.com",        category: "monitoring", icon: "📊" },
    { id: "c9f0f895-fb98-4b0a-9b1c-5d2e6a7b8c02", name: "Prometheus",  url: "https://prometheus.io",      category: "monitoring", icon: "🔥" },
    { id: "45c48cce-2e2d-4fb1-9b4a-0c1d2e3f4a03", name: "n8n",         url: "https://n8n.io",             category: "automation", icon: "🔗" },
    { id: "d3d94468-02a4-4c7f-9bd1-2e3f4a5b6c04", name: "Argo CD",     url: "https://argo-cd.readthedocs.io", category: "automation", icon: "🚀" },
    { id: "6512bd43-d9ca-4e6f-8b1f-3a4b5c6d7e05", name: "AWS Console", url: "https://console.aws.amazon.com", category: "cloud",  icon: "☁️" },
    { id: "c20ad4d7-6fe9-4779-8c1f-4b5c6d7e8f06", name: "Terraform",   url: "https://registry.terraform.io", category: "cloud",   icon: "🏗️" },
    { id: "c51ce410-c124-4a53-9a1b-5c6d7e8f9a07", name: "app-hub",     url: "https://github.com/HarshitRawat11/app-hub", category: "code", icon: "🐙" },
    { id: "aab32389-22bc-4b8a-8b1c-6d7e8f9a0b08", name: "Unreachable host", url: "https://nope.invalid", category: "code",       icon: "💀" },
  ];

  // Probe results, mirroring aggregator's shape. One is deliberately down --
  // a status panel that is all green demonstrates nothing, and the grey/red
  // distinction is most of what the panel is for.
  const probes = {
    "aab32389-22bc-4b8a-8b1c-6d7e8f9a0b08":
      { status: "down", http_status: null, latency_ms: 218, detail: "ConnectError" },
  };

  // The owner's other projects, merged in from the SAME file the landing page
  // renders from (site/projects.json) rather than repeated here. Four links
  // written out in three places is the duplication this project keeps paying
  // for; one file with three readers has nothing to drift.
  //
  // Loaded once, lazily, and every failure mode is survivable: a missing file,
  // a parse error or an entry with no URL simply means the demo catalogue is
  // the seed list without the projects. The dashboard is not broken by the
  // absence of an extra category.
  let projectsMerged = null;

  function mergeProjects() {
    if (projectsMerged) return projectsMerged;
    projectsMerged = realFetch("/projects.json")
      .then(function (r) { return r.ok ? r.json() : { projects: [] }; })
      .then(function (data) {
        (data.projects || []).forEach(function (p, i) {
          // `public` matters here for the same reason it does on the landing
          // page: THIS DEMO IS ALSO PUBLIC. It is served from the same Netlify
          // site, so a localhost entry would give every visitor a card that
          // does nothing -- and one that reports "up" in the status panel,
          // because the stub does not really probe anything. A dead link that
          // claims to be healthy is worse than no link.
          if (!p.url || !p.public) return; // see projects.json
          links.push({
            // Deterministic ids so a reload does not reshuffle them, and
            // prefixed so they cannot collide with the seed uuids above.
            id: "project-" + i + "-" + p.name.toLowerCase().replace(/[^a-z0-9]+/g, "-"),
            name: p.name,
            url: p.url,
            category: "projects",
            icon: p.icon || "🧱",
          });
        });
      })
      .catch(function () { /* demo works without them */ });
    return projectsMerged;
  }

  function probeFor(id) {
    return probes[id] || { status: "up", http_status: 200, latency_ms: 40 + ((parseInt(id.slice(0, 4), 16) || 0) % 900), detail: null };
  }

  // A minimal Response. app.js touches exactly `.ok`, `.status` and `.json()`,
  // so faking the whole interface would be noise -- but `ok` must be derived
  // from the status rather than hardcoded, or the error paths below never fire.
  function reply(status, body) {
    return Promise.resolve({
      ok: status >= 200 && status < 300,
      status: status,
      json: function () {
        return body === undefined
          ? Promise.reject(new Error("no body"))
          : Promise.resolve(body);
      },
    });
  }

  function uuid() {
    if (window.crypto && window.crypto.randomUUID) return window.crypto.randomUUID();
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
      const r = (Math.random() * 16) | 0;
      return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
    });
  }

  // Real requests are not instant, and a demo that answers in 0ms hides the
  // loading states the dashboard was built to have.
  function slow(value) {
    return new Promise(function (resolve) {
      setTimeout(function () { resolve(value); }, 120 + Math.random() * 180);
    });
  }

  window.fetch = function (path, options) {
    const opts = options || {};
    const method = (opts.method || "GET").toUpperCase();
    // Tolerate an absolute URL, since fetch accepts one and app.js may not
    // always pass a bare path.
    const url = String(path).replace(/^https?:\/\/[^/]+/, "");

    if (method === "GET" && url === "/links") {
      return mergeProjects().then(function () { return slow(reply(200, links.slice())); });
    }

    if (method === "GET" && url === "/status") {
      // Also waits for the merge. app.js happens to call /links first today,
      // which would make this redundant -- but relying on that would make the
      // status dots silently miss the projects the day the call order changes.
      return mergeProjects().then(function () {
        const decorated = links.map(function (l) {
          return Object.assign({}, l, { probe: probeFor(l.id) });
        });
        const summary = { total: decorated.length, up: 0, down: 0, blocked: 0 };
        decorated.forEach(function (l) { summary[l.probe.status] += 1; });
        return slow(reply(200, {
          checked_at: new Date().toISOString(),
          age_seconds: 0.0,
          cached: false,
          summary: summary,
          links: decorated,
        }));
      });
    }

    if (method === "POST" && url === "/links") {
      let body;
      try {
        body = JSON.parse(opts.body);
      } catch (e) {
        // 422 is what links-service returns for an unparseable body, and
        // gateway passes it straight through.
        return slow(reply(422, { detail: "Invalid JSON" }));
      }
      const created = {
        id: uuid(),
        name: body.name,
        url: body.url,
        category: body.category,
        icon: body.icon || null,
      };
      links.push(created);
      return slow(reply(201, created));
    }

    const del = url.match(/^\/links\/(.+)$/);
    if (method === "DELETE" && del) {
      const id = decodeURIComponent(del[1]);
      const before = links.length;
      links = links.filter(function (l) { return l.id !== id; });
      // 404 when nothing matched, exactly as the real service does -- this is
      // the branch gateway passes through rather than mapping to a 502.
      return slow(links.length === before ? reply(404, { detail: "Link not found" })
                                          : reply(204, undefined));
    }

    // Anything unrecognised fails loudly rather than resolving to something
    // plausible. A shim that silently answers 200 to a path it does not model
    // would make a broken demo look like a working one.
    return slow(reply(404, { detail: "not part of the demo: " + method + " " + url }));
  };
})();
