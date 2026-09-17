// Renders the "Other things I've built" section from site/projects.json.
//
// WHY THIS IS RENDERED RATHER THAN WRITTEN INTO THE HTML
//
// The same four projects are needed in three places: this page, the demo
// catalogue in demo-api.js, and scripts/seed-projects.py, which writes them
// into the real links catalogue when a cluster is up. Writing them out three
// times is the duplication this project keeps paying for -- so all three read
// one file instead, and there is no copy to drift.
//
// The cost is that this section needs JavaScript. That is acceptable here and
// would not be for the rest of the page: the architecture, the stack table and
// the repo list are all static HTML and render with scripts blocked.
//
// A project with `url: null` is NOT RENDERED. A placeholder that renders is
// worse than one that does not -- a dead link on a portfolio page reads as
// carelessness, not as a TODO. If nothing has a URL yet, the whole section
// stays hidden rather than showing an empty heading.

(function () {
  "use strict";

  const section = document.getElementById("projects");
  const list = document.getElementById("projects-list");
  if (!section || !list) return;

  function card(p) {
    const li = document.createElement("li");

    const a = document.createElement("a");
    a.href = p.url;
    // Same pairing as the dashboard: a new tab, and the rel that makes that
    // safe. noopener stops the opened page reaching back through
    // window.opener; noreferrer stops this site announcing itself.
    a.target = "_blank";
    a.rel = "noopener noreferrer";

    const name = document.createElement("strong");
    // textContent throughout, never innerHTML -- same rule as the dashboard.
    // This data is ours rather than user-submitted, but the habit is the
    // protection; an exception made once is an exception made again.
    name.textContent = p.name;
    a.appendChild(name);

    if (p.blurb) {
      const blurb = document.createElement("span");
      blurb.className = "blurb";
      blurb.textContent = p.blurb;
      a.appendChild(blurb);
    }

    if (p.stack) {
      const stack = document.createElement("span");
      stack.className = "stack";
      stack.textContent = p.stack;
      a.appendChild(stack);
    }

    li.appendChild(a);

    // The repo is a secondary link, not a replacement for the live one.
    if (p.repo) {
      const repo = document.createElement("a");
      repo.className = "repo";
      repo.href = p.repo;
      repo.target = "_blank";
      repo.rel = "noopener noreferrer";
      repo.textContent = "source";
      li.appendChild(repo);
    }

    return li;
  }

  fetch("/projects.json")
    .then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    })
    .then(function (data) {
      // `public` is the load-bearing filter, not `url`.
      //
      // Three of the owner's projects are reachable only from their own
      // machine -- two localhost dev servers and a personal Xiaomi account.
      // Those are correct entries for a private start page and dead links on
      // a public portfolio page, where every visitor would get a connection
      // error. Rendering them here would be the single most obviously broken
      // thing on the site.
      const ready = (data.projects || []).filter(function (p) {
        return p.url && p.public;
      });
      if (!ready.length) return; // section stays hidden
      ready.forEach(function (p) { list.appendChild(card(p)); });
      section.hidden = false;
    })
    .catch(function () {
      // Deliberately silent. This section is additive; the page is complete
      // without it, and an error banner about a missing side-list would be
      // noisier than the omission it reports.
    });
})();
